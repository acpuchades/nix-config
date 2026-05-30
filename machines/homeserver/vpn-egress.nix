{ config, lib, pkgs, ... }:

# Host-specific policy routing: steer the wg0 VPN clients' internet egress out
# the ProtonVPN tunnel (wgproton), with a kill switch so it never leaks to the
# ISP if the tunnel drops. This is coupled to the homeserver's topology — the
# wg0 client subnet, the LAN, and the wgproton tunnel — so it lives here rather
# than in the reusable modules/ tree.

let
  iface = "wgproton";                                  # ProtonVPN client tunnel
  from = [ "10.0.0.0/24" ];                            # wg0 client subnet to steer
  localNetworks = [ "192.168.2.0/24" "10.0.0.0/24" ];  # LAN + VPN subnet stay on the normal route
  killSwitch = true;
  clampMss = true;

  # Single source of truth: the routing table is whatever the wgproton
  # interface installs its default route into (set in default.nix).
  table =
    let t = config.my.wireguard-client.interfaces.${iface}.table;
    in if t == null
       then throw "vpn-egress: my.wireguard-client.interfaces.${iface}.table must be set (with allowedIPsAsRoutes = true)"
       else t;

  ip = "${pkgs.iproute2}/bin/ip";
  ksChain = "vpn-egress-ks";

  # `ip rule` lines, parameterised by verb ("add"/"del"). For each steered
  # source: keep traffic to local networks (LAN, intra-VPN, the server itself)
  # on the main table; send everything else to the tunnel's table.
  mkRuleLines = verb: lib.concatLists (map (src:
    (map (net: "${ip} rule ${verb} from ${src} to ${net} lookup main priority 1000") localNetworks)
    ++ [ "${ip} rule ${verb} from ${src} lookup ${table} priority 1001" ]
  ) from);

  startScript = pkgs.writeShellScript "vpn-egress-${iface}-start" ''
    set -eu
    # Fail-safe: an unreachable default in the tunnel's table means that when
    # the tunnel is down (its 'default dev ${iface}' route gone) the lookup
    # terminates here instead of falling through to main → no ISP leak.
    ${ip} route replace unreachable default table ${table} metric 1000
    ${lib.concatStringsSep "\n" (map (l: "${l} || true") (mkRuleLines "add"))}
  '';

  stopScript = pkgs.writeShellScript "vpn-egress-${iface}-stop" ''
    ${lib.concatStringsSep "\n" (map (l: "${l} || true") (mkRuleLines "del"))}
    ${ip} route del unreachable default table ${table} metric 1000 || true
  '';

  natLines = lib.concatMapStringsSep "\n"
    (src: "iptables -t nat -A POSTROUTING -s ${src} -o ${iface} -j MASQUERADE")
    from;

  mssLines = lib.optionalString clampMss (lib.concatMapStringsSep "\n"
    (src: "iptables -t mangle -A FORWARD -p tcp --syn -s ${src} -o ${iface} -j TCPMSS --clamp-mss-to-pmtu")
    from);

  # Kill-switch chain: client traffic to local networks RETURNs to normal
  # processing; traffic correctly leaving via the tunnel is ACCEPTed (terminal
  # — nothing else in FORWARD accepts wg0→${iface}); everything else from a
  # steered source is DROPped so it can never leak out the ISP uplink. The jump
  # is INSERTED at the top of FORWARD, ahead of the NAT module's
  # 'wg0 -> wlp3s0 ACCEPT'.
  ksStart = lib.optionalString killSwitch ''
    iptables -N ${ksChain} 2>/dev/null || iptables -F ${ksChain}
    ${lib.concatMapStringsSep "\n" (net: "iptables -A ${ksChain} -d ${net} -j RETURN") localNetworks}
    iptables -A ${ksChain} -o ${iface} -j ACCEPT
    iptables -A ${ksChain} -j DROP
    ${lib.concatMapStringsSep "\n" (src: ''
      iptables -D FORWARD -s ${src} -j ${ksChain} 2>/dev/null || true
      iptables -I FORWARD 1 -s ${src} -j ${ksChain}'') from}
  '';

  ksStop = lib.optionalString killSwitch ''
    ${lib.concatMapStringsSep "\n" (src: "iptables -D FORWARD -s ${src} -j ${ksChain} 2>/dev/null || true") from}
    iptables -F ${ksChain} 2>/dev/null || true
    iptables -X ${ksChain} 2>/dev/null || true
  '';

  natStop = lib.concatMapStringsSep "\n"
    (src: "iptables -t nat -D POSTROUTING -s ${src} -o ${iface} -j MASQUERADE || true")
    from;

  mssStop = lib.optionalString clampMss (lib.concatMapStringsSep "\n"
    (src: "iptables -t mangle -D FORWARD -p tcp --syn -s ${src} -o ${iface} -j TCPMSS --clamp-mss-to-pmtu || true")
    from);
in
{
  # Required for the asymmetric return path: replies arrive on ${iface} but the
  # route back to their internet source is the main-table default via the ISP
  # uplink, which strict reverse-path filtering would drop. Note: this also
  # relaxes spoof protection on the public interface — accepted here.
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  systemd.services."vpn-egress-${iface}" = {
    description = "Policy routing: steer ${lib.concatStringsSep "," from} out ${iface}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = startScript;
      ExecStop = stopScript;
    };
  };

  networking.firewall.extraCommands = lib.mkAfter ''
    ${natLines}
    ${mssLines}
    ${ksStart}
  '';

  networking.firewall.extraStopCommands = ''
    ${ksStop}
    ${natStop}
    ${mssStop}
  '';
}
