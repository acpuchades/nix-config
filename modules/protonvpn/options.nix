# Option schema of my.protonvpn. Implementation in ./default.nix (policy
# routing, kill switch, watchdogs, resolver) and ./p2p.nix (the P2P namespace).
{ config, lib, ... }:

let
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
        (e.g. "ES#124, P2P-flagged, NAT-PMP enabled"). Names the server in
        watchdog alerts, and otherwise documentation — but a tunnel whose server
        nobody can identify is one nobody can re-generate.
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
          reached by another address), or servers sharing that key. For a
          different server, use `fallbacks`.
        '';
      };

      fallbacks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              publicKey = lib.mkOption {
                type = lib.types.str;
                description = "Fallback Proton server's WireGuard public key.";
              };
              endpoint = lib.mkOption {
                type = lib.types.str;
                description = "Fallback Proton endpoint as host:port.";
              };
              server = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "ES#161";
                description = "Human-readable server name, used in alerts.";
              };
            };
          }
        );
        default = [ ];
        description = ''
          Other Proton SERVERS the watchdog fails over to. With no failure
          history they are tried in order after the primary's extraEndpoints;
          once candidates have failed, the watchdog tries never-failed ones
          first and the one that failed longest ago next (history persists in
          /var/lib/protonvpn-watchdog), so a dead server sinks to the back
          without anyone editing this list. The swap replaces the interface's peer
          in one `wg set` (old peer removed, new one added), so it is as live as
          an endpoint rotation. The client private key needs no change: Proton
          registers it account-wide, so it handshakes with any of its servers.
          Pick servers in a different /24 than the primary — a dead server's
          neighbours often die with it.

          There is no automatic fail-back: a working fallback is kept until a
          reboot or the watchdog's own reset (after every candidate failed)
          puts the primary back. A rebuild or a manual `networkctl reconfigure`
          does NOT — networkd leaves an existing WireGuard device's peers alone.
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
        (my.vpn-server.interface). This module adds each client tunnel's
        `gateway` to it as an additional address; it does not otherwise touch
        it, and existing peers are left exactly as they are.
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
      example = [
        "192.168.2.0/24"
        "10.0.0.0/24"
        "10.0.1.0/24"
      ];
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

      viaTunnel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "es";
        description = ''
          Name of the client tunnel these LAN sources leave through. Required
          when `lanRedirect.enable` is on — with several exits configured there
          is no sensible default, and guessing one would silently pick a country
          on the user's behalf.
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

      notify = {
        command = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Alert sender, called as `<cmd> <topic> <title> <priority> <tags>
            <message>`, on a failover, an outage (every candidate failed for
            failuresBeforeRestart probes) and the recovery from one. Null (the
            default) sends nothing. Typically config.my.ntfy-alert.notifyCommand.
          '';
        };
        topic = lib.mkOption {
          type = lib.types.str;
          default = "alerts-system";
          description = "Topic passed to the alert sender.";
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "EnvironmentFile for the watchdog units (e.g. NTFY_TOKEN).";
        };
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
          `resolver.viaTunnel` set, the resolver's own
          upstream queries leave through that tunnel, so a hostname here is
          circular: the probe cannot resolve until the tunnel carries traffic,
          the watchdog reads that as the tunnel being down, and it restarts the
          tunnel every interval while DNS stays dead host-wide. `1.1.1.1` is
          used rather than a Proton endpoint because it is anycast, stable, and
          serves a certificate valid for the literal address.
        '';
      };
    };

    resolver = {
      viaTunnel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "es";
        description = ''
          Name of the client tunnel to send the local resolver's UPSTREAM
          queries out of, so public lookups carry a Proton source address rather
          than this line's. Null leaves upstream DNS on the ISP path.

          ONE tunnel, deliberately, even when several are configured. The
          resolver is a single host-wide service shared by the LAN and by every
          peer regardless of which exit that peer uses, so there is no per-query
          notion of "the right country" to honour — picking one and saying so is
          more honest than pretending the choice tracks the client. Choose the
          exit whose jurisdiction you would rather the upstream resolvers see.

          Split-horizon and the internal zones are unaffected and keep working
          from the local resolver either way — this only moves where a query that
          has to leave the house goes out.

          Steering is BY UID, which is why enabling this also takes the resolver
          off DynamicUser and gives it a declared user. A uid rule is consulted
          by the route lookup that `connect()` itself performs, so the socket is
          bound to the tunnel address from the start. The obvious-looking
          alternative — marking the packets in the OUTPUT mangle hook — cannot
          work: it runs after the source address has already been chosen, and
          the post-mangle reroute changes the route without revisiting the
          source, so queries leave for Proton carrying an RFC1918 address and
          are silently dropped.

          Failure here is DEGRADED, NOT DEAD. `resolver.table` holds only the
          tunnel route and no blackhole, so a dead tunnel empties it, this rule
          stops matching, and queries fall through to the ISP path still
          encrypted to the same no-log resolvers. verify-protonvpn.sh asserts
          both the rule and its effect, so the degraded state is visible rather
          than silent.

          Set to false to leave upstream DNS on the ISP path permanently, and to
          leave the resolver on DynamicUser. What this option buys is hiding the
          source address from those resolvers — worth having, not worth an
          outage, which is why the fallback below exists.
        '';
      };

      table = lib.mkOption {
        type = lib.types.int;
        default = 44;
        description = ''
          Routing table for the resolver's upstream queries, used by the uid
          rule at priority 1002.

          Deliberately NOT a client tunnel's own table. Those carry a blackhole
          default so steered PEER traffic fails closed, and pointing DNS at it
          means a dead tunnel takes name resolution down for the entire LAN and
          every VPN peer — which is exactly what happened, twice, before this
          was split out. This table holds the tunnel's default route and nothing
          else, so when the interface goes the table empties and the lookup
          falls through to `main` instead of terminating.
        '';
      };

      fallbackServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tls://dns.quad9.net" ];
        description = ''
          Resolvers the local resolver falls back to when its upstream cannot be
          reached — which, with `resolver.viaTunnel` set, is exactly what a dead
          tunnel looks like.

          This is the path that keeps ACME renewals, `nixos-rebuild` and every
          other name lookup on this box working while Proton is down. It
          deliberately does NOT use the ISP's resolver: fallback means degraded,
          not leaking. DoT to a third party keeps queries encrypted and keeps the
          ISP seeing nothing but a TLS session even in the degraded state.
        '';
      };
    };

    clientTunnels = lib.mkOption {
      default = { };
      description = ''
        Client egress tunnels, keyed by a short name that IS the user-facing
        identity of the exit — typically a country code (`es`, `in`, `us`). The
        name picks the interface (`proton-<name>`) and the kill-switch chain, so
        keep it short and stable: renaming one is a new interface and a new set
        of rules, not an edit.

        Each tunnel owns a `sourcePrefixes` range of the WireGuard server's
        address space. Selection is by PREFIX rather than by a per-peer list, so
        adding a peer to an exit is an allocation out of that range and needs no
        change here. Peers outside every tunnel's prefixes (the original
        10.0.0.0/24) keep direct, untunneled egress via the ISP — which is the
        right default for reaching LAN services, for anything geo-sensitive, and
        for anything that must survive Proton being down.

        The tunnels are independent: each has its own routing table, its own
        blackhole, its own kill-switch chain and its own watchdog. One being
        down affects only the peers allocated to it.
      '';
      example = lib.literalExpression ''
        {
          es = {
            server = "ES#95";
            table = 42;
            sourcePrefixes = [ "10.0.1.0/24" ];
            gateway = "10.0.1.1/24";
            privateKeyFile = config.sops.secrets."wireguard-client/wgproton-es".path;
            peer = {
              publicKey = "...=";
              endpoint = "192.0.2.10:51820";
            };
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options =
              (tunnelOptions {
                name = "proton-${name}";
                defaultTable = null;
              })
              // {
                # No default: a table number silently shared with another tunnel would
                # merge two exits into one, and the symptom (traffic leaving the wrong
                # country) is not one anybody would think to look for. Make it
                # explicit and let the assertion in ./default.nix catch collisions.
                table = lib.mkOption {
                  type = lib.types.int;
                  description = ''
                    Dedicated routing table for this tunnel's default route and
                    blackhole fallback. Must be unique across tunnels, must not be
                    `main`, and must not collide with `resolver.table`.
                  '';
                };

                sourcePrefixes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  example = [ "10.0.1.0/24" ];
                  description = ''
                    Sub-ranges of the WireGuard server's address space whose peers
                    egress via this tunnel. Every prefix listed here must also appear
                    in `localPrefixes`, or traffic from one tunneled prefix to another
                    hairpins out through Proton instead of staying local.
                  '';
                };

                gateway = lib.mkOption {
                  type = lib.types.str;
                  example = "10.0.1.1/24";
                  description = ''
                    Address added to `wgInterface` so it is on-link for this tunnel's
                    `sourcePrefixes`. Added ALONGSIDE the existing server address, not
                    in place of it.
                  '';
                };
              };
          }
        )
      );
    };

    p2pTunnel =
      tunnelOptions {
        name = "proton-p2p";
        defaultTable = 43;
      }
      // {
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
      # nginx can reach the web UI, and for nothing else: without a route to the
      # internet on it, and with the host refusing to forward anything off it
      # (see the FORWARD drop in ./default.nix), it cannot become a way around the tunnel.
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
          description = "Host end of the RPC link. This is what nginx connects from.";
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
}
