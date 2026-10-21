# The P2P side of my.protonvpn: the WireGuard tunnel moved into its own
# network namespace, Transmission running inside it, and NAT-PMP port
# renewal. The client tunnels and policy routing are in ./default.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.protonvpn;
  ip = "${pkgs.iproute2}/bin/ip";
  wg = "${pkgs.wireguard-tools}/bin/wg";
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      ##########################################################################
      # P2P tunnel — created in the ROOT namespace and then moved into `netns`.
      #
      # The move order matters and is the whole trick: a WireGuard device keeps its
      # UDP socket in the namespace it was CREATED in, so after the move the
      # encrypted underlay still leaves via the host's ordinary WAN route, while
      # the cleartext side is only reachable from inside the namespace. That is why
      # the namespace needs no route to Proton, no veth to the internet, and no
      # second default route — the only thing in it is the tunnel.
      #
      # Written as a bespoke unit rather than through my.wireguard-client because
      # that module (correctly) knows nothing about namespaces, and the interface
      # has to be configured before it is moved.
      ##########################################################################
      (lib.mkIf cfg.p2pTunnel.enable (
        let
          t = cfg.p2pTunnel;
          ns = t.netns;
        in
        {
          systemd.services."netns-${ns}" = {
            description = "Network namespace ${ns} (isolated ProtonVPN P2P egress)";
            wantedBy = [ "multi-user.target" ];
            before = [ "protonvpn-${t.interface}.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "netns-${ns}-start" ''
                set -eu
                ${ip} netns list | ${pkgs.gnugrep}/bin/grep -qx '${ns}' || ${ip} netns add ${ns}
                ${ip} -n ${ns} link set lo up

                # No IPv6 in here at all. The tunnel is IPv4-only and this host has
                # no IPv6 anywhere, so a v6 address inside the namespace could only
                # ever be a link-local that some future change turns into a leak.
                # Disabling it outright makes "no routable IPv6" a property of the
                # namespace rather than an accident of the current configuration.
                ${ip} netns exec ${ns} ${pkgs.procps}/bin/sysctl -q -w net.ipv6.conf.all.disable_ipv6=1
                ${ip} netns exec ${ns} ${pkgs.procps}/bin/sysctl -q -w net.ipv6.conf.default.disable_ipv6=1
              '';
              ExecStop = pkgs.writeShellScript "netns-${ns}-stop" ''
                ${ip} netns del ${ns} || true
              '';
            };
          };

          systemd.services."protonvpn-${t.interface}" = {
            description = "ProtonVPN P2P tunnel ${t.interface} inside namespace ${ns}";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "netns-${ns}.service"
            ];
            wants = [ "network-online.target" ];
            requires = [ "netns-${ns}.service" ];
            bindsTo = [ "netns-${ns}.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "protonvpn-${t.interface}-start" ''
                set -eu

                # Clear any leftover from an unclean stop, in either namespace.
                ${ip} link del ${t.interface} 2>/dev/null || true
                ${ip} -n ${ns} link del ${t.interface} 2>/dev/null || true

                # Create and configure in the ROOT namespace, so the UDP socket
                # binds here and uses the host's WAN route.
                ${ip} link add ${t.interface} type wireguard
                ${wg} set ${t.interface} \
                  private-key ${t.privateKeyFile} \
                  peer ${t.peer.publicKey} \
                    endpoint ${t.peer.endpoint} \
                    allowed-ips 0.0.0.0/0 \
                    persistent-keepalive ${toString t.peer.persistentKeepalive}
                ${ip} link set ${t.interface} mtu ${toString t.mtu}

                # Move the cleartext side into the namespace and give it the only
                # route that will exist in there.
                ${ip} link set ${t.interface} netns ${ns}
                ${lib.concatMapStringsSep "\n" (a: "${ip} -n ${ns} address add ${a} dev ${t.interface}") t.address}
                ${ip} -n ${ns} link set ${t.interface} up
                ${ip} -n ${ns} route add default dev ${t.interface}
              '';
              ExecStop = pkgs.writeShellScript "protonvpn-${t.interface}-stop" ''
                ${ip} -n ${ns} link del ${t.interface} 2>/dev/null || true
                ${ip} link del ${t.interface} 2>/dev/null || true
              '';
            };
          };
        }
      ))

      ##########################################################################
      # Transmission inside the P2P namespace.
      #
      # This is the strongest isolation available here and the reason a namespace
      # was chosen over policy routing: the daemon does not have a rule that sends
      # its traffic down a tunnel, it has NO OTHER ROUTE IN EXISTENCE. A firewall
      # kill switch drops packets the daemon can still form; this removes the path
      # itself. If the tunnel dies the daemon cannot address the internet at all.
      ##########################################################################
      (lib.mkIf (cfg.p2pTunnel.enable && cfg.transmission.enable) (
        let
          t = cfg.p2pTunnel;
          ns = t.netns;
          v = cfg.transmission.veth;
          nsPath = "/var/run/netns/${ns}";
          # The tunnel address without its mask — what the daemon binds its peer
          # sockets to. Never 0.0.0.0: an unbound daemon would happily use the veth
          # if one ever gained a route.
          tunnelAddr = lib.head (lib.splitString "/" (lib.head t.address));
        in
        {
          # Proton's in-tunnel resolver, for the namespace only. Placed at the path
          # `ip netns exec` looks for, so anything entered into this namespace by
          # hand or by the NAT-PMP unit picks it up automatically, and bind-mounted
          # into the daemon (which systemd's NetworkNamespacePath does NOT do — the
          # /etc/netns convention belongs to iproute2, not systemd). Without this
          # the daemon would inherit the host's `nameserver 127.0.0.1`, which
          # inside the namespace is a loopback with nothing listening on it.
          environment.etc."netns/${ns}/resolv.conf".text = ''
            nameserver ${t.dns}
            options edns0
          '';

          systemd.services."protonvpn-veth-${ns}" = {
            description = "RPC veth link into namespace ${ns}";
            wantedBy = [ "multi-user.target" ];
            after = [ "netns-${ns}.service" ];
            requires = [ "netns-${ns}.service" ];
            bindsTo = [ "netns-${ns}.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "protonvpn-veth-${ns}-start" ''
                set -eu
                ${ip} link del ${v.hostInterface} 2>/dev/null || true

                ${ip} link add ${v.hostInterface} type veth peer name ${v.namespaceInterface}
                ${ip} link set ${v.namespaceInterface} netns ${ns}

                ${ip} address add ${v.hostAddress}/${toString v.prefixLength} dev ${v.hostInterface}
                ${ip} link set ${v.hostInterface} up

                ${ip} -n ${ns} address add ${v.namespaceAddress}/${toString v.prefixLength} dev ${v.namespaceInterface}
                ${ip} -n ${ns} link set ${v.namespaceInterface} up

                # NOTE the absence of a default route via this link, on both ends.
                # The only route it creates is the kernel's on-link /${toString v.prefixLength}, which reaches
                # exactly one address. Adding a default here would quietly undo the
                # entire isolation.
              '';
              ExecStop = pkgs.writeShellScript "protonvpn-veth-${ns}-stop" ''
                ${ip} link del ${v.hostInterface} 2>/dev/null || true
              '';
            };
          };

          # The veth's FORWARD drop is in ./default.nix, after the kill switch.

          my.transmission-server = {
            # The daemon binds its RPC to the namespace end; nginx connects from
            # the host end, which is what the whitelist has to name.
            rpcAddress = v.namespaceAddress;
            # Both ends of the link. nginx reaches the daemon from the host end;
            # the NAT-PMP renewal unit runs INSIDE the namespace and therefore
            # reaches it from the namespace end, where source selection picks the
            # local address. Omitting the second address makes every port update
            # fail with a 403 that nothing surfaces.
            rpcWhitelist = "${v.hostAddress},${v.namespaceAddress}";
          };

          services.transmission.settings = {
            # Peer traffic is pinned to the tunnel address explicitly rather than
            # left on 0.0.0.0. In this namespace that is belt and braces — the
            # tunnel is the only route — but it means a misconfiguration shows up
            # as a daemon that will not bind rather than as one quietly using
            # another interface.
            bind-address-ipv4 = tunnelAddr;
            bind-address-ipv6 = "::1";

            # Transmission's own port mapping stays OFF. The forwarded port comes
            # from Proton's NAT-PMP, renewed by protonvpn-natpmp, and two things
            # negotiating the same mapping would fight over it.
            port-forwarding-enabled = false;

            # LPD is already off in modules/transmission-server; it is restated
            # here because it is an ISOLATION property, not a preference. LPD
            # announces to the local link, which in this namespace means the tunnel
            # — broadcasting our presence to whatever else Proton has on it.
            lpd-enabled = false;

            # DHT and PEX stay ON, deliberately and unchanged. Both are fine behind
            # a VPN — they reveal the Proton exit address, not ours — and turning
            # them off measurably hurts peer discovery on smaller swarms. Flagged
            # rather than silently flipped: if the threat model is "no participation
            # in any distributed tracker at all", these are the two to reconsider,
            # and that is a decision to take on purpose.
            dht-enabled = true;
            pex-enabled = true;
          };

          systemd.services.transmission = {
            after = [
              "netns-${ns}.service"
              "protonvpn-${t.interface}.service"
              "protonvpn-veth-${ns}.service"
            ];
            requires = [
              "netns-${ns}.service"
              "protonvpn-veth-${ns}.service"
            ];
            # BindsTo the tunnel: if it stops, the daemon stops with it. PartOf so
            # that a tunnel RESTART (the watchdog rotating an endpoint) takes the
            # daemon with it — the interface is recreated, so the sockets bound to
            # its address have to be as well.
            bindsTo = [ "protonvpn-${t.interface}.service" ];
            partOf = [ "protonvpn-${t.interface}.service" ];
            serviceConfig = {
              NetworkNamespacePath = nsPath;
              # Upstream binds /etc read-only into RootDirectory; this lands on top
              # of it. Both are lists, so this concatenates rather than replaces.
              BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
            };
          };
        }
      ))

      ##########################################################################
      # NAT-PMP port renewal.
      #
      # Proton's forwarded port is randomly assigned and the lease is ~60 seconds,
      # so this is not a setup step that runs once — it is a permanent loop, and if
      # it stops the port goes away within a minute. It renews on a 45s cadence,
      # notices when the assigned port CHANGES, and pushes the new value into the
      # running daemon over RPC. The daemon is never restarted for a port change:
      # that would interrupt every transfer, repeatedly, for a routine event.
      ##########################################################################
      (lib.mkIf (cfg.p2pTunnel.enable && cfg.transmission.enable) (
        let
          t = cfg.p2pTunnel;
          ns = t.netns;
          v = cfg.transmission.veth;
          rpc = "${v.namespaceAddress}:${toString config.my.transmission-server.rpcPort}";
        in
        {
          systemd.services.protonvpn-natpmp = {
            description = "ProtonVPN NAT-PMP forwarded-port renewal for transmission";
            wantedBy = [ "multi-user.target" ];
            after = [
              "protonvpn-${t.interface}.service"
              "protonvpn-veth-${ns}.service"
              "transmission.service"
            ];
            requires = [ "protonvpn-veth-${ns}.service" ];
            bindsTo = [ "protonvpn-${t.interface}.service" ];
            partOf = [ "protonvpn-${t.interface}.service" ];
            serviceConfig = {
              Type = "simple";
              User = "transmission";
              Group = config.my.transmission-server.group;
              # Same namespace as the daemon: the gateway it has to talk to exists
              # nowhere else.
              NetworkNamespacePath = "/var/run/netns/${ns}";
              Restart = "always";
              RestartSec = 10;
              ExecStart = pkgs.writeShellScript "protonvpn-natpmp" ''
                set -u
                last=""
                while :; do
                  # Both protocols are renewed every cycle. Proton returns the same
                  # public port for each, but the two leases expire independently,
                  # so renewing only one silently loses half the mapping.
                  ${pkgs.libnatpmp}/bin/natpmpc -a 1 0 udp 60 -g ${t.dns} >/dev/null 2>&1 || true
                  out=$(${pkgs.libnatpmp}/bin/natpmpc -a 1 0 tcp 60 -g ${t.dns} 2>/dev/null) || true
                  port=$(printf '%s\n' "$out" \
                    | ${pkgs.gnused}/bin/sed -n 's/.*Mapped public port \([0-9]\{1,\}\).*/\1/p' \
                    | ${pkgs.coreutils}/bin/head -1)

                  if [ -z "$port" ]; then
                    # No reply. Either the tunnel is down or this Proton server is
                    # not servicing NAT-PMP — the request leaves either way, so
                    # silence is all we get to distinguish them by. Keep retrying;
                    # the loop is the whole mechanism.
                    :
                  elif [ "$port" != "$last" ]; then
                    if ${pkgs.transmission_4}/bin/transmission-remote ${rpc} --port "$port" >/dev/null 2>&1; then
                      echo "natpmp: forwarded port changed ''${last:-none} -> $port, pushed to transmission"
                      last="$port"
                    else
                      echo "natpmp: got forwarded port $port but the RPC update failed; will retry"
                    fi
                  fi

                  ${pkgs.coreutils}/bin/sleep 45
                done
              '';
            };
          };
        }
      ))
    ]
  );
}
