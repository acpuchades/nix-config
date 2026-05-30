{ config, lib, pkgs, ... }:

# Host-specific egress confinement for the Transmission daemon: force ALL of its
# traffic out the ProtonVPN BitTorrent tunnel (wgproton-bt), with a kill switch
# so its real IP can never leak to the ISP if the tunnel drops, plus a NAT-PMP
# renewal loop that feeds Proton's forwarded port to Transmission.
#
# Coupled to the homeserver's topology (the wgproton-bt tunnel, the LAN, the
# transmission UID), so it lives here rather than in the reusable modules/ tree —
# the same split as machines/homeserver/vpn-egress.nix vs modules/wireguard-client.
# modules/transmission-server stays completely VPN-unaware; this file is the only
# place the daemon and the tunnel are wired together, and it does so purely by the
# daemon's (upstream-static) UID.

let
  iface = "wgproton-bt";                                # ProtonVPN P2P tunnel
  uid = config.ids.uids.transmission;                  # static uid 70 — owner match
  fwmark = "0x2";
  table = "43";                                         # wgproton-bt's dedicated table
  localNetworks = [ "192.168.2.0/24" "10.0.0.0/24" ];  # LAN + wg0 subnet stay on main route
  gw = "10.2.0.1";                                      # tunnel gateway (Proton NAT-PMP)
  rpc = "127.0.0.1:${toString config.my.transmission-server.rpcPort}";

  ip = "${pkgs.iproute2}/bin/ip";
  ksChain = "transmission-ks";   # IPv4 kill-switch chain
  ksChain6 = "transmission-ks6"; # IPv6 kill-switch chain

  # `ip rule` lines, parameterised by verb ("add"/"del"). Local networks are
  # looked up in main (normal routing) ahead of the fwmark rule, so marked
  # traffic to the LAN/VPN never gets shoved into the tunnel. Priorities 1100/1101
  # sit clear of vpn-egress's 1000/1001.
  mkRuleLines = verb:
    (map (net: "${ip} rule ${verb} from all to ${net} lookup main priority 1100") localNetworks)
    ++ [ "${ip} rule ${verb} fwmark ${fwmark} lookup ${table} priority 1101" ];

  startScript = pkgs.writeShellScript "transmission-egress-start" ''
    set -eu
    # Fail-safe: an unreachable default in table ${table} means that when the
    # tunnel is down (its 'default dev ${iface}' route gone) the lookup terminates
    # here instead of falling through to main → no ISP leak (belt-and-suspenders
    # with the kill switch below).
    ${ip} route replace unreachable default table ${table} metric 1000
    ${lib.concatStringsSep "\n" (map (l: "${l} || true") (mkRuleLines "add"))}
  '';

  stopScript = pkgs.writeShellScript "transmission-egress-stop" ''
    ${lib.concatStringsSep "\n" (map (l: "${l} || true") (mkRuleLines "del"))}
    ${ip} route del unreachable default table ${table} metric 1000 || true
  '';

  # NAT-PMP renewal loop. Runs as the transmission user so its packets carry the
  # same UID mark and are allowed out ${iface} by the kill switch; reaching the
  # gateway ${gw} requires the tunnel, so until it's up this just retries.
  natpmpScript = pkgs.writeShellScript "transmission-natpmp" ''
    set -u
    last=""
    while :; do
      # Refresh both protocol mappings (60s lifetime); Proton returns the same
      # public port for udp and tcp.
      ${pkgs.libnatpmp}/bin/natpmpc -a 1 0 udp 60 -g ${gw} >/dev/null 2>&1 || true
      out=$(${pkgs.libnatpmp}/bin/natpmpc -a 1 0 tcp 60 -g ${gw} 2>/dev/null) || true
      port=$(printf '%s\n' "$out" | ${pkgs.gnused}/bin/sed -n 's/.*Mapped public port \([0-9]\{1,\}\).*/\1/p' | head -1)
      if [ -n "$port" ] && [ "$port" != "$last" ]; then
        # RPC is loopback with no auth (Caddy is the auth gate); no credentials.
        if ${pkgs.transmission_4}/bin/transmission-remote ${rpc} --port "$port" >/dev/null 2>&1; then
          last="$port"
          echo "natpmp: peer port set to $port"
        fi
      fi
      sleep 45
    done
  '';
in
{
  # Make the host `-m owner --uid-owner` match reliable: the upstream module sets
  # PrivateUsers=true (a user namespace), under which host-side owner matching is
  # unreliable. Override from OUT here so modules/transmission-server stays
  # VPN-unaware. RootDirectory et al. still apply.
  systemd.services.transmission.serviceConfig.PrivateUsers = lib.mkForce false;

  # Never let the daemon start before the steering rules + kill switch exist
  # (a startup leak window), and tear it down if the policy rules vanish.
  systemd.services.transmission = {
    after = [ "wireguard-${iface}.service" "transmission-egress.service" "firewall.service" ];
    requires = [ "transmission-egress.service" ];
    bindsTo = [ "transmission-egress.service" ];
  };

  systemd.services.transmission-egress = {
    description = "Policy routing: confine transmission (uid ${toString uid}) to ${iface}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = startScript;
      ExecStop = stopScript;
    };
  };

  systemd.services.transmission-natpmp = {
    description = "ProtonVPN NAT-PMP port forwarding for transmission";
    after = [ "transmission.service" "transmission-egress.service" "wireguard-${iface}.service" ];
    requires = [ "transmission.service" ];
    bindsTo = [ "transmission-egress.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "transmission";
      ExecStart = natpmpScript;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # iptables lives in the firewall hooks (not the oneshot) because the firewall
  # service flushes and rebuilds its chains on reload, which would wipe rules an
  # external oneshot added. The `ip rule`/route above are instead preserved by
  # vpn-egress.nix's global ManageForeignRoutingPolicyRules=false / ManageForeignRoutes=false.
  networking.firewall.extraCommands = lib.mkAfter ''
    # Mark transmission's locally-originated traffic so the fwmark ip-rule steers
    # it into table ${table} (→ default dev ${iface}).
    iptables -t mangle -A OUTPUT -m owner --uid-owner ${toString uid} -j MARK --set-mark ${fwmark}

    # SNAT to ${iface}'s address so the source is the tunnel IP regardless of the
    # source picked by the pre-mark route lookup (mirrors vpn-egress's MASQUERADE).
    iptables -t nat -A POSTROUTING -o ${iface} -m owner --uid-owner ${toString uid} -j MASQUERADE
    # Clamp MSS — the tunnel is nested inside wg0 (MTU 1340), so PMTU would
    # otherwise black-hole.
    iptables -t mangle -A POSTROUTING -p tcp --syn -o ${iface} -m owner --uid-owner ${toString uid} -j TCPMSS --clamp-mss-to-pmtu

    # IPv4 kill switch: transmission traffic to the LAN/VPN and loopback is fine,
    # traffic correctly leaving via ${iface} is fine, everything else from this
    # UID is REJECTed (fail fast, don't hang) so it can never leak out the ISP.
    iptables -N ${ksChain} 2>/dev/null || iptables -F ${ksChain}
    ${lib.concatMapStringsSep "\n" (net: "iptables -A ${ksChain} -d ${net} -j RETURN") localNetworks}
    iptables -A ${ksChain} -o lo -j RETURN
    iptables -A ${ksChain} -o ${iface} -j RETURN
    iptables -A ${ksChain} -j REJECT --reject-with icmp-port-unreachable
    iptables -D OUTPUT -m owner --uid-owner ${toString uid} -j ${ksChain} 2>/dev/null || true
    iptables -I OUTPUT 1 -m owner --uid-owner ${toString uid} -j ${ksChain}

    # IPv6 kill switch: table ${table} carries no IPv6 route, so block all of the
    # daemon's IPv6 egress (it falls back to IPv4) — prevents an IPv6 leak.
    ip6tables -N ${ksChain6} 2>/dev/null || ip6tables -F ${ksChain6}
    ip6tables -A ${ksChain6} -o lo -j RETURN
    ip6tables -A ${ksChain6} -j REJECT --reject-with icmp6-port-unreachable
    ip6tables -D OUTPUT -m owner --uid-owner ${toString uid} -j ${ksChain6} 2>/dev/null || true
    ip6tables -I OUTPUT 1 -m owner --uid-owner ${toString uid} -j ${ksChain6}
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D OUTPUT -m owner --uid-owner ${toString uid} -j ${ksChain} 2>/dev/null || true
    iptables -F ${ksChain} 2>/dev/null || true
    iptables -X ${ksChain} 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m owner --uid-owner ${toString uid} -j MARK --set-mark ${fwmark} 2>/dev/null || true
    iptables -t nat -D POSTROUTING -o ${iface} -m owner --uid-owner ${toString uid} -j MASQUERADE 2>/dev/null || true
    iptables -t mangle -D POSTROUTING -p tcp --syn -o ${iface} -m owner --uid-owner ${toString uid} -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    ip6tables -D OUTPUT -m owner --uid-owner ${toString uid} -j ${ksChain6} 2>/dev/null || true
    ip6tables -F ${ksChain6} 2>/dev/null || true
    ip6tables -X ${ksChain6} 2>/dev/null || true
  '';
}
