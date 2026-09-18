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
  # Installed and removed by dnscrypt-proxy.service itself; see the comment at
  # the use site for why it cannot live in the firewall hooks.
  dnsCgroup = "system.slice/dnscrypt-proxy.service";

  dnsMarkInstall = pkgs.writeShellScript "protonvpn-dns-mark-install" ''
    set -u
    ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m cgroup --path ${dnsCgroup} -j MARK --set-mark ${toString dnsMark} 2>/dev/null || true
    if ! ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT -m cgroup --path ${dnsCgroup} -j MARK --set-mark ${toString dnsMark}; then
      echo "protonvpn: FAILED to install the DNS mark rule — upstream DNS will leave via the ISP, not the tunnel" >&2
      exit 1
    fi
  '';

  dnsMarkRemove = pkgs.writeShellScript "protonvpn-dns-mark-remove" ''
    ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m cgroup --path ${dnsCgroup} -j MARK --set-mark ${toString dnsMark} 2>/dev/null || true
  '';

  # The client tunnel's address without its mask.
  clientTunnelAddr = lib.head (lib.splitString "/" (lib.head cfg.clientTunnel.address));

  # Firewall mark for the resolver's upstream queries. Priority 1002 carries
  # the matching rule and is cleared with the rest in protonvpn-policy.
  dnsMark = 66;

  ownedPriorities = [ 1000 1001 1010 1011 1002 1003 ];

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

    # Let anything on this host that deliberately binds the tunnel's own source
    # address route through the tunnel's table. Without it a socket bound to
    # that address has no route at all, because `main` knows nothing about the
    # tunnel by design. This is what lets the watchdog probe THROUGH the
    # interface rather than merely checking that it exists — a WireGuard
    # interface stays up and happy with a dead peer on the other side, so
    # anything less than an end-to-end probe tests nothing.
    ${lib.optionalString cfg.clientTunnel.enable
      "${ip} rule add from ${clientTunnelAddr} lookup ${toString cfg.clientTunnel.table} priority 1003"}
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

  # One watchdog timer per tunnel. The probe, the rotation and the restart are
  # deliberately three escalating steps rather than one: most failures are a
  # single unresponsive Proton endpoint, and reaching for a unit restart first
  # would take Transmission down with it (it is PartOf the P2P tunnel) for
  # something a live `wg set` fixes without dropping a single transfer.
  mkWatchdog = { t, unit, probePrefix, curlArgs, wgPrefix }:
    let
      eps = endpointsOf t;
      stateFile = "/run/protonvpn-${t.interface}.endpoint";
      failFile = "/run/protonvpn-${t.interface}.fails";
    in
    {
      systemd.timers."protonvpn-watchdog-${t.interface}" = {
        description = "Probe ${t.interface} and rotate its endpoint on failure";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Deliberately OnActiveSec, not OnBootSec. A monotonic timer whose
          # deadline is already in the past when it starts fires immediately,
          # and on a `nixos-rebuild switch`/`test` into a host that booted days
          # ago an OnBootSec deadline always is — so the first probe landed in
          # the same second the tunnel came up, long before any handshake could
          # complete, and the watchdog restarted it on the spot. OnActiveSec is
          # relative to the timer's own activation, so the grace window is real
          # both at boot and at switch.
          OnActiveSec = cfg.watchdog.interval * 2;
          OnUnitActiveSec = cfg.watchdog.interval;
          AccuracySec = "5s";
        };
      };

      systemd.services."protonvpn-watchdog-${t.interface}" = {
        description = "ProtonVPN watchdog for ${t.interface}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "protonvpn-watchdog-${t.interface}" ''
            set -u

            endpoints=(${lib.concatMapStringsSep " " (e: "'${e}'") eps})
            n=''${#endpoints[@]}

            probe() {
              ${probePrefix}${pkgs.curl}/bin/curl -fsS -o /dev/null \
                ${curlArgs} --max-time ${toString cfg.watchdog.timeout} \
                ${cfg.watchdog.probeUrl}
            }

            # Consecutive failures, carried across invocations: this unit is a
            # oneshot, so the count cannot live in memory.
            fails=0
            [ -r ${failFile} ] && fails=$(${pkgs.coreutils}/bin/cat ${failFile} 2>/dev/null || echo 0)

            if probe; then
              ${pkgs.coreutils}/bin/rm -f ${failFile}
              exit 0
            fi

            fails=$((fails + 1))
            echo "$fails" > ${failFile}
            echo "watchdog: ${t.interface} failed its probe ($fails/${toString cfg.watchdog.failuresBeforeRestart})"

            # Rotation is NOT gated on the failure count. `wg set` swaps the
            # endpoint on a live interface, so a rotation that works costs
            # nothing — no interface teardown, no dropped sockets, no restart
            # cascade — and there is no reason to sit on a dead endpoint while a
            # counter fills.
            if [ "$n" -gt 1 ]; then
              idx=0
              [ -r ${stateFile} ] && idx=$(${pkgs.coreutils}/bin/cat ${stateFile} 2>/dev/null || echo 0)

              # Try each remaining endpoint once.
              for _ in $(${pkgs.coreutils}/bin/seq 1 "$((n - 1))"); do
                idx=$(( (idx + 1) % n ))
                next=''${endpoints[$idx]}
                echo "watchdog: rotating ${t.interface} to $next"
                ${wgPrefix}${pkgs.wireguard-tools}/bin/wg set ${t.interface} \
                  peer ${t.peer.publicKey} endpoint "$next" || continue
                echo "$idx" > ${stateFile}

                # Give the new endpoint a handshake window before judging it.
                ${pkgs.coreutils}/bin/sleep 5
                if probe; then
                  echo "watchdog: ${t.interface} recovered on $next"
                  ${pkgs.coreutils}/bin/rm -f ${failFile}
                  exit 0
                fi
              done

              echo "watchdog: no endpoint answered for ${t.interface}"
            fi

            # The restart is the only destructive step here: it resets a
            # handshake that may simply not have completed yet, and for the P2P
            # tunnel it takes Transmission down with it. So it, alone, waits for
            # the failure count.
            if [ "$fails" -lt ${toString cfg.watchdog.failuresBeforeRestart} ]; then
              echo "watchdog: deferring restart of ${unit}"
              exit 0
            fi

            echo "watchdog: restarting ${unit} after $fails consecutive failures"
            ${pkgs.coreutils}/bin/rm -f ${failFile}
            exec ${pkgs.systemd}/bin/systemctl restart ${unit}
          '';
        };
      };
    };

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

    watchdog = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Probe each tunnel end-to-end and rotate its endpoint when it stops
          answering.

          This exists because a WireGuard interface gives no useful health
          signal on its own: it stays up, configured and entirely happy with a
          dead peer on the other side, forwarding into a void. Only traffic that
          completes a round trip proves anything, so the probe goes THROUGH the
          interface rather than looking at it.

          Rotation has to be explicit for the same structural reason. WireGuard
          does not fail over between peers inside one interface — it has no
          concept of a peer being down — so nothing moves us off a dead endpoint
          unless something replaces it.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Seconds between probes.";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = ''
          Per-probe timeout in seconds. Kept well under `interval` so a hung
          probe cannot overlap the next one.
        '';
      };

      failuresBeforeRestart = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = ''
          Consecutive failed probes required before the watchdog restarts the
          tunnel's unit.

          Endpoint rotation is deliberately not gated on this — `wg set` is free
          and drops nothing, so it happens on the first failure. Only the restart
          waits, because only the restart is destructive: it resets a handshake
          that may simply not have completed yet, and a single failure is enough
          to guillotine a tunnel that was seconds away from coming up. At the
          default interval this gives a new tunnel two minutes to settle.
        '';
      };

      probeUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://1.1.1.1/";
        description = ''
          URL fetched through the tunnel to prove it carries traffic. Any small,
          reliable HTTPS endpoint works; what matters is that a full request
          completes, since that exercises connectivity, routing, NAT and MTU in
          one go.

          It MUST address its host by IP, never by name. With
          `resolver.routeUpstreamThroughClient` enabled the resolver's own
          upstream queries leave through this tunnel, so a hostname here is
          circular: the probe cannot resolve until the tunnel carries traffic,
          the watchdog reads that as the tunnel being down, and it restarts the
          tunnel every interval while DNS stays dead host-wide. `1.1.1.1` is
          used rather than a Proton endpoint because it is anycast, stable, and
          serves a certificate valid for the literal address.
        '';
      };
    };

    resolver = {
      routeUpstreamThroughClient = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Send the local resolver's UPSTREAM queries out the client tunnel, so
          public lookups carry a Proton source address rather than this line's.

          Split-horizon and the internal zones are unaffected and keep working
          from the local resolver either way — this only moves where a query that
          has to leave the house goes out.

          Marking is done by cgroup rather than by uid because the upstream
          dnscrypt-proxy unit runs under DynamicUser, so its uid is not stable
          and cannot be named at evaluation time. The kernel re-runs the route
          lookup after the OUTPUT mangle hook when the mark changes, which is
          what makes a locally-generated packet honour the rule; if that ever
          stops holding, the symptom is upstream DNS leaving via the ISP rather
          than failing, so verify-protonvpn.sh asserts it explicitly.

          Set to false to leave upstream DNS on the ISP path. Queries are already
          encrypted to no-log resolvers there, so what this buys is hiding the
          source address from those resolvers — worth having, not worth an
          outage, which is why the fallback below exists.
        '';
      };

      fallbackServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tls://dns.quad9.net" ];
        description = ''
          Resolvers the local resolver falls back to when its upstream cannot be
          reached — which, with routeUpstreamThroughClient on, is exactly what a
          dead tunnel looks like.

          This is the path that keeps ACME renewals, `nixos-rebuild` and every
          other name lookup on this box working while Proton is down. It
          deliberately does NOT use the ISP's resolver: fallback means degraded,
          not leaking. DoT to a third party keeps queries encrypted and keeps the
          ISP seeing nothing but a TLS session even in the degraded state.
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

          Note that this makes the inherited `table` option INERT for this
          tunnel: there is no policy routing here to need a table, because the
          namespace has exactly one route and no alternative to choose between.
        '';
      };
    };

    transmission = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Move the Transmission daemon into the P2P namespace and point its RPC
          endpoint at the veth below. This is the one place the daemon and the
          tunnel are wired together; modules/transmission-server stays unaware of
          both, as its header promises.
        '';
      };

      # A /30 carrying exactly two addresses and no default route. It exists so
      # Caddy can reach the web UI, and for nothing else: without a route to the
      # internet on it, and with the host refusing to forward anything off it
      # (see the FORWARD drop below), it cannot become a way around the tunnel.
      veth = {
        hostInterface = lib.mkOption {
          type = lib.types.str;
          default = "vt-host";
          description = "Host-side veth peer name.";
        };
        namespaceInterface = lib.mkOption {
          type = lib.types.str;
          default = "vt-ns";
          description = "Namespace-side veth peer name.";
        };
        hostAddress = lib.mkOption {
          type = lib.types.str;
          default = "10.200.0.1";
          description = "Host end of the RPC link. This is what Caddy connects from.";
        };
        namespaceAddress = lib.mkOption {
          type = lib.types.str;
          default = "10.200.0.2";
          description = "Namespace end of the RPC link. This is what the daemon binds its RPC to.";
        };
        prefixLength = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Prefix length of the RPC link. A /30 holds exactly these two addresses.";
        };
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

        # Belt and braces for the veth: even if something inside the namespace
        # acquired a default route via the host end, the host will not forward a
        # packet off this link. Combined with the absent route and the absent
        # SNAT rule, that is three independent reasons the namespace cannot reach
        # the internet except through Proton.
        networking.firewall.extraCommands = lib.mkAfter ''
          iptables -D FORWARD -i ${v.hostInterface} -j DROP 2>/dev/null || true
          iptables -I FORWARD 1 -i ${v.hostInterface} -j DROP
        '';
        networking.firewall.extraStopCommands = ''
          iptables -D FORWARD -i ${v.hostInterface} -j DROP 2>/dev/null || true
        '';

        my.transmission-server = {
          # The daemon binds its RPC to the namespace end; Caddy connects from
          # the host end, which is what the whitelist has to name.
          rpcAddress = v.namespaceAddress;
          # Both ends of the link. Caddy reaches the daemon from the host end;
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

    ##########################################################################
    # Resolver.
    #
    # The split-horizon answers and internal zones already live in
    # my.dns-filtering (AdGuard rewrites pointing acpuchades.com and friends at
    # the LAN address), and they are deliberately untouched here: they are what
    # stops LAN and WireGuard clients hairpinning out through Proton and back to
    # this host's WAN address to reach a service sitting three metres away.
    #
    # What this adds is where a query that genuinely has to leave goes out, plus
    # the fallback that keeps the box resolving when it cannot.
    ##########################################################################
    {
      # Fallback first, so the failure mode is covered before the thing that can
      # fail is introduced. Ordering matters here in review, not just at runtime.
      services.adguardhome.settings.dns.fallback_dns = cfg.resolver.fallbackServers;
    }

    (lib.mkIf (cfg.clientTunnel.enable && cfg.resolver.routeUpstreamThroughClient) {
      systemd.services.protonvpn-policy.serviceConfig.ExecStartPost =
        pkgs.writeShellScript "protonvpn-dns-rule-start" ''
          set -eu
          while ${ip} rule del priority 1002 2>/dev/null; do :; done
          ${ip} rule add fwmark ${toString dnsMark} lookup ${toString cfg.clientTunnel.table} priority 1002
        '';

      # The marking rule is installed by the RESOLVER's own unit, not by the
      # firewall hooks, and that is not a stylistic choice — `-m cgroup --path`
      # resolves the path to a live cgroup when the rule is INSERTED, so it has
      # two failure modes the firewall hooks cannot avoid:
      #
      #   * inserted while dnscrypt-proxy is stopped, it fails outright (the
      #     cgroup does not exist), which would fail firewall.service at boot,
      #     where the firewall reliably starts first;
      #   * the cgroup is destroyed and recreated on every service RESTART, so a
      #     rule inserted once silently stops matching afterwards — and a marking
      #     rule that stops matching means upstream DNS quietly reverts to the
      #     ISP path, with nothing failing to announce it.
      #
      # Binding it to the unit whose cgroup it names fixes both: it can only be
      # inserted when the cgroup exists, and it is reinserted every time that
      # cgroup is recreated. `+` runs it as root — the service itself is
      # DynamicUser and could not call iptables. The mangle OUTPUT chain is not
      # touched by firewall reloads (the NixOS firewall only manages its own
      # nixos-fw-rpfilter chain in mangle), so the rule survives them.
      systemd.services.dnscrypt-proxy.serviceConfig = {
        # "+-": root (the unit is DynamicUser), and a FAILURE HERE DOES NOT KILL
        # THE RESOLVER. That direction is chosen deliberately. If the rule cannot
        # be installed, the cost is upstream DNS taking the ISP path — degraded
        # privacy — whereas failing the unit costs name resolution for the entire
        # LAN and every VPN peer, and would do it at boot, before anyone could
        # intervene. The script still logs the failure loudly, and
        # verify-protonvpn.sh asserts both the rule and its effect, so this is a
        # verified control rather than a silent one.
        ExecStartPost = [ "+-${dnsMarkInstall}" ];
        ExecStopPost = [ "+${dnsMarkRemove}" ];
      };

      networking.firewall.extraCommands = lib.mkAfter ''
        iptables -t nat -D POSTROUTING -o ${cfg.clientTunnel.interface} -m mark --mark ${toString dnsMark} -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o ${cfg.clientTunnel.interface} -m mark --mark ${toString dnsMark} -j MASQUERADE
      '';

      networking.firewall.extraStopCommands = ''
        iptables -t nat -D POSTROUTING -o ${cfg.clientTunnel.interface} -m mark --mark ${toString dnsMark} -j MASQUERADE 2>/dev/null || true
      '';
    })

    ##########################################################################
    # Watchdog and endpoint rotation.
    ##########################################################################
    (lib.mkIf (cfg.watchdog.enable && cfg.clientTunnel.enable) (
      mkWatchdog {
        t = cfg.clientTunnel;
        unit = "wireguard-${cfg.clientTunnel.interface}.service";
        # Probed from the tunnel's own source address, which priority 1003 routes
        # into the tunnel's table.
        probePrefix = "";
        curlArgs = "--interface ${clientTunnelAddr}";
        wgPrefix = "";
      }
    ))

    (lib.mkIf (cfg.watchdog.enable && cfg.p2pTunnel.enable) (
      mkWatchdog {
        t = cfg.p2pTunnel;
        unit = "protonvpn-${cfg.p2pTunnel.interface}.service";
        # Probed from inside the namespace, where the tunnel is the only route,
        # so no source binding is needed or wanted.
        probePrefix = "${ip} netns exec ${cfg.p2pTunnel.netns} ";
        curlArgs = "";
        wgPrefix = "${ip} netns exec ${cfg.p2pTunnel.netns} ";
      }
    ))
  ]);
}
