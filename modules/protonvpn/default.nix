{
  config,
  lib,
  pkgs,
  ...
}:

# ProtonVPN egress, in independent tunnels that never share an exit IP:
#
#   * clientTunnels ("proton-<name>") — selective egress for WireGuard peers,
#     one tunnel per exit country. Each owns a prefix of the WireGuard server's
#     address space (`sourcePrefixes`), its own routing table, its own
#     kill-switch chain and its own watchdog, so a peer's exit is decided by
#     which prefix its address came from and tunnels fail independently.
#     Everything else on this box, the host itself included, keeps leaving via
#     the ISP — including peers outside every tunnel's prefix, which is the
#     right default for LAN services, for geo-sensitive sites, and for anything
#     that must survive Proton being down.
#   * p2pTunnel ("proton-p2p") — a P2P-flagged Proton server that lives INSIDE a
#     network namespace, used by the Transmission daemon and nothing else. It is
#     deliberately on a different server from every client tunnel: browsing and
#     BitTorrent sharing one exit address is the correlation this whole
#     arrangement exists to prevent.
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
# Layout: ./options.nix is the option schema; this file holds the client
# tunnels, policy routing, kill switch, NAT and resolver; ./p2p.nix the P2P
# namespace (tunnel, Transmission, NAT-PMP); ./watchdog.nix the watchdog
# builder both use.
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

  # A tunnel's (publicKey, endpoint) candidates always have the configured peer
  # first, then the primary's alternate addresses, then the fallback servers.
  # Kept here so the unit and the watchdog agree on the indices by construction.
  # This is the CONFIGURED order; the watchdog re-ranks it by each candidate's
  # failure history when it rotates (see `failover_order`).
  candidatesOf =
    t:
    map (e: {
      inherit (t.peer) publicKey;
      endpoint = e;
      label = if t.server != "" then t.server else e;
    }) ([ t.peer.endpoint ] ++ t.peer.extraEndpoints)
    ++ map (f: {
      inherit (f) publicKey endpoint;
      label = if f.server != null then f.server else f.endpoint;
    }) t.peer.fallbacks;

  # A tunnel's address without its mask.
  addrOf = t: lib.head (lib.splitString "/" (lib.head t.address));

  # The resolver's own user. Declared (not DynamicUser) so its uid is STABLE,
  # which is the whole basis of the steering below — see the resolver section.
  # The uid itself is never named here: NixOS allocates it and the scripts read
  # it back with `id -u`, so there is no number to collide or drift.
  resolverUser = "dnscrypt-proxy";

  # Client tunnels as an ORDERED list. `lib.attrNames` sorts, so the index a
  # tunnel gets — and therefore the priority block it owns — is a pure function
  # of the set of NAMES, not of attrset construction order. Inserting a name
  # that sorts earlier does shift the blocks after it, which is harmless: the
  # policy unit tears every rule in its range down and reinstalls it on each
  # start, so priorities are never expected to be stable across a rebuild, only
  # deterministic within one.
  #
  # Note for anyone adding a tunnel: `in` is a Nix keyword, so a country code
  # like that has to be written as a quoted attribute (`"in" = { … }`).
  clientTunnels = map (name: {
    inherit name;
    t = cfg.clientTunnels.${name};
  }) (lib.attrNames cfg.clientTunnels);

  activeTunnels = lib.filter (c: c.t.enable) clientTunnels;

  # Policy priorities this module owns.
  #
  # Each steered group owns a contiguous run of `prioStep` starting at
  # `prioBase`:
  #
  #   +0  bypass — local destinations, resolved in `main` BEFORE the tunnel
  #                lookup is ever reached
  #   +1  steer  — everything else from this group's sources
  #   +2  oif    — host traffic deliberately bound to this tunnel's DEVICE
  #
  # Only the bypass-below-steer ordering is load-bearing. Ordering BETWEEN
  # groups is irrelevant, because a group's rules match none but its own
  # sources — which is what makes adding a tunnel a local change.
  prioBase = 1100;
  prioStep = 10;
  prioOf = i: {
    bypass = prioBase + prioStep * i;
    steer = prioBase + prioStep * i + 1;
    oif = prioBase + prioStep * i + 2;
  };

  # The resolver's uid rule keeps its historical priority. It belongs to no
  # tunnel block, and it is referenced by number in verify-protonvpn.sh.
  resolverPrio = 1002;

  # The range swept before rules are (re)installed. It starts BELOW prioBase on
  # purpose: 1000/1001/1003 (single client tunnel) and 1010/1011 (LAN redirect)
  # are what earlier versions of this module installed, and on the first switch
  # onto this version those are the rules actually in the kernel.
  prioSweepLo = 1000;
  prioSweepHi = 1260; # exclusive

  indexedTunnels = lib.imap0 (i: c: c // { prio = prioOf i; }) activeTunnels;

  tunnelByName = name: lib.findFirst (c: c.name == name) null indexedTunnels;

  # Steered groups: each pairs source prefixes with the tunnel they leave
  # through and the priority block they occupy. The LAN redirect, when enabled,
  # is simply another group pointed at a named tunnel.
  steeredGroups =
    (map (c: {
      inherit (c) name prio;
      tunnel = c.t;
      sources = c.t.sourcePrefixes;
    }) indexedTunnels)
    ++ lib.optional (cfg.lanRedirect.enable && cfg.lanRedirect.viaTunnel != null) (
      let
        c = tunnelByName cfg.lanRedirect.viaTunnel;
      in
      {
        inherit (c) name;
        prio = prioOf (lib.length indexedTunnels);
        tunnel = c.t;
        sources = cfg.lanRedirect.sourcePrefixes;
      }
    );

  ruleLines = lib.concatLists (
    map (
      g:
      lib.concatLists (
        map (
          src:
          # Local destinations first: LAN-to-LAN and client-to-server traffic must
          # never be pushed through a tunnel. A prefix missing from localPrefixes
          # becomes a silently tunneled local flow, which is why the option's
          # description insists on enumerating all of them. With several tunnels it
          # also covers traffic BETWEEN two tunneled prefixes, which must stay local
          # rather than hairpin out through Proton and back.
          (map (
            net: "${ip} rule add from ${src} to ${net} lookup main priority ${toString g.prio.bypass}"
          ) cfg.localPrefixes)
          ++ [
            "${ip} rule add from ${src} lookup ${toString g.tunnel.table} priority ${toString g.prio.steer}"
          ]
        ) g.sources
      )
    ) steeredGroups
  );

  # Host traffic bound to a tunnel's DEVICE, matched by `oif` and not by source
  # address.
  #
  # It has to be `oif`, and the reason is Proton: every profile they issue
  # carries the same 10.2.0.2/32, so with more than one client tunnel in this
  # namespace `from 10.2.0.2` is ambiguous — first match wins, and every
  # tunnel's watchdog would probe whichever tunnel sorts first while reporting
  # on its own. A dead tunnel would look healthy for as long as ANY tunnel was
  # up, which is worse than having no watchdog at all. `oif` keys on the device
  # the socket is bound to, which is unique per tunnel.
  #
  # The duplicate addresses are otherwise harmless: the kernel accepts the same
  # /32 on several interfaces, and forwarded traffic is SNATted per outgoing
  # interface, so only locally-originated traffic ever needed disambiguating.
  oifRuleLines = map (
    c:
    "${ip} rule add oif ${c.t.interface} lookup ${toString c.t.table} priority ${toString c.prio.oif}"
  ) indexedTunnels;

  # Clear every rule whose priority falls in the block this module owns, read
  # back FROM THE KERNEL rather than re-derived from the configuration. A
  # config-derived list cannot remove the rules of a tunnel that has just been
  # deleted from the configuration, and a steering rule that outlives its
  # tunnel points into a table whose route is gone — exactly the silent-leak
  # shape this module exists to prevent. Deleting by priority removes one rule
  # per call, so duplicates at the same priority are each listed and each
  # deleted.
  clearPriorities = ''
    owned_prios=$(${ip} rule show | ${pkgs.gnused}/bin/sed -n 's/^\([0-9]\{1,\}\):.*/\1/p')
    for prio in $owned_prios; do
      if [ "$prio" -ge ${toString prioSweepLo} ] && [ "$prio" -lt ${toString prioSweepHi} ]; then
        ${ip} rule del priority "$prio" 2>/dev/null || true
      fi
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
    ${lib.concatMapStringsSep "\n    " (
      c: "${ip} route replace blackhole default table ${toString c.t.table} metric 1000"
    ) indexedTunnels}

    ${lib.concatStringsSep "\n    " ruleLines}

    # Let anything on this host that deliberately binds a tunnel's DEVICE route
    # through that tunnel's table. Without it a socket bound to the device has
    # no route at all, because `main` knows nothing about the tunnel by design.
    # This is what lets each watchdog probe THROUGH its own interface rather
    # than merely checking that it exists — a WireGuard interface stays up and
    # happy with a dead peer on the other side, so anything less than an
    # end-to-end probe tests nothing. See oifRuleLines for why these match by
    # device and not by source address.
    ${lib.concatStringsSep "\n    " oifRuleLines}

    # The resolver's upstream queries, steered BY UID.
    #
    # This is a uid rule and not a firewall mark, and the difference is the
    # whole reason the previous attempt could not work. A `-j MARK` in mangle
    # OUTPUT lands AFTER connect() has already run the route lookup, chosen the
    # WAN source address and bound the socket to it; the post-mangle reroute
    # then changes the route but never the source, so the query entered the
    # tunnel carrying an RFC1918 address that Proton drops — a silent timeout,
    # not an error. A uid rule is consulted BY that first lookup, so source
    # selection lands on the tunnel address from the start. No mark, no cgroup
    # match, no SNAT to paper over a wrong source, and nothing to re-resolve
    # when the unit restarts.
    #
    # The uid is read at runtime rather than baked in: NixOS allocates it (see
    # resolverUser), so there is no number here to collide with another service
    # or to drift if allocation changes.
    #
    # Non-fatal on purpose. Everything above this point — the blackhole and the
    # peer steering rules — is already installed, and those are the fail-closed
    # guarantees; letting a missing resolver uid abort the unit would take them
    # down to protect a privacy nicety. If the lookup fails, upstream DNS stays
    # on the ISP path and says so, which is the same degraded state a dead
    # tunnel produces.
    ${lib.optionalString (cfg.resolver.viaTunnel != null) ''
      if resolver_uid="$(${pkgs.coreutils}/bin/id -u ${resolverUser} 2>/dev/null)"; then
        ${ip} rule add uidrange "$resolver_uid-$resolver_uid" lookup ${toString cfg.resolver.table} priority ${toString resolverPrio}
      else
        echo "protonvpn: user ${resolverUser} does not exist — upstream DNS will leave via the ISP, not the tunnel" >&2
      fi
    ''}
  '';

  policyStop = pkgs.writeShellScript "protonvpn-policy-stop" ''
    ${clearPriorities}
    ${lib.concatMapStringsSep "\n    " (
      c: "${ip} route del blackhole default table ${toString c.t.table} metric 1000 || true"
    ) indexedTunnels}
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
  # ONE CHAIN PER TUNNEL, and that is not tidiness. The ACCEPT rule names a
  # specific interface, so a single shared chain would accept a packet from the
  # `es` prefix that was leaving down the `us` tunnel. That is not a leak to the
  # ISP, but it is a silent violation of the thing the user actually chose — the
  # exit country — and it would be invisible. A per-tunnel chain makes the
  # correct exit the only accepted one.
  ksChainOf = name: "protonvpn-ks-${name}";

  ksStart = ''
    ${lib.concatMapStringsSep "\n" (c: ''
      iptables -N ${ksChainOf c.name} 2>/dev/null || iptables -F ${ksChainOf c.name}
      ${lib.concatMapStringsSep "\n      " (
        net: "iptables -A ${ksChainOf c.name} -d ${net} -j RETURN"
      ) cfg.localPrefixes}
      iptables -A ${ksChainOf c.name} -o ${c.t.interface} -j ACCEPT
      iptables -A ${ksChainOf c.name} -j DROP'') indexedTunnels}
    ${lib.concatMapStringsSep "\n" (
      g:
      lib.concatMapStringsSep "\n" (src: ''
        iptables -D FORWARD -s ${src} -j ${ksChainOf g.name} 2>/dev/null || true
        iptables -I FORWARD 1 -s ${src} -j ${ksChainOf g.name}'') g.sources
    ) steeredGroups}

    # IPv6 guard. This host has no IPv6 egress — no global address, no v6
    # default route — so peers have no routable v6 through us. wg0 may carry a
    # ULA (my.vpn-server.ula6Prefix) so peers route their v6 INTO the tunnel
    # rather than around it; this rule is what refuses it there. Without it,
    # a v6 address on the WireGuard interface would silently give tunneled
    # clients dual-stack egress that bypasses Proton. "No routable IPv6" is a
    # supported answer; "IPv6 that quietly goes around Proton" is not.
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j DROP 2>/dev/null || true
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || true
    # REJECT, not DROP: peers route ::/0 into the tunnel (my.vpn-server
    # .ula6Prefix) so their IPv6 cannot go around it, and an immediate
    # "prohibited" makes them fall back to IPv4 at once instead of timing out.
    ip6tables -I FORWARD 1 -i ${cfg.wgInterface} -j REJECT --reject-with icmp6-adm-prohibited
  '';

  # Only the chains the CURRENT configuration knows about are removed here. A
  # chain left behind by a tunnel that has since been deleted is inert — its
  # jump rules go with the FORWARD entries above, and an unreferenced chain
  # matches nothing — so it costs a stale name in `iptables -L` and nothing
  # else.
  ksStop = ''
    ${lib.concatMapStringsSep "\n" (
      g:
      lib.concatMapStringsSep "\n" (
        src: "iptables -D FORWARD -s ${src} -j ${ksChainOf g.name} 2>/dev/null || true"
      ) g.sources
    ) steeredGroups}
    ${lib.concatMapStringsSep "\n" (c: ''
      iptables -F ${ksChainOf c.name} 2>/dev/null || true
      iptables -X ${ksChainOf c.name} 2>/dev/null || true'') indexedTunnels}
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j DROP 2>/dev/null || true
    ip6tables -D FORWARD -i ${cfg.wgInterface} -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || true
  '';

  # SNAT to the tunnel address, and clamp MSS on the way in. The clamp matters
  # more here than usual: the peer has already crossed one WireGuard hop, so the
  # path it is about to enter is narrower than anything its own PMTU discovery
  # can observe, and without the clamp large TCP transfers black-hole while small
  # requests succeed — which reads as "the VPN is up but the internet is broken".
  natStart = lib.concatMapStringsSep "\n" (
    g:
    lib.concatMapStringsSep "\n" (src: ''
      iptables -t nat -D POSTROUTING -s ${src} -o ${g.tunnel.interface} -j MASQUERADE 2>/dev/null || true
      iptables -t nat -A POSTROUTING -s ${src} -o ${g.tunnel.interface} -j MASQUERADE
      iptables -t mangle -D FORWARD -p tcp --syn -s ${src} -o ${g.tunnel.interface} -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
      iptables -t mangle -A FORWARD -p tcp --syn -s ${src} -o ${g.tunnel.interface} -j TCPMSS --clamp-mss-to-pmtu
    '') g.sources
  ) steeredGroups;

  natStop = lib.concatMapStringsSep "\n" (
    g:
    lib.concatMapStringsSep "\n" (src: ''
      iptables -t nat -D POSTROUTING -s ${src} -o ${g.tunnel.interface} -j MASQUERADE 2>/dev/null || true
      iptables -t mangle -D FORWARD -p tcp --syn -s ${src} -o ${g.tunnel.interface} -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    '') g.sources
  ) steeredGroups;

  # Escalating probe / endpoint rotation / reset timer (./watchdog.nix).
  mkWatchdog = import ./watchdog.nix {
    inherit
      lib
      pkgs
      cfg
      wg
      candidatesOf
      ;
  };

  # Named units, one pair per client tunnel.
  #
  # This is a list of (name, units) rather than a list of module fragments, and
  # that is not a style choice. Merging fragments with `mkMerge (map … )` makes
  # the SHAPE of this module's `config` depend on `cfg.clientTunnels`, and the
  # module system has to know the shape before it can evaluate any option — so
  # it forces the option while computing it, and the evaluation recurses
  # forever. Keeping the attribute paths below static (`systemd.timers`,
  # `systemd.services`) moves everything config-derived into VALUES, which are
  # lazy and resolve fine.
  clientWatchdogs = map (c: {
    name = "protonvpn-watchdog-${c.t.interface}";
    units = mkWatchdog {
      inherit (c) t;
      # There is no wireguard-<iface>.service to restart under networkd.
      # `networkctl reconfigure` re-applies the .network (addresses, routes)
      # but NOT the .netdev: an existing WireGuard device keeps its peers, so
      # the watchdog restores the primary peer itself before calling this. The
      # table route survives it — we own that route, and ManageForeignRoutes=
      # false keeps networkd's hands off it.
      resetCmd = "${pkgs.systemd}/bin/networkctl reconfigure ${c.t.interface}";
      resetName = "${c.t.interface} (networkctl reconfigure)";
      # Bound to the DEVICE, not to the address: every Proton profile carries
      # the same 10.2.0.2, so binding the address would send each tunnel's probe
      # down whichever tunnel sorts first and make a dead tunnel
      # indistinguishable from a healthy one. `if!` forces curl to read the
      # argument as an interface name rather than falling back to treating it as
      # a host.
      probePrefix = "";
      curlArgs = "--interface if!${c.t.interface}";
      wgPrefix = "";
    };
  }) activeTunnels;

  p2pWatchdog = mkWatchdog {
    t = cfg.p2pTunnel;
    # The P2P tunnel IS a real service — it is built by hand rather than through
    # networkd, because it has to be created inside a namespace.
    resetCmd = "${pkgs.systemd}/bin/systemctl restart protonvpn-${cfg.p2pTunnel.interface}.service";
    resetName = "protonvpn-${cfg.p2pTunnel.interface}.service";
    # Probed from inside the namespace, where the tunnel is the only route, so
    # no source binding is needed or wanted.
    probePrefix = "${ip} netns exec ${cfg.p2pTunnel.netns} ";
    curlArgs = "";
    wgPrefix = "${ip} netns exec ${cfg.p2pTunnel.netns} ";
  };

in
{
  # This module configures both of these (my.wireguard-client for the client
  # tunnels, my.transmission-server for the P2P netns wiring), so it declares
  # the dependency instead of relying on the host importing them alongside it.
  # Importing the same path twice is a no-op, so hosts that already list them
  # lose nothing.
  imports = [
    ../wireguard-client
    ../transmission-server
    ./options.nix
    ./p2p.nix
  ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [

      ##########################################################################
      # Assertions.
      #
      # Every one of these guards a misconfiguration whose SYMPTOM is traffic
      # quietly leaving by the wrong path — a wrong exit country, a local flow
      # hairpinned through Proton, a watchdog reporting on a tunnel it is not
      # probing. None of them announce themselves at runtime, so they are caught
      # here instead.
      ##########################################################################
      {
        assertions = [
          {
            assertion =
              let
                tables = map (c: c.t.table) activeTunnels;
              in
              lib.length (lib.unique tables) == lib.length tables;
            message = ''
              my.protonvpn.clientTunnels: two tunnels share a routing table.
              Their default routes would land in the same table and one exit
              would silently swallow the other's traffic. Give each tunnel its
              own `table`.
            '';
          }
          {
            assertion = !(lib.any (c: c.t.table == cfg.resolver.table) activeTunnels);
            message = ''
              my.protonvpn: a client tunnel uses resolver.table
              (${toString cfg.resolver.table}). The resolver's table must hold
              the tunnel route and NO blackhole, so that a dead tunnel degrades
              DNS to the ISP path instead of killing name resolution for the
              whole LAN. Sharing the table reintroduces exactly that outage.
            '';
          }
          {
            assertion = cfg.resolver.viaTunnel == null || tunnelByName cfg.resolver.viaTunnel != null;
            message = ''
              my.protonvpn.resolver.viaTunnel = "${toString cfg.resolver.viaTunnel}"
              names no enabled client tunnel.
            '';
          }
          {
            assertion =
              !cfg.lanRedirect.enable
              || (cfg.lanRedirect.viaTunnel != null && tunnelByName cfg.lanRedirect.viaTunnel != null);
            message = ''
              my.protonvpn.lanRedirect is enabled but viaTunnel does not name an
              enabled client tunnel. With several exits configured there is no
              sensible default to fall back on.
            '';
          }
          {
            assertion = lib.length activeTunnels <= (prioSweepHi - prioBase) / prioStep - 1;
            message = ''
              my.protonvpn.clientTunnels: too many tunnels for the priority
              range this module owns (${toString prioBase}..${toString prioSweepHi},
              one block of ${toString prioStep} each, one reserved for
              lanRedirect). Widen prioSweepHi.
            '';
          }
        ]
        ++ map (c: {
          assertion = lib.all (src: lib.elem src cfg.localPrefixes) c.t.sourcePrefixes;
          message = ''
            my.protonvpn.clientTunnels.${c.name}: every prefix in
            `sourcePrefixes` must also appear in `localPrefixes`. Without it,
            traffic from this tunnel's peers to another tunneled prefix has no
            bypass rule and hairpins out through Proton and back instead of
            staying on wg0.
          '';
        }) activeTunnels;
      }

      ##########################################################################
      # Client tunnels — ordinary interfaces in the root namespace, carrying no
      # routes of their own. Everything that steers traffic into them is policy
      # routing, added separately.
      ##########################################################################
      (lib.mkIf (activeTunnels != [ ]) {
        my.wireguard-client = {
          enable = true;
          interfaces = lib.listToAttrs (
            map (
              c:
              lib.nameValuePair c.t.interface {
                privateKeyFile = c.t.privateKeyFile;
                address = c.t.address;
                mtu = c.t.mtu;
                # No routes, no table: bringing this up must not change how a single
                # packet is routed until a policy rule says so. This is the
                # `table = "off"` of a wg-quick profile, expressed in the interface
                # module this repo actually uses.
                allowedIPsAsRoutes = false;
                table = null;
                peer = {
                  publicKey = c.t.peer.publicKey;
                  endpoint = c.t.peer.endpoint;
                  # IPv4 only, on purpose. This host has no IPv6 at all (no global
                  # address, no v6 default route) and neither does wg0, so a ::/0
                  # route here would be a black hole that dual-stack clients stall on
                  # during Happy Eyeballs before falling back. No routable IPv6
                  # anywhere beats silent dual-stack fallback.
                  allowedIPs = [ "0.0.0.0/0" ];
                  persistentKeepalive = c.t.peer.persistentKeepalive;
                };
              }
            ) activeTunnels
          );
        };
      })

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
        networking.wireguard.interfaces.${cfg.wgInterface}.ips = map (c: c.t.gateway) activeTunnels;

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

      (lib.mkIf (activeTunnels != [ ]) {
        # The tunnels' routes are owned by NETWORKD, not by a oneshot unit.
        #
        # A oneshot was tried twice and is wrong both times. Anchored to
        # multi-user.target it required a wireguard-<iface>.service that does not
        # exist under networkd, so it never ran at all and the tunnel's table held
        # nothing but its blackhole. Re-anchored to the interface's .device unit it
        # started correctly at boot, but a .device unit tracks the device's
        # EXISTENCE in sysfs, not whether it is UP — so `ip link set <iface> down`
        # flushed these routes while the unit stayed `active` with RemainAfterExit,
        # BindsTo never fired, and `systemctl start` was a no-op. The tunnel came
        # back and its routes did not.
        #
        # networkd already owns this interface and re-applies its configuration
        # whenever the link is reconfigured or regains carrier, which is exactly
        # the event the oneshot had no way to observe. Declaring the routes here
        # makes recovery automatic and deletes the unit and its failure modes.
        #
        # Neither route can touch `main`: both pin an explicit Table=. This is
        # still consistent with allowedIPsAsRoutes = false — that keeps WireGuard
        # from installing ITS notion of routes (0.0.0.0/0 into main); these are
        # policy-table routes that only a policy rule can ever reach.
        systemd.network.networks = lib.listToAttrs (
          map (
            c:
            lib.nameValuePair "40-${c.t.interface}" {
              routes = [
                # Scope=link because a WireGuard device has no gateway to speak of;
                # this reproduces `ip route add default dev <iface> scope link`.
                {
                  Destination = "0.0.0.0/0";
                  Table = c.t.table;
                  Scope = "link";
                }
              ]
              ++ lib.optional (cfg.resolver.viaTunnel == c.name) {
                # The resolver's table. Deliberately holds ONLY this route and no
                # blackhole, which is what makes upstream DNS DEGRADE instead of
                # dying: when the link goes, the kernel drops this route with it, the
                # table is empty, rule 1002 matches nothing and the lookup falls
                # through to `main` — queries leave over the ISP, still encrypted to
                # the same no-log resolvers. That is this module's stated intent for
                # DNS, and it is why the resolver does not share table
                # ${toString c.t.table}, whose blackhole exists to keep
                # PEER traffic fail-closed and once took the whole LAN's name
                # resolution down with it.
                #
                # PreferredSource pins the source address rather than leaving it to
                # selection, so the uid rule's whole purpose — a correct source at
                # connect() time — cannot be quietly undone by a second address
                # appearing on the interface.
                Destination = "0.0.0.0/0";
                Table = cfg.resolver.table;
                Scope = "link";
                PreferredSource = addrOf c.t;
              };
            }
          ) activeTunnels
        );
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
      (lib.mkIf (activeTunnels != [ ]) {
        networking.firewall.extraCommands = lib.mkAfter ''
          ${ksStart}
          ${natStart}
        '';
        networking.firewall.extraStopCommands = ''
          ${ksStop}
          ${natStop}
        '';
      })

      # Belt and braces for the Transmission veth (./p2p.nix): even if something
      # inside the namespace acquired a default route via the host end, the host
      # will not forward a packet off this link. Combined with the absent route
      # and the absent SNAT rule, that is three independent reasons the namespace
      # cannot reach the internet except through Proton.
      #
      # Kept HERE rather than in ./p2p.nix on purpose: `-I FORWARD 1` makes the
      # insert order the rule order, and definitions from an imported module
      # merge ahead of this file's own, which would put the drop below the
      # kill-switch rules instead of above them.
      (lib.mkIf (cfg.p2pTunnel.enable && cfg.transmission.enable) (
        let
          v = cfg.transmission.veth;
        in
        {
          networking.firewall.extraCommands = lib.mkAfter ''
            iptables -D FORWARD -i ${v.hostInterface} -j DROP 2>/dev/null || true
            iptables -I FORWARD 1 -i ${v.hostInterface} -j DROP
          '';
          networking.firewall.extraStopCommands = ''
            iptables -D FORWARD -i ${v.hostInterface} -j DROP 2>/dev/null || true
          '';
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

      (lib.mkIf (cfg.resolver.viaTunnel != null) {
        # A STABLE uid is the entire mechanism here, so the resolver cannot keep
        # nixpkgs' DynamicUser. An `ip rule` can match uidrange but has no notion
        # of a cgroup, and cgroup matching was the previous approach precisely
        # because a dynamic uid cannot be named — but it had to be done in mangle
        # OUTPUT, which is too late to influence source selection (see the rule in
        # protonvpn-policy). Trading DynamicUser for a declared user is what buys
        # a correct source address, and it is the smaller loss: every other
        # sandboxing directive nixpkgs sets on this unit is untouched, and the
        # uid is still unprivileged and owns nothing but its own state.
        #
        # No uid is written down. NixOS allocates one for a declared system user
        # and records it in /var/lib/nixos, so it is stable across rebuilds and
        # reboots without this module picking a number that could collide with
        # another service on the host.
        users.users.${resolverUser} = {
          isSystemUser = true;
          group = resolverUser;
          description = "dnscrypt-proxy, with a stable uid so its upstream queries can be steered into the ProtonVPN tunnel";
        };
        users.groups.${resolverUser} = { };

        # systemd migrates StateDirectory/CacheDirectory between
        # /var/lib/private/<name> and /var/lib/<name> when DynamicUser flips, so
        # the existing resolver state and cache move across on the first start
        # rather than being abandoned.
        systemd.services.dnscrypt-proxy.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = resolverUser;
          Group = resolverUser;
        };

        # No ordering is added against user creation. systemd.sysusers is off on
        # this host, so users.users is realised by the activation script into
        # /etc/passwd before any unit is started, and at boot the file is simply
        # already correct — there is no unit to order against. protonvpn-policy
        # looks the uid up defensively regardless.

        # Nothing to add to the firewall. The old mark-66 MASQUERADE existed only
        # to rewrite a source address that was wrong by construction; with the
        # uid rule the socket is bound to the tunnel's own address from the start
        # and
        # there is nothing left to translate.
      })

      ##########################################################################
      # Watchdog and endpoint rotation.
      ##########################################################################
      (lib.mkIf cfg.watchdog.enable {
        systemd.timers = lib.listToAttrs (map (x: lib.nameValuePair x.name x.units.timer) clientWatchdogs);
        systemd.services = lib.listToAttrs (
          map (x: lib.nameValuePair x.name x.units.service) clientWatchdogs
        );
      })

      (lib.mkIf (cfg.watchdog.enable && cfg.p2pTunnel.enable) {
        systemd.timers."protonvpn-watchdog-${cfg.p2pTunnel.interface}" = p2pWatchdog.timer;
        systemd.services."protonvpn-watchdog-${cfg.p2pTunnel.interface}" = p2pWatchdog.service;
      })
    ]
  );
}
