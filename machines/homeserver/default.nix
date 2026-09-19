# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  sops-nix,
  emacs-overlay,
  fugazi-web,
  fugazi-web-testing,
  nix-caddy-withplugins,
  ...
}:

let

  # `lib` is a module argument, so it is in scope inside `configuration` below but
  # NOT out here — and pkgsUnstable's allowInsecurePredicate needs it. Taken from
  # the flake input, which is the same lib the module system passes in. The inner
  # function's own `lib` parameter shadows this one within its body, harmlessly:
  # they are equal.
  inherit (nixpkgs) lib;

  homeServerLocalAddress = "192.168.2.2";

  # The physical uplink, named ONCE. Interface names are derived from the
  # device's PCI/USB path, so they are a property of the hardware and not of
  # this configuration: the same config on another box calls its wireless NIC
  # something else, and every reference here silently stops matching. That is
  # three separate outages at once — no static LAN address (the networkd network
  # below), no association (networking.wireless.interfaces), and no NAT for
  # WireGuard clients (my.vpn-server.upstreamInterface) — for a box whose only
  # uplink is this radio, so there is no second path to log in and fix it.
  # Exported through _module.args below so ./networking.nix reads the same
  # string; grep for it before moving hardware, and change it here only.
  uplinkInterface = "wlp3s0";
  adminEmailAddress = "admin@acpuchades.com";
  # Shared with fugazi.nix — the whys live in networks.nix.
  inherit (import ./networks.nix) lanNetwork wgNetworks privateNetworks;

  # nixpkgs-unstable, instantiated ONCE for the handful of packages this host
  # deliberately runs ahead of nixpkgs-26.05. Two consumers today — openclaw and
  # immich — each with its reason written at its use site below. Shared rather
  # than imported per consumer because `import <nixpkgs>` is a full evaluation of
  # the package set: doing it twice doubles that cost to produce two package sets
  # that differ only in a config flag neither of them changes a derivation with.
  #
  # The insecure permit is openclaw's (upstream marks every release
  # knownVulnerabilities for LLM prompt injection) and is written as a predicate
  # on the package NAME, so it stays openclaw-only and does not quietly bless
  # anything else that gets pulled from here — immich included, which is the
  # whole point of taking it from unstable rather than permitting 26.05's.
  pkgsUnstable = import nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowInsecurePredicate = p: lib.getName p == "openclaw";
  };

  configuration =
    inputs@{ config, options, lib, pkgs, ... }:
    {
      imports = [
        # Include the results of the hardware scan.
        ./hardware-configuration.nix

        # Host settings, imported as a module so it merges with full option
        # semantics. It used to be `import ./settings.nix inputs // { ... }`,
        # but that shallow `//` silently dropped any top-level key settings.nix
        # shared with the inline set — notably `services` (losing the journald
        # SystemMaxUse cap) and `security` (masking the sudo setting).
        ./settings.nix
        ./services.nix
        ./networking.nix
        ./sops.nix
        ./users.nix

        # Custom modules
        ../../modules/vpn-server
        ../../modules/wireguard-client
        ../../modules/protonvpn
        ../../modules/transmission-server
        ../../modules/dns-filtering
        ../../modules/web-server
        ../../modules/postgresql-server
        ../../modules/cloud-suite
        ../../modules/samba-server
        ../../modules/media-server
        ../../modules/print-server
        ../../modules/geocoding
        ../../modules/openclaw
        ../../modules/tor-bridge
        ../../modules/push-notifications
        ../../modules/mail-server
        ../../modules/prefect-server
        ../../modules/home-assistant
        ../../modules/server-stats
        ../../modules/web-analytics
        ../../modules/service-dashboard
        ../../modules/acme-cloudflare
        ../../modules/caddy-plugins
        ../../modules/host-security
        ../../modules/ups-monitor
        ../../modules/backup
        ../../modules/ntfy-alert

        # fugazi-web (testing.fugazitrade.com), in its own file: the service is
        # large enough that its policy helpers and instance configuration were
        # about half of this one. Curried over the flake inputs because its own
        # `imports` needs them — see the header there.
        (import ./fugazi.nix { inherit fugazi-web fugazi-web-testing; })
      ];

      # Make `uplinkInterface` a module argument, so the imports above (notably
      # ./networking.nix) name the same interface without re-declaring it.
      _module.args = { inherit uplinkInterface; };

      systemd.network.networks = {
        "10-${uplinkInterface}" = {
          matchConfig.Name = uplinkInterface;
          # Static LAN IP. The server's identity (192.168.2.2) is hardcoded
          # across AdGuard rewrites, the *.acpuchades.com vhosts,
          # homeServerLocalAddress and the router's 51820 port-forward, so it
          # must not float on DHCP (a lease change took the server down once).
          # Make sure 192.168.2.2 is outside the router's DHCP pool to avoid a
          # collision with a dynamically-assigned client.
          address = [ "192.168.2.2/24" ];
          gateway = [ "192.168.2.1" ];
          networkConfig = {
            DHCP = "no";
            DNS = [ "127.0.0.1" ];
          };
        };
      };

      # ddclient is driven by a sops configFile, which bypasses the NixOS
      # module's auto-injected cache= path — without this it falls back to a
      # directory inside the read-only Nix store. CacheDirectory provisions
      # /var/cache/ddclient (cache= in sops.nix points there).
      systemd.services.ddclient.serviceConfig.CacheDirectory = "ddclient";

      security.tpm2.enable = true;
      security.tpm2.pkcs11.enable = true;
      security.tpm2.tctiEnvironment.enable = true;

      # The options field had a leading slash for most of this disk's life, which
      # made systemd parse the whole string as one unknown option and drop it
      # ("Encountered unknown /etc/crypttab option '/tpm2-device=auto', ignoring").
      # The volume still unlocked, because systemd-cryptsetup finds the enrolled
      # systemd-tpm2 token in the LUKS2 header on its own — so the typo cost
      # nothing visible and went unnoticed. tpm2-device= is now real.
      #
      # `discard` is deliberately NOT restored. Both DAS drives are spinning rust
      # (WD60EZAX in a TerraMaster USB enclosure, ROTA=1) and the block device
      # advertises discard_max_bytes=0, so TRIM would do nothing here — while on
      # LUKS it leaks which blocks are unused to anyone who images the disk.
      #
      # `nofail` matches what fstab already says one layer up: a failed unseal
      # should not gate boot. Without it the generated cryptsetup unit carries
      # TimeoutSec=infinity and sits on a console password prompt under
      # sysinit.target, which on this headless box means physical access. With
      # it, boot continues to multi-user, SSH comes up, and keyslot 1 (the
      # argon2id passphrase) can be used remotely.
      environment.etc."crypttab".text = ''
        srv-encrypted /dev/disk/by-uuid/c5e7c042-5625-493f-9b8a-487ecdac277a - tpm2-device=auto,nofail
      '';

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = import ./packages.nix inputs;

      # Configure custom modules

      # Caddy's compiled-in plugins. The list is contributed by whichever modules
      # need one (acme-cloudflare's DNS-01 solver, fugazi-web's rate limiter);
      # only the hash lives here, because it is a property of the assembled set
      # and no single contributor can know it. Changing the set changes this —
      # rebuild and take the `got:` value from the mismatch.
      #
      # Under nix-caddy-withplugins (the overlay below) this covers ONLY the
      # plugins' own Go modules, so a Caddy or nixpkgs bump no longer touches it;
      # what does is adding, removing or bumping a plugin above. It was
      # `sha256-w1H86by…` under nixpkgs' withPlugins and is not comparable.
      my.caddy-plugins.hash = "sha256-6FwLem59rxu0M+Rz2nGylF5cTbO7meZb9j0Tqk5YY5A=";

      my.acme-cloudflare = {
        enable = true;
        credentialsFile = config.sops.templates."caddy/cloudflare-env".path;
      };

      my.vpn-server = {
        enable = true;
        privateKeyFile = config.sops.secrets."wireguard/private-key".path;
        serverPublicKey = "dnwEk7CRGfzDFJruRiCzmGNURU6Ba/OLUDpQ5ImO7G4=";
        serverEndpoint = "vpn.acpuchades.com:51820";
        clientDns = "10.0.0.1";
        upstreamInterface = uplinkInterface;
        peers = {
          alex-laptop = {
            publicKey = "96LNh5CjJQZuWpqquXlmc9cNU5sJzalzKcTcnMhqWSI=";
            allowedIPs = [ "10.0.1.2/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-laptop".path;
          };
          alex-ipad = {
            publicKey = "qek70rKtZ2KpDk5JvEJrc3HDP9E0i+uwyv8BJpFi4GQ=";
            allowedIPs = [ "10.0.1.3/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-ipad".path;
          };
          alex-phone-owner = {
            publicKey = "jzXucrFLPLL0og1QXP75R+oYUyTqNCRnD6gw3SMPI0M=";
            allowedIPs = [ "10.0.1.4/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-owner".path;
          };
          alex-phone-personal = {
            publicKey = "ayIoJHS1QIvbyixoVTRMuDB+RMoh6N7mgscfP7RY7wY=";
            allowedIPs = [ "10.0.1.5/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-personal".path;
          };
          alex-phone-work = {
            publicKey = "r/0vQN5JOLlWWOBwIi9SRJj8F06FrMP9xywO+PMs6Rc=";
            allowedIPs = [ "10.0.1.6/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-work".path;
          };
          mubin-laptop-personal = {
            publicKey = "Wk0VWDe0KNjrG8fDDTfFXpuNfZ8BNxLxhYiF1LFyCA4=";
            allowedIPs = [ "10.0.1.10/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-personal".path;
          };
          mubin-laptop-work = {
            publicKey = "3jUISZl3AQAScASjxNnoGPvayi1/3jbLUzVS+6Kzfmo=";
            allowedIPs = [ "10.0.1.11/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-work".path;
          };
          mubin-phone-personal = {
            publicKey = "y5XFrY1BT+lG25DM+0se9GBTiGcAv69Ag2twUbcWugE=";
            allowedIPs = [ "10.0.1.12/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-personal".path;
          };
          mubin-phone-work = {
            publicKey = "efhtt7/eRYIvoyda7u+0GUA7y6WOxZtbPjIUNwdOsF4=";
            allowedIPs = [ "10.0.1.13/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-work".path;
          };
        };
      };

      # ProtonVPN egress. Everything about how this is wired — policy routing,
      # the fail-closed chains, the P2P namespace, NAT-PMP, the watchdog — lives
      # in modules/protonvpn; what is host-specific is only the topology below.
      #
      # The two tunnels are on DIFFERENT Proton servers on purpose. Sharing one
      # would give browsing traffic and BitTorrent traffic the same exit address,
      # which is the one correlation this whole arrangement exists to prevent.
      my.protonvpn = {
        enable = true;

        wgInterface = config.my.vpn-server.interface;

        # One prefix per exit, allocated out of 10.0.N.0/24. A peer's exit is
        # decided by which prefix its address came from and by nothing else, so
        # moving a device between exits is an address change in its profile plus
        # the matching allowedIPs here — the keys never move.
        #
        #   10.0.0.0/24  untunneled (straight out the ISP)
        #   10.0.1.0/24  es      ← every peer today
        #   10.0.2.0/24  in
        #   10.0.3.0/24  us
        #
        # 10.0.0.0/24 is deliberately kept and deliberately empty. It is the
        # fallback: a device that needs the residential Spanish address (a bank,
        # a streaming licence) or that must keep working while Proton is down
        # gets a SECOND profile on it and switches in the WireGuard app. Nothing
        # about that path depends on Proton, which is exactly why it is worth a
        # reserved prefix rather than being reclaimed.
        #
        # Note what moving every peer to es costs, because it is not nothing:
        # the kill switch is fail-closed, so ES#124 going down now takes every
        # peer's internet with it rather than a subset. The watchdog rotates
        # endpoints on the first failed probe and resets the interface after
        # two, but the window is real and the fallback is manual — hence the
        # paragraph above.
        #
        # Every locally-reachable prefix, so traffic between them is never
        # tunneled — including between two tunneled prefixes, which must stay on
        # wg0 rather than hairpin out through Proton and back. Identical to
        # privateNetworks by construction: a peer that can be reached locally is
        # exactly a peer that is trusted locally, and keeping two lists in step
        # by hand is how one of them goes stale. The transmission RPC veth
        # (10.200.0.0/30) is deliberately absent from both: tunneled clients have
        # no business reaching the daemon's RPC directly, they reach the web UI
        # through Caddy like everything else.
        localPrefixes = privateNetworks;

        clientTunnels = {
          es = {
            server = "ES#124";
            table = 42;
            sourcePrefixes = [ "10.0.1.0/24" ];
            gateway = "10.0.1.1/24";
            privateKeyFile = config.sops.secrets."wireguard-client/wgproton-es".path;
            address = [ "10.2.0.2/32" ];
            peer = {
              publicKey = "XkiKln3Se1dUvLL9s803TbYkfFNJtb051iGcGs1jgSk=";
              endpoint = "130.195.250.98:51820";
            };
          };

          # India and the United States. Tables 42/43/44 are taken
          # (es, p2p, resolver), hence 45 and 46.
          "in" = { # quoted: `in` is a Nix keyword
            server = "IN#13";
            table = 45;
            sourcePrefixes = [ "10.0.2.0/24" ];
            gateway = "10.0.2.1/24";
            privateKeyFile = config.sops.secrets."wireguard-client/wgproton-in".path;
            address = [ "10.2.0.2/32" ];
            peer = {
              publicKey = "QnqJI0C2xQZrKfZLrBaCHa2h3TZ9CBt6sCuzg3ue4X4=";
              endpoint = "146.70.142.18:51820";
            };
          };

          us = {
            server = "US-NY#608";
            table = 46;
            sourcePrefixes = [ "10.0.3.0/24" ];
            gateway = "10.0.3.1/24";
            privateKeyFile = config.sops.secrets."wireguard-client/wgproton-us".path;
            address = [ "10.2.0.2/32" ];
            peer = {
              publicKey = "R8Of+lrl8DgOQmO6kcjlX7SchP4ncvbY90MB7ZUNmD8=";
              endpoint = "193.148.18.82:51820";
            };
          };
        };

        # Upstream DNS leaves through one exit, not per-client: the resolver is
        # a single host-wide service shared by the LAN and by every peer
        # whatever exit that peer uses, so there is no per-query country to
        # honour. Spain is chosen to match where this line actually is.
        resolver.viaTunnel = "es";

        p2pTunnel = {
          server = "ES#33 (P2P-flagged, NAT-PMP enabled)";
          privateKeyFile = config.sops.secrets."wireguard-client/wgproton-p2p".path;
          address = [ "10.2.0.2/32" ];
          # The same 10.2.0.2 as the client tunnel, which is what Proton hands
          # every config. Harmless here: this one lives in its own network
          # namespace, so the two addresses never share a routing table.
          peer = {
            publicKey = "roOsz9dJeKKVt6E3EIEKXQfZsmhSfsqOceZWiuGLIgg=";
            endpoint = "185.76.11.17:51820";
          };
        };
      };

      my.transmission-server = {
        enable = true;
        hostName = "torrent.acpuchades.com";
        downloadDir = "/srv/shared/Downloads";
        allowedNetworks = privateNetworks;
        basicAuthFile = config.sops.templates."caddy/torrent-auth".path;
        # Bumped above the module defaults (8000/1500 full, 2000/500 turtle) so
        # slow torrents aren't ceilinged — schedule unchanged (turtle 08:00–23:00,
        # full speed overnight). A cap is a ceiling not a floor: this only helps
        # torrents that actually have the peers to saturate it.
        maxDownKBps = 15000; # ~120 Mbit/s full speed (overnight 23:00–08:00)
        maxUpKBps = 2500;
        altDownKBps = 4000;  # ~32 Mbit/s turtle (active 08:00–23:00)
        altUpKBps = 1000;
      };

      my.dns-filtering = {
        enable = true;
        adguardPort = 3000;
        dnsPort = 53;
        dnsResolverPort = 5300;
        basicAuthFile = config.sops.templates."caddy/adguard-auth".path;
        virtualHost = "adguard.acpuchades.com";
        allowedNetworks = privateNetworks;
        # Plain DNS is for the LAN and the VPN only, never the public internet.
        # 10.0.0.0/24 (the wg subnet) is listed for defence in depth rather than
        # necessity: wg0 is a trustedInterface, so peer traffic to 10.0.0.1:53
        # bypasses the firewall chain entirely.
        allowedClientNetworks = privateNetworks;
        dnsRewrites = [
          # vpn.acpuchades.com is intentionally NOT rewritten here: it must
          # always resolve to the public IP (via DDNS) so the WireGuard endpoint
          # stays reachable. The router handles NAT hairpin for on-LAN clients,
          # which avoids the split-horizon blip a global AdGuard rewrite caused
          # for remote clients re-resolving the endpoint through the tunnel when
          # switching networks while connected.
          { domain = "acpuchades.com";           answer = homeServerLocalAddress; }
          { domain = "www.acpuchades.com";       answer = homeServerLocalAddress; }
          { domain = "blog.acpuchades.com";      answer = homeServerLocalAddress; }
          { domain = "home.acpuchades.com";      answer = homeServerLocalAddress; }
          { domain = "adguard.acpuchades.com";   answer = homeServerLocalAddress; }
          { domain = "bitwarden.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "photos.acpuchades.com";    answer = homeServerLocalAddress; }
          { domain = "media.acpuchades.com";     answer = homeServerLocalAddress; }
          { domain = "cloud.acpuchades.com";     answer = homeServerLocalAddress; }
          { domain = "collabora.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "prefect.acpuchades.com";   answer = homeServerLocalAddress; }
          { domain = "status.acpuchades.com";    answer = homeServerLocalAddress; }
          { domain = "analytics.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "dashboard.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "torrent.acpuchades.com";   answer = homeServerLocalAddress; }
          { domain = "nominatim.acpuchades.com"; answer = homeServerLocalAddress; }
          # fugazitrade.com is public AND proxied through Cloudflare, so these
          # rewrites do more than save a hairpin: a client resolving through
          # AdGuard reaches Caddy directly instead of going out to the CF edge and
          # back. Same app, same certificate, one less party in the path.
          #
          # The apex and www are kept here even though NOTHING serves them right
          # now — there is no vhost for either, so a request gets a TLS handshake
          # failure rather than a page, which is what "reserved for launch" should
          # look like. www stays in ddclient too, so its record is current on the
          # day `prod` takes it rather than dating from whenever the box last
          # moved. The apex does NOT: it is a CNAME to www in Cloudflare and
          # follows it on its own (see the ddclient block in sops.nix). It is
          # rewritten here anyway, because a CNAME would otherwise send a LAN
          # client out to the CF edge and back for a name this resolver can answer
          # directly.
          { domain = "fugazitrade.com";          answer = homeServerLocalAddress; }
          { domain = "www.fugazitrade.com";      answer = homeServerLocalAddress; }
          { domain = "testing.fugazitrade.com";  answer = homeServerLocalAddress; }
          # ntfy is reachable from off-LAN by design; this rewrite only affects
          # clients resolving through AdGuard, and just saves them a NAT hairpin.
          { domain = "ntfy.acpuchades.com";      answer = homeServerLocalAddress; }
        ];
      };

      my.web-server = {
        enable = true;
        adminEmail = adminEmailAddress;
        virtualHosts = {
          "acpuchades.com" = {
            redirect = "https://www.acpuchades.com";
          };
          "www.acpuchades.com" = {
            root = "/var/www/acpuchades.com";
          };
          "blog.acpuchades.com" = {
            redirect = "https://www.acpuchades.com/blog";
          };
        };
      };

      # nix-caddy-withplugins replaces `pkgs.caddy` with the same package carrying
      # a different `withPlugins`, the one whose plugin hash does not move when
      # Caddy is updated (see the flake input's comment, and my.caddy-plugins.hash
      # below). It takes `prev.caddy` and rebuilds it from our pkgs, so what runs
      # is still nixpkgs' Caddy at nixpkgs' version — only the way the plugin
      # sources are fetched changes. Nothing but my.caddy-plugins consumes it.
      #
      # ./fugazi.nix contributes fugazi-web's overlay to this same list.
      nixpkgs.overlays = [ nix-caddy-withplugins.overlays.default ];

      my.postgresql-server = {
        enable = true;
        dataDir = "/srv/encrypted/postgresql";
      };

      my.cloud-suite = {
        enable = true;
        bitwarden = {
          hostName = "bitwarden.acpuchades.com";
          signupsAllowed = false;
          dataDir = "/srv/encrypted/vaultwarden";
          allowedNetworks = privateNetworks;
        };
        collabora = {
          hostName = "collabora.acpuchades.com";
          port = 9980;
          # Its only consumer is Nextcloud (itself LAN-gated), loading the
          # editor iframe in the user's browser — so nothing public ever needs
          # this vhost, and the CODE admin console stays off the internet.
          allowedNetworks = privateNetworks;
        };
        email = {
          from = "noreply@acpuchades.com";
        };
        immich = {
          hostName = "photos.acpuchades.com";
          mediaLocation = "/srv/encrypted/immich";
          accelerationDevices = [ "/dev/dri/renderD128" ];

          # Immich 3.x from nixpkgs-unstable, because 26.05 has no runnable
          # Immich left: it ships 2.7.5, upstream ended 2.x support, and nixpkgs
          # marked the package insecure (CVE-2026-59258, CVE-2026-82272) — which
          # fails evaluation of this host's toplevel, not just Immich. Permitting
          # it would keep an unpatched, end-of-line release answering on a
          # public hostname; 3.x is the version that still gets fixes.
          #
          # Safe to cross channels here because the module is the same module:
          # 26.05's services.immich and unstable's differ only in a docstring and
          # one dropped env var, nothing in it is keyed on the Immich version,
          # and the database halves line up (both channels ship VectorChord
          # 1.1.1, and we are long past the pgvecto.rs cutoff that 3.0 requires).
          # Machine learning follows automatically — the module reads it from
          # this package's `machine-learning` passthru.
          #
          # Drop this when nixpkgs-26.05 carries Immich 3.x, or on the next
          # NixOS release: `nix eval nixpkgs#immich.version`, and if it is 3.x,
          # delete these two lines.
          package = pkgsUnstable.immich;
        };
        nextcloud = {
          hostName = "cloud.acpuchades.com";
          adminPasswordFile = config.sops.secrets."nextcloud/admin".path;
          maxUploadSize = "2G";
          phoneRegion = "ES";
          dataDir = "/srv/encrypted/nextcloud";
          allowedNetworks = privateNetworks;
          # Must list every app that was previously installed through the App
          # Store: appstoreEnable = false drops store-apps from apps_paths, so
          # anything still living only there silently disappears.
          extraApps = [
            "bookmarks" "calendar" "contacts" "gpoddersync" "groupfolders"
            "guests" "news" "nextpod" "notes" "richdocuments" "tasks"
            "twofactor_webauthn"
          ];
          # Probes status.php every 15 min; nextcloud-health is wired into
          # my.ntfy-alert.failureUnits below, closing the gap where a dead
          # Nextcloud (broken stateful config.php) looked green to systemd.
          healthCheck.enable = true;
        };
      };

      my.samba-server = {
        enable = true;
        group = "share";
        users = {
          alex = config.sops.secrets."samba/alex".path;
        };
        allowedNetworks = privateNetworks;
        shares = {
          shared = {
            path = "/srv/shared";
            comment = "Home server files";
            "read only" = false;
            # Anyone in the `share` group may read/write; new files land in the
            # group group-writable so other members can edit them too.
            "valid users" = "@share";
            "write list" = "@share";
            "force group" = "share";
            "create mask" = "0664";
            "force create mode" = "0660";
            "directory mask" = "2770";
            "force directory mode" = "2770";
          };
        };
      };

      my.media-server = {
        enable = true;
        hostName = "media.acpuchades.com";
        # Libraries live inside the Samba share so media dropped over SMB is
        # readable by Jellyfin; shareGroup = "share" makes jellyfin join the
        # group and provisions the folders root:share 2770 (matching the share).
        mediaDir = "/srv/shared/Media";
        libraries = [ "Movies" "Shows" "Music" ];
        shareGroup = "share";
        # Internal hosts only — Caddy restricts the vhost to the LAN/VPN subnets.
        allowedNetworks = privateNetworks;
        # TV/mobile apps keep talking straight to :8096 (this replaced the old
        # blanket LAN accept; drop it if every client moves to the vhost).
        allowedDirectNetworks = privateNetworks;
        # Same GPU render node Immich uses; enable the codecs in Jellyfin's UI.
        accelerationDevices = [ "/dev/dri/renderD128" ];
      };

      my.print-server = {
        enable = true;
        allowedNetworks = privateNetworks;
        # Driverless printers (IPP Everywhere / AirPrint) need no driver package.
        drivers = [];
        # Network printer at 192.168.2.3, driverless (IPP Everywhere). model =
        # "everywhere" derives the PPD by querying the device, so the printer must
        # be reachable at `nixos-rebuild switch` time. Print to it with
        # `lp -d HomePrinter <file>`.
        defaultPrinter = "HomePrinter";
        printers = [{
          name = "HomePrinter";
          location = "Home";
          deviceUri = "ipp://192.168.2.3/ipp/print";
          model = "everywhere";
          # Default to two-sided (long-edge / book-style). `Duplex` is the
          # standard PPD keyword CUPS's driverless PPD exposes; DuplexNoTumble =
          # flip on the long edge, DuplexTumble = short edge, None = one-sided.
          # This only sets the DEFAULT — a job can still override per-print
          # (`lp -o Duplex=None`/`sides=one-sided`). If the generated PPD names the
          # option `sides` instead, use `sides = "two-sided-long-edge";` here.
          ppdOptions = {
            Duplex = "DuplexNoTumble";
          };
        }];
      };

      # Nominatim. Kept LAN/WireGuard-only: a public geocoding endpoint is a
      # scraper magnet, and the only consumer here is Home Assistant. See the
      # module header — enabling this creates an EMPTY database; the Spain
      # extract has to be imported by hand once.
      my.geocoding = {
        enable = true;
        hostName = "nominatim.acpuchades.com";
        allowedNetworks = privateNetworks;
        # Keep the database off /srv/encrypted: that is a spinning disk, and
        # Nominatim is dominated by random index reads. /var/lib is on the ext4
        # NVMe root, which also sidesteps the btrfs CoW + zstd penalty the rest
        # of the cluster pays. A Spain extract needs ~15-20 GB of the 386 GB
        # free there.
        tablespace.enable = true;
        updates = {
          enable = true;
          # Must match the extract imported by hand (spain-latest.osm.pbf).
          replicationUrl = "https://download.geofabrik.de/europe/spain-updates/";
        };
      };

      # ntfy. Deliberately NOT restricted to privateNetworks — a push server
      # that only works on the LAN is pointless. Auth is deny-all instead, so
      # users/tokens must be created with the CLI before anything can publish
      # or subscribe. See the module header.
      my.push-notifications = {
        enable = true;
        hostName = "ntfy.acpuchades.com";
      };

      # OpenClaw agent — Telegram-only, loopback gateway, but NOT confined on
      # the host side (no sandbox/grants; see the module header).
      # Needs the two SOPS secrets below populated (declared in sops.nix):
      #   sops machines/homeserver/secrets/default.yml
      #     openclaw/eva/telegram-token, openclaw/eva/telegram-userid
      # Auth is the Claude subscription via the Claude CLI runtime — log in once:
      #   sudo -u eva -H claude            # /login, then quit
      # OpenClaw from nixpkgs-unstable (2026.6.33), NOT nixpkgs-26.05's 2026.5.7.
      # Why: 2026.5.7's claude-cli runtime has no handler for Claude Code's
      # permission protocol (control_request/can_use_tool), so a non-allowlisted
      # command hangs ~180s then dies with no Telegram prompt. 2026.6.33 adds the
      # responder (claude-live-session answers can_use_tool → allow under YOLO
      # else a clean deny) AND fixes the bundled-surface hardlink guard upstream
      # (plugin loaders now pass rejectHardlinks:false), which is what our
      # openclawPatched workaround exists to paper over. Taken from the shared
      # `pkgsUnstable` instance at the top of this file, whose insecure permit is
      # this package's (openclaw is marked knownVulnerabilities upstream) and is
      # version-agnostic, so it survives unstable's openclaw bumps without
      # editing a version string.
      my.openclaw = {
        # SHARED across all agent instances — the one OpenClaw build they all run.
        package = pkgsUnstable.openclaw;

        # A single agent for now: eva (Telegram bot eva_lebbot), with her own OS
        # user, home, memory/state dir (/var/lib/openclaw/eva) and gateway service
        # (openclaw-eva.service). Her full instance config lives in its own file;
        # additional agents would be added as sibling `instances.<name>` imports,
        # each its own user, bot token and state (only `package` here is shared).
        instances.eva = import ../../users/alex/agents/eva.nix {
          inherit config pkgs;
        };
      };

      # obfs4 Tor bridge. Both ports below still need forwarding on the router,
      # same as 51820 for WireGuard.
      my.tor-bridge = {
        enable = true;
        nickname = "acpuchades";
        contactInfo = adminEmailAddress;
        bandwidth = {
          rate = "10 MBytes";
          burst = "20 MBytes";
        };
      };

      # Wildcard cert for *.acpuchades.com, shared by Postfix (mail STARTTLS) and
      # any other service that needs a NixOS-managed cert for this domain.
      # Caddy manages its own certs independently via the acme-cloudflare module.
      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@acpuchades.com";
        certs."acpuchades.com" = {
          extraDomainNames = [ "*.acpuchades.com" ];
          dnsProvider = "cloudflare";
          environmentFile = config.sops.templates."acme/cloudflare-env".path;
          group = "postfix";
          reloadServices = [ "postfix.service" ];
          # This host's own resolver (AdGuard, 127.0.0.1) split-horizons
          # acpuchades.com to the LAN IP and returns no SOA for the apex, which
          # breaks lego's DNS-01 zone-walk ("cloudflare: failed to find zone com.").
          # Point lego at a public resolver so zone detection + propagation checks
          # see the real Cloudflare SOA instead of the local rewrite.
          dnsResolver = "1.1.1.1:53";
        };
      };

      my.mail-server = {
        enable = true;
        hostname = "mail.acpuchades.com";
        origin = "acpuchades.com";
        # Public identity e.nebot@acpuchades.com is a Cloudflare Email Routing
        # alias forwarding to eva@mail.acpuchades.com, which (mailDomain being
        # local) delivers straight to the eva system user's ~/Maildir.
        mailDomain = "mail.acpuchades.com";
        # rspamd stamps `X-Trusted-Sender: yes` on inbound mail whose From is one
        # of these AND passes DMARC (spoof-proof). eva keys "may act on this mail"
        # off that header, not the raw From. Pulled from eva's own unprompted-send
        # list (defined in agents/eva.nix) so trust stays symmetric in both
        # directions without a second copy of the addresses to drift.
        trustedSenders = config.my.openclaw.instances.eva.mail.unpromptedRecipients;
        relayHost = "[in-v3.mailjet.com]:587";
        saslPasswordFile = config.sops.templates."postfix/sasl_passwd".path;
        # Use the shared wildcard cert instead of managing a per-hostname cert.
        acmeCertName = "acpuchades.com";
      };

      # Encrypted off-site backups to Backblaze B2 (restic, client-side AES-256).
      # Covers the irreplaceable, non-declarative state: DB dumps, all user homes
      # (keys, configs, shell histories, ~/.claude memory, eva's Maildir + agent
      # state) and the cloud-suite data dirs. Home coverage is a DENYLIST, not an
      # allowlist — backing up all of /home and excluding the re-acquirable caches
      # means new important dirs are caught automatically instead of silently
      # missed (the failure mode of a curated path list). Still EXCLUDES the big
      # reproducible sets — Bitcoin chainstate, Nominatim DB, Samba media/downloads,
      # and per-home caches/build artifacts — so the off-site copy stays small.
      # Repo password + B2 credentials come from sops (backup/* below).
      my.backup = {
        enable = true;
        repository = "b2:acpuchades-homeserver-restic:restic";
        passwordFile = config.sops.secrets."backup/restic-password".path;
        environmentFile = config.sops.templates."backup/b2-env".path;

        # Data-directory paths tracked off their owning modules' options so they
        # follow any relocation. /home covers both alex and eva (incl. Maildir).
        paths = [
          "/home"                                            # all user homes (caches excluded below)
          "/var/lib/openclaw/eva"                            # eva agent state/memory
          "/var/lib/hass"                                    # Home Assistant config
          "/srv/prefect"                                     # Prefect data dir

          # --- machine identity, not user data --------------------------------
          # These are what turn "the config rebuilds" into "the machine comes
          # back". Small, and none of them is reproducible from this repo.
          #
          # /etc/ssh holds the host keys, and the ed25519 one IS the age identity
          # sops-nix decrypts every homeserver secret with (sops.age.sshKeyPaths).
          # Storing it here is safe — restic encrypts client-side with AES-256
          # before anything reaches B2, which only ever sees opaque blobs, and
          # the repo password never leaves the host. What it does NOT do is
          # bootstrap itself: the repo password is `backup/restic-password`, a
          # sops secret decrypted by this very key, so a copy of the restic
          # password (and the master age key) must live OFF this machine — and
          # not only in Vaultwarden, which is hosted here. With those two in hand
          # this entry is what makes a rebuild on new hardware a restore rather
          # than a re-key of every secret in the repo.
          "/etc/ssh"                                         # host keys = the sops age identity
          # NixOS records its allocated uids/gids here. Restore the data without
          # it and every dynamically-allocated service user can come back on a
          # different number, leaving the restored trees owned by nobody.
          "/var/lib/nixos"                                   # uid/gid allocation map
          # ACME account key + issued certs. Re-issue is automatic, so this is
          # only a convenience — but it means HTTPS works the minute the new box
          # boots, and it keeps a migration from spending a Let's Encrypt
          # duplicate-certificate rate limit on ~15 vhosts at once.
          "/var/lib/acme"
          # The bridge's long-term identity: lose it and the relay comes back as
          # a brand-new bridge (new fingerprint, reputation and uptime history
          # reset, and any obfs4 bridgeline already handed out stops working).
          "/var/lib/tor"
          # Accounts, watch state and library metadata. The MEDIA is deliberately
          # not backed up (below), but "who watched what, and where they left
          # off" is not re-acquirable from anywhere.
          "/var/lib/jellyfin"
          # Torrent files + resume state. Tiny, and without it every active
          # transfer restarts from zero and re-hashes.
          "/var/lib/transmission"

          config.my.cloud-suite.nextcloud.dataDir            # /srv/encrypted/nextcloud
          config.my.cloud-suite.bitwarden.dataDir            # /srv/encrypted/vaultwarden
          config.my.cloud-suite.immich.mediaLocation         # /srv/encrypted/immich
          "/srv/shared"                                      # Samba share (media/downloads excluded)
        ];

        # Keep the big, re-acquirable trees out of the off-site copy.
        exclude = [
          "/srv/shared/Media"
          "/srv/shared/Downloads"
          # 1.2 T of sequencing data — on its own it was ~60% of every snapshot
          # and pushed the repo past 2 TiB, which is the difference between a
          # restore measured in hours and one measured in days (plus the B2
          # egress to match). It is bulk source data, not service state, so it
          # belongs on its own copy (a second local disk, or a separate restic
          # repo with its own retention) rather than in the nightly one whose job
          # is getting this HOST back.
          "/srv/shared/NGS"
          # Re-derivable from the media itself: artwork/NFO scraped from the
          # metadata providers. The parts of /var/lib/jellyfin worth keeping
          # (library.db, users, playstate) are not in here. Transcodes need no
          # exclude: Jellyfin writes them under its cacheDir
          # (/var/cache/jellyfin), which is not a backup path at all.
          "/var/lib/jellyfin/metadata"
          # Immich's derivatives live INSIDE mediaLocation, so without these
          # they ride along with the originals — regenerable data (3.x
          # derivatives can rival the originals in size) paying for B2 space
          # and restore time. Immich rebuilds both from the originals;
          # profile/ (avatars, not regenerable) stays in.
          "${config.my.cloud-suite.immich.mediaLocation}/thumbs"
          "${config.my.cloud-suite.immich.mediaLocation}/encoded-video"
          "/srv/shared/**/.incomplete"
          "/var/lib/hass/*.log*"
          # Per-home caches / build artifacts: re-acquirable and they churn every
          # snapshot. Drops ~7.7G of /home/alex's 8.2G while keeping keys, configs,
          # histories, Org, and ~/.claude (memory + transcripts).
          "/home/*/.cache"
          "/home/*/.cargo"
          "/home/*/.npm"
          "/home/*/.local/share/uv"
          "/home/*/.claude/projects/*/shell-snapshots"       # ephemeral shell captures
          "/home/alex/nominatim"                             # Geofabrik import data, re-downloadable
          "/home/alex/nix-config"                            # version-controlled + pushed to GitHub
        ];

        # PostgreSQL: dump every live DB except the huge, re-importable Nominatim
        # extract (rebuild from Geofabrik, not worth the off-site GB).
        postgres.excludeDatabases = [ "nominatim" ];

        # SQLite services snapshot-copied consistently before upload.
        sqliteDatabases = [
          { name = "grafana"; path = "/var/lib/grafana/grafana.db"; }
          { name = "ntfy";    path = "/var/lib/ntfy-sh/user.db"; }
        ];

        # Quiesce NextCloud during the backup so files + DB agree.
        nextcloudOccBin = "${config.services.nextcloud.occ}/bin/nextcloud-occ";

        # Retention: 7 daily, 4 weekly, 6 monthly (host default; here explicit).
        pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];

        # Failure alerting is handled by my.ntfy-alert — restic-backups-homeserver
        # is opted into its failureUnits below.
      };

      my.home-assistant = {
        enable = true;
        hostName = "home.acpuchades.com";
        allowedNetworks = privateNetworks;
        extraComponents = [
          "alexa_devices"
          "conversation"
          "hue"
          "met"
          "nut"
          "roborock"
          "smartthings"
          "spotify"
          "stream"
        ];
        email.from = "noreply@acpuchades.com";
        email.recipient = adminEmailAddress;
      };

      my.server-stats = {
        enable = true;
        hostName = "status.acpuchades.com";
        port = 3001;
        allowedNetworks = privateNetworks;
        secretKeyFile = config.sops.secrets."grafana/secret-key".path;
        rendererTokenFile = config.sops.secrets."grafana/renderer-token".path;
        rendererAuthEnvFile = config.sops.templates."grafana/renderer-env".path;
      };

      my.web-analytics = {
        enable = true;
        hostName = "analytics.acpuchades.com";
        appSecretFile = config.sops.secrets."umami/app-secret".path;
      };

      my.service-dashboard = {
        enable = true;
        hostName = "dashboard.acpuchades.com";
        allowedNetworks = privateNetworks;
        # Tiles reference each service's own hostName option, so they track
        # renames automatically — no second copy of the addresses to drift.
        groups = [
          {
            name = "Cloud";
            services = [
              { name = "Nextcloud";   icon = "nextcloud.png";        description = "Files, calendar, contacts & notes"; href = "https://${config.my.cloud-suite.nextcloud.hostName}"; }
              { name = "Immich";      icon = "immich.png";           description = "Photo & video backup";              href = "https://${config.my.cloud-suite.immich.hostName}"; }
              { name = "Vaultwarden"; icon = "vaultwarden.png";      description = "Password manager";                  href = "https://${config.my.cloud-suite.bitwarden.hostName}"; }
              { name = "Collabora";   icon = "collabora-online.png"; description = "Online office suite";               href = "https://${config.my.cloud-suite.collabora.hostName}"; }
            ];
          }
          {
            name = "Media";
            services = [
              { name = "Jellyfin"; icon = "jellyfin.png"; description = "Movies, shows & music"; href = "https://${config.my.media-server.hostName}"; }
            ];
          }
          {
            name = "Smart Home";
            services = [
              { name = "Home Assistant"; icon = "home-assistant.png"; description = "Home automation"; href = "https://${config.my.home-assistant.hostName}"; }
            ];
          }
          {
            name = "Network";
            services = [
              { name = "AdGuard Home"; icon = "adguard-home.png"; description = "DNS filtering"; href = "https://${config.my.dns-filtering.virtualHost}"; }
              { name = "Transmission"; icon = "transmission.png"; description = "BitTorrent client"; href = "https://${config.my.transmission-server.hostName}"; }
            ];
          }
          {
            name = "Workflows & Analytics";
            services = [
              { name = "Prefect";     icon = "https://avatars.githubusercontent.com/u/39270919?s=200&v=4"; description = "Workflow orchestration"; href = "https://${config.my.prefect-server.virtualHost}"; }
              { name = "Umami";       icon = "umami.png";      description = "Web analytics";          href = "https://${config.my.web-analytics.hostName}"; }
              { name = "Nominatim";   icon = "mdi-map-search"; description = "OSM geocoding & reverse geocoding"; href = "https://${config.my.geocoding.hostName}"; }
            ];
          }
          {
            name = "Monitoring";
            services = [
              { name = "Grafana"; icon = "grafana.png"; description = "Metrics & dashboards"; href = "https://${config.my.server-stats.hostName}"; }
              { name = "ntfy";    icon = "mdi-bell-ring";  description = "Push notifications";    href = "https://${config.my.push-notifications.hostName}"; }
            ];
          }
        ];
      };

      my.host-security = {
        enable = true;
        fail2ban = {
          enable = true;
          ignoreIP = privateNetworks;
        };
      };

      my.ups-monitor = {
        enable = true;
        monitorPasswordFile = config.sops.secrets."nut/monitor".path;
        network.enable = true;
        network.allowedNetworks = privateNetworks;
        # Push power events (on-battery, low-battery, back-online…) to ntfy.
        notify.command = config.my.ntfy-alert.powerNotifyCommand;
        notify.environmentFile = config.sops.templates."ntfy/env".path;
      };

      # Opt-in ntfy alerting. The module forces nothing; alerts fire only for the
      # units listed here (and the UPS wiring above). One shared ntfy token
      # (ntfy/token) backs all of it, backup included.
      my.ntfy-alert = {
        enable = true;
        environmentFile = config.sops.templates."ntfy/env".path;
        # All suitable long-running services whose failure means a real outage.
        # Bare unit names (no .service). Setup/one-shot units are excluded
        # (they fail visibly at deploy time, not in steady state) — with one
        # deliberate exception: nextcloud-health, the timer-driven probe that
        # exists precisely because a Nextcloud dead from a broken stateful
        # config.php keeps phpfpm-nextcloud and nextcloud-cron green.
        failureUnits = [
          "nextcloud-health"
          "restic-backups-homeserver"
          "postgresql"
          "redis-nextcloud"
          "redis-immich"
          "caddy"
          "postfix"
          "vaultwarden"
          "phpfpm-nextcloud"
          "nextcloud-cron"
          "immich-server"
          "home-assistant"
          "prefect-server"
          "fugazi-web-testing"
          # The resident deployment tickers, and only those: the twelve timed
          # cadences are oneshots, which this list deliberately excludes. These
          # three are long-running units with no timer behind them, so one that
          # systemd stops retrying advances nothing until a human notices.
          "fugazi-web-testing-deployment-tick-1m"
          "fugazi-web-testing-deployment-tick-3m"
          "fugazi-web-testing-deployment-tick-5m"
          "ddclient"
          "openclaw-eva"
          "bitcoind-main"
          "upsd"
          "upsmon"
        ];
      };


      my.prefect-server = {
        enable = true;
        # Loopback only: the Prefect API has NO authentication, and it can run
        # arbitrary code as the prefect user (deployments/flow runs). The Caddy
        # vhost (basic-auth) is the only intended way in; the local workers
        # already target 127.0.0.1:4200 directly.
        host = "127.0.0.1";
        port = 4200;
        dataDir = "/srv/prefect";
        baseUrl = "https://prefect.acpuchades.com";
        virtualHost = "prefect.acpuchades.com";
        basicAuthFile = config.sops.templates."caddy/prefect-auth".path;
        workerPools.default.installPolicy = "if-not-present";
      };

      # Copy the NixOS configuration file and link it from the resulting system
      # (/run/current-system/configuration.nix). This is useful in case you
      # accidentally delete configuration.nix.
      # system.copySystemConfiguration = true;

      # This option defines the first version of NixOS you have installed on this particular machine,
      # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
      #
      # Most users should NEVER change this value after the initial install, for any reason,
      # even if you've upgraded your system to a new NixOS release.
      #
      # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
      # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
      # to actually do that.
      #
      # This value being lower than the current NixOS release does NOT mean your system is
      # out of date, out of support, or vulnerable.
      #
      # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
      # and migrated your data accordingly.
      #
      # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
      system.stateVersion = "25.05"; # Did you read the comment?

    };

in

nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = import ../common.nix {
    host = "homeserver";
    homeDirectory = "/home/alex";
    inherit sops-nix emacs-overlay;
  } ++ [
    configuration
    sops-nix.nixosModules.sops
    home-manager.nixosModules.home-manager
  ];
}
