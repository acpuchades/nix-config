{ config, lib, pkgs, ... }:

# ProtonVPN egress, in two independent tunnels that never share an exit IP:
#
#   * clientTunnel ("proton-client") — selective egress for WireGuard peers
#     allocated out of `tunneledPeerPrefix`. Everything else on this box, the
#     host itself included, keeps leaving via the ISP.
#   * p2pTunnel ("proton-p2p") — a P2P-flagged Proton server that lives INSIDE a
#     network namespace, used by the Transmission daemon and nothing else.
#
# Two properties this module is built around, both load-bearing:
#
#   1. THE MAIN ROUTING TABLE IS NEVER TOUCHED. This host terminates inbound
#      services (WireGuard, Caddy for acpuchades.com, Nextcloud, Immich,
#      Vaultwarden, Umami). Moving the default route into a tunnel would make
#      every one of those reply down a path its request did not arrive on, and
#      they would all break at once. Steering is done with source-based policy
#      routing into dedicated tables instead, and WireGuard is told to install no
#      routes at all (`allowedIPsAsRoutes = false`) so merely bringing a tunnel
#      up can never hijack anything.
#
#   2. EVERY PATH FAILS CLOSED. A dead tunnel means no traffic, never a silent
#      fallback to the ISP. Three independent mechanisms, because this is the one
#      thing that must not be wrong: a `blackhole default` in each policy table so
#      the lookup terminates instead of falling through to main; a terminal-DROP
#      firewall chain that contains no tunneled-source-to-WAN rule at all; and,
#      for Transmission, a network namespace in which the tunnel is the only route
#      that exists — if it dies the daemon has no network path whatsoever, which
#      is strictly stronger than any firewall can be.
#
# HISTORY worth knowing before editing. An earlier version of this lived in
# machines/homeserver/{vpn-egress,transmission-egress}.nix and was disabled in
# June 2026 because forwarded client traffic got no replies from Proton while
# host-sourced egress on the same address worked. The cause was almost certainly
# that BOTH Proton interfaces were pinned to `mtu = 1340`. The two encapsulations
# here are SEQUENTIAL, not nested on the wire — the server decapsulates wg0
# before it encapsulates into a Proton tunnel — so a 1420-byte inner packet from
# a client met a 1340 tunnel and needed fragmenting, while host-sourced traffic
# auto-sized itself to 1340 and was unaffected. That is exactly the
# forwarded-vs-local asymmetry that went unexplained at the time. Hence: the
# PROTON interfaces sit at 1420, and it is the CLIENT profiles of tunneled peers
# that carry the reduced MTU (see `tunneledPeerMtu`).

let
  cfg = config.my.protonvpn;

  ip = "${pkgs.iproute2}/bin/ip";
  wg = "${pkgs.wireguard-tools}/bin/wg";

  # A tunnel's peer endpoint list always has the configured endpoint first; the
  # watchdog rotates through the rest. Kept here so the unit and the watchdog
  # agree on the ordering by construction.
  endpointsOf = t: [ t.peer.endpoint ] ++ t.peer.extraEndpoints;

  # Priorities this module owns. Cleared wholesale before the rules are
  # (re)installed, which is what makes the unit idempotent — `ip rule add` is
  # not, and re-running it otherwise stacks duplicates until the table is
  # unreadable.
  ownedPriorities = [ 1000 1001 1010 1011 ];

  # Groups of steered sources, each with the priority pair it uses: the bypass
  # rule sits one below the steering rule so local destinations are resolved in
  # `main` BEFORE the tunnel lookup is ever reached.
  steeredGroups =
    [ { bypassPrio = 1000; steerPrio = 1001; sources = [ cfg.tunneledPeerPrefix ]; } ]
    ++ lib.optional cfg.lanRedirect.enable
      { bypassPrio = 1010; steerPrio = 1011; sources = cfg.lanRedirect.sourcePrefixes; };

  ruleLines = lib.concatLists (map (g:
    lib.concatLists (map (src:
      # Local destinations first: LAN-to-LAN and client-to-server traffic must
      # never be pushed through a tunnel. A prefix missing from localPrefixes
      # becomes a silently tunneled local flow, which is why the option's
      # description insists on enumerating all of them.
      (map (net:
        "${ip} rule add from ${src} to ${net} lookup main priority ${toString g.bypassPrio}")
        cfg.localPrefixes)
      ++ lib.optional cfg.clientTunnel.enable
        "${ip} rule add from ${src} lookup ${toString cfg.clientTunnel.table} priority ${toString g.steerPrio}"
    ) g.sources)
  ) steeredGroups);

  clearPriorities = ''
    for prio in ${lib.concatMapStringsSep " " toString ownedPriorities}; do
      while ${ip} rule del priority "$prio" 2>/dev/null; do :; done
    done
  '';

  policyStart = pkgs.writeShellScript "protonvpn-policy-start" ''
    set -eu
    ${clearPriorities}

    # The blackhole goes in FIRST and outlives every tunnel. At metric 1000 it
    # loses to the tunnel's own default route while that exists, and becomes the
    # only match the moment the kernel drops that route with the device. A lookup
    # that reaches it terminates there instead of falling through to `main` and
    # leaving via the ISP.
    #
    # The P2P tunnel has no equivalent here and needs none: it lives in a network
    # namespace whose only route is the tunnel, so there is nothing to fall
    # through to in the first place.
    ${lib.optionalString cfg.clientTunnel.enable
      "${ip} route replace blackhole default table ${toString cfg.clientTunnel.table} metric 1000"}

    ${lib.concatStringsSep "\n    " ruleLines}
  '';

  policyStop = pkgs.writeShellScript "protonvpn-policy-stop" ''
    ${clearPriorities}
    ${lib.optionalString cfg.clientTunnel.enable
      "${ip} route del blackhole default table ${toString cfg.clientTunnel.table} metric 1000 || true"}
  '';

  # The kill-switch chain. Read the ORDER, because the guarantee is structural:
  # local destinations RETURN to normal processing, traffic correctly leaving via
  # the tunnel is ACCEPTed, and everything else from a steered source is DROPped.
  #
  # There is deliberately NO rule matching a steered source to the WAN interface.
  # Not a rule that drops it — no rule at all. The chain simply cannot express
  # "tunneled client goes out the ISP", so no future edit to the surrounding
  # ruleset, and no tunnel failure, can produce that packet. That is the whole
  # design: the fallback path does not exist rather than being forbidden.
  ksChain = "protonvpn-ks";

  steeredSources = lib.concatMap (g: g.sources) steeredGroups;

  ksStart = ''
    iptables -N ${ksChain} 2>/dev/null || iptables -F ${ksChain}
    ${lib.concatMapStringsSep "\n" (net:
      "iptables -A ${ksChain} -d ${net} -j RETURN") cfg.localPrefixes}
    iptables -A ${ksChain} -o ${cfg.clientTunnel.interface} -j ACCEPT
    iptables -A ${ksChain} -j DROP
    ${lib.concatMapStringsSep "\n" (src: ''
      iptables -D FORWARD -s ${src} -j ${ksChain} 2>/dev/null || true
      iptables -I FORWARD 1 -s ${src} -j ${ksChain}'') steeredSources}

    # IPv6 guard. This host has no IPv6 at all — no global address, no v6
    # default route — and peer profiles are generated IPv4-only, so tunneled
    # clients have no routable v6 through us and there is nothing here to leak
    # today. This rule is what keeps that true if a v6 address is ever added to
    # the WireGuard interface without revisiting this module: tunneled clients
    # would otherwise silently acquire dual-stack egress that bypasses the
    # tunnel entirely. "No routable IPv6" is a supported answer; "IPv6 that
    # quietly goes around Proton" is not.
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j DROP 2>/dev/null || true
    ip6tables -I FORWARD 1 -i ${cfg.wgInterface} -j DROP
  '';

  ksStop = ''
    ${lib.concatMapStringsSep "\n" (src:
      "iptables -D FORWARD -s ${src} -j ${ksChain} 2>/dev/null || true") steeredSources}
    iptables -F ${ksChain} 2>/dev/null || true
    iptables -X ${ksChain} 2>/dev/null || true
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j DROP 2>/dev/null || true
  '';

  # SNAT to the tunnel address, and clamp MSS on the way in. The clamp matters
  # more here than usual: the peer has already crossed one WireGuard hop, so the
  # path it is about to enter is narrower than anything its own PMTU discovery
  # can observe, and without the clamp large TCP transfers black-hole while small
  # requests succeed — which reads as "the VPN is up but the internet is broken".
  natStart = lib.concatMapStringsSep "\n" (src: ''
    iptables -t nat -D POSTROUTING -s ${src} -o ${cfg.clientTunnel.interface} -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s ${src} -o ${cfg.clientTunnel.interface} -j MASQUERADE
    iptables -t mangle -D FORWARD -p tcp --syn -s ${src} -o ${cfg.clientTunnel.interface} -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    iptables -t mangle -A FORWARD -p tcp --syn -s ${src} -o ${cfg.clientTunnel.interface} -j TCPMSS --clamp-mss-to-pmtu
  '') steeredSources;

  natStop = lib.concatMapStringsSep "\n" (src: ''
    iptables -t nat -D POSTROUTING -s ${src} -o ${cfg.clientTunnel.interface} -j MASQUERADE 2>/dev/null || true
    iptables -t mangle -D FORWARD -p tcp --syn -s ${src} -o ${cfg.clientTunnel.interface} -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
  '') steeredSources;

  tunnelOptions = { name, defaultTable }: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to bring up this Proton tunnel.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = "Kernel name of the WireGuard interface for this tunnel.";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the file holding this profile's WireGuard private key (the
        `PrivateKey` from Proton's .conf). A sops-nix secret path, so the key
        never lands in the Nix store.
      '';
    };

    address = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "10.2.0.2/32" ];
      description = ''
        Tunnel-local address(es), i.e. the profile's `Address`. Proton hands
        every config the same 10.2.0.2/32, which is harmless here: the client
        tunnel's route lives in its own table and the P2P tunnel lives in its own
        network namespace, so the duplicate never reaches the main table.
      '';
    };

    mtu = lib.mkOption {
      type = lib.types.int;
      default = 1420;
      description = ''
        Interface MTU. Leave at WireGuard's default 1420 — see the MTU note in
        this module's header before lowering it. Traffic that has already crossed
        another WireGuard hop is made to fit by lowering the MTU on THAT hop's
        clients (`tunneledPeerMtu`), not by shrinking this tunnel.
      '';
    };

    table = lib.mkOption {
      type = lib.types.int;
      default = defaultTable;
      description = ''
        Dedicated routing table this tunnel's default route and blackhole
        fallback are installed into. Never `main`.
      '';
    };

    dns = lib.mkOption {
      type = lib.types.str;
      default = "10.2.0.1";
      description = ''
        Proton's in-tunnel resolver (the profile's `DNS`, which is also the
        tunnel gateway). Used as the NAT-PMP gateway and as the resolver inside
        the P2P namespace. It is deliberately NOT made the host's resolver.
      '';
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Human-readable note recording WHICH Proton server this profile is for
        (e.g. "ES#124, P2P-flagged, NAT-PMP enabled"). Documentation only —
        nothing reads it — but a tunnel whose server nobody can identify is one
        nobody can re-generate.
      '';
    };

    peer = {
      publicKey = lib.mkOption {
        type = lib.types.str;
        description = "Proton server's WireGuard public key.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "Primary Proton endpoint as host:port.";
        example = "130.195.250.66:51820";
      };

      extraEndpoints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional endpoints the watchdog rotates to when the primary stops
          answering. WireGuard does NOT fail over between peers within one
          interface, so rotation has to be done explicitly — these are alternate
          endpoints for the SAME peer public key (i.e. the same Proton server
          reached by another address), or servers sharing that key.
        '';
      };

      persistentKeepalive = lib.mkOption {
        type = lib.types.int;
        default = 25;
        description = "Seconds between keepalives, to hold the NAT mapping open.";
      };
    };
  };
in
{
  options.my.protonvpn = {
    enable = lib.mkEnableOption "ProtonVPN egress (selective client tunnel + isolated P2P tunnel)";

    wgInterface = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
      description = ''
        The inbound WireGuard server interface whose peers are being steered
        (my.vpn-server.interface). This module adds `tunneledGateway` to it as a
        second address; it does not otherwise touch it, and existing peers are
        left exactly as they are.
      '';
    };

    tunneledPeerPrefix = lib.mkOption {
      type = lib.types.str;
      default = "10.0.1.0/24";
      description = ''
        Sub-range of the WireGuard server's address space whose peers egress via
        the client tunnel. Selection is by PREFIX rather than by a per-peer list,
        so adding a tunneled peer is an allocation out of this range and needs no
        change here. Peers outside it (the existing 10.0.0.0/24) keep direct,
        untunneled access to the LAN services.
      '';
    };

    tunneledGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.0.1.1/24";
      description = ''
        Address added to `wgInterface` so it is on-link for `tunneledPeerPrefix`.
        Added ALONGSIDE the existing server address, not in place of it.
      '';
    };

    tunneledPeerMtu = lib.mkOption {
      type = lib.types.int;
      default = 1340;
      description = ''
        MTU that tunneled peers must set in their own client profiles. Purely
        documentation on this side — the value has to be typed into the client —
        but it is consumed by the verification script and is the number to quote
        when handing out a tunneled profile.

        Why 1340: the peer's inner packet is at most this, WireGuard adds 60
        bytes to reach the server (1400 on the wire), the server decapsulates and
        re-encapsulates into the 1420-byte Proton tunnel, which fits with room to
        spare — including on a 1492-byte PPPoE path.
      '';
    };

    localPrefixes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Every locally-reachable prefix — LAN, WireGuard subnets, container
        bridges. Traffic from a tunneled source to any of these is looked up in
        `main` at a HIGHER priority than the steering rule, so LAN-to-LAN and
        client-to-server traffic is never pushed through a tunnel. Enumerate all
        of them; one missing prefix becomes a silently tunneled local flow.
      '';
      example = [ "192.168.2.0/24" "10.0.0.0/24" "10.0.1.0/24" ];
    };

    uplinkInterface = lib.mkOption {
      type = lib.types.str;
      description = "WAN interface. Referenced only to keep it out of the tunneled path.";
      example = "wlp3s0";
    };

    lanRedirect = {
      enable = lib.mkEnableOption ''
        steering entire LAN hosts through the client tunnel.

        DELIBERATELY OFF. This box is not the LAN's default gateway, and making
        it one is a different project with a different blast radius. The option
        exists so the capability is visible and reviewable in one place rather
        than rediscovered later
      '';

      sourcePrefixes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          LAN source addresses/prefixes to steer when `lanRedirect.enable` is on.
          These must be hosts that actually route through this machine.
        '';
      };
    };

    clientTunnel = tunnelOptions { name = "proton-client"; defaultTable = 42; };

    p2pTunnel = tunnelOptions { name = "proton-p2p"; defaultTable = 43; } // {
      netns = lib.mkOption {
        type = lib.types.str;
        default = "torrent";
        description = ''
          Name of the network namespace the P2P tunnel and its consumer live in.
          The tunnel is the only route inside it, so a dead tunnel leaves the
          daemon with no network path at all.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [

    ##########################################################################
    # Client tunnel — an ordinary interface in the root namespace, carrying no
    # routes of its own. Everything that steers traffic into it is policy
    # routing, added separately.
    ##########################################################################
    (lib.mkIf cfg.clientTunnel.enable {
      my.wireguard-client = {
        enable = true;
        interfaces.${cfg.clientTunnel.interface} = {
          privateKeyFile = cfg.clientTunnel.privateKeyFile;
          address = cfg.clientTunnel.address;
          mtu = cfg.clientTunnel.mtu;
          # No routes, no table: bringing this up must not change how a single
          # packet is routed until a policy rule says so. This is the
          # `table = "off"` of a wg-quick profile, expressed in the interface
          # module this repo actually uses.
          allowedIPsAsRoutes = false;
          table = null;
          peer = {
            publicKey = cfg.clientTunnel.peer.publicKey;
            endpoint = cfg.clientTunnel.peer.endpoint;
            # IPv4 only, on purpose. This host has no IPv6 at all (no global
            # address, no v6 default route) and neither does wg0, so a ::/0
            # route here would be a black hole that dual-stack clients stall on
            # during Happy Eyeballs before falling back. No routable IPv6
            # anywhere beats silent dual-stack fallback.
            allowedIPs = [ "0.0.0.0/0" ];
            persistentKeepalive = cfg.clientTunnel.peer.persistentKeepalive;
          };
        };
      };
    })

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
            '';
            ExecStop = pkgs.writeShellScript "netns-${ns}-stop" ''
              ${ip} netns del ${ns} || true
            '';
          };
        };

        systemd.services."protonvpn-${t.interface}" = {
          description = "ProtonVPN P2P tunnel ${t.interface} inside namespace ${ns}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" "netns-${ns}.service" ];
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
              ${lib.concatMapStringsSep "\n" (a:
                "${ip} -n ${ns} address add ${a} dev ${t.interface}") t.address}
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
    # Policy routing.
    #
    # Split deliberately across TWO units, and the split is the fail-closed
    # guarantee rather than tidiness:
    #
    #   protonvpn-policy        permanent. Installs the `ip rule`s and the
    #                           blackhole default in each table. Never bound to a
    #                           tunnel, because if it were, stopping the tunnel
    #                           would also remove the rules — and traffic would
    #                           then fall through to `main` and leave via the
    #                           ISP, which is the exact leak this exists to stop.
    #
    #   protonvpn-route-<ifc>   bound to its tunnel. Installs only the tunnel's
    #                           default route, at the kernel's default metric so
    #                           it wins over the blackhole at metric 1000. When
    #                           the tunnel goes away the kernel drops this route
    #                           with the device, the blackhole is what remains,
    #                           and the lookup terminates there.
    ##########################################################################
    {
      # Loose reverse-path filtering. Strict rp_filter drops replies arriving on
      # a Proton interface, because the route back to their internet source is
      # the main-table default via the WAN — the asymmetry is the entire point of
      # policy routing, so strict mode and this design are incompatible.
      #
      # `all` is a max() against each interface's own value, so setting it to 2
      # makes every interface loose regardless of what `default` seeded them with.
      boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" = 2;
      networking.firewall.checkReversePath = lib.mkDefault "loose";

      # systemd-networkd deletes routing policy rules and routes it does not
      # manage ("foreign") whenever it restarts. Everything below is added
      # imperatively by the units in this module, so without these two settings
      # networkd wipes the rules on every rebuild — steered traffic then falls
      # through to the ISP route, which the firewall chain drops, and the symptom
      # is tunneled clients losing the internet on an unrelated `nixos-rebuild`.
      systemd.network.config.networkConfig = {
        ManageForeignRoutingPolicyRules = false;
        ManageForeignRoutes = false;
      };

      # Put the tunneled range on-link on the WireGuard server interface, as a
      # SECOND address beside the existing one (`ips` is a list option, so this
      # concatenates). Existing peers keep their addresses, their keys and their
      # ordering untouched; a tunneled peer is simply allocated out of the new
      # prefix and picked up by the prefix rule below with no further change.
      networking.wireguard.interfaces.${cfg.wgInterface}.ips = [ cfg.tunneledGateway ];

      systemd.services.protonvpn-policy = {
        description = "ProtonVPN policy routing rules and fail-closed blackholes";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = policyStart;
          ExecStop = policyStop;
        };
      };
    }

    (lib.mkIf cfg.clientTunnel.enable {
      systemd.services."protonvpn-route-${cfg.clientTunnel.interface}" = {
        description = "Default route for ${cfg.clientTunnel.interface} in table ${toString cfg.clientTunnel.table}";
        wantedBy = [ "multi-user.target" ];
        after = [ "wireguard-${cfg.clientTunnel.interface}.service" "protonvpn-policy.service" ];
        requires = [ "wireguard-${cfg.clientTunnel.interface}.service" ];
        # PartOf, so a tunnel restart re-installs the route the kernel dropped
        # along with the device.
        partOf = [ "wireguard-${cfg.clientTunnel.interface}.service" ];
        bindsTo = [ "wireguard-${cfg.clientTunnel.interface}.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "protonvpn-route-${cfg.clientTunnel.interface}-start" ''
            set -eu
            ${ip} route replace default dev ${cfg.clientTunnel.interface} table ${toString cfg.clientTunnel.table}
          '';
          ExecStop = pkgs.writeShellScript "protonvpn-route-${cfg.clientTunnel.interface}-stop" ''
            ${ip} route del default dev ${cfg.clientTunnel.interface} table ${toString cfg.clientTunnel.table} || true
          '';
        };
      };
    })

    ##########################################################################
    # Fail-closed forwarding, NAT and MSS clamping for the client tunnel.
    #
    # These live in the firewall hooks rather than in a oneshot because the
    # firewall service flushes and rebuilds its chains on every reload, which
    # would silently wipe rules an external unit had added. The `ip rule`s and
    # routes above are the opposite case — they are preserved by
    # ManageForeignRoutingPolicyRules = false — which is why the two halves of
    # this module are installed by different mechanisms.
    ##########################################################################
    (lib.mkIf cfg.clientTunnel.enable {
      networking.firewall.extraCommands = lib.mkAfter ''
        ${ksStart}
        ${natStart}
      '';
      networking.firewall.extraStopCommands = ''
        ${ksStop}
        ${natStop}
      '';
    })
  ]);
}
