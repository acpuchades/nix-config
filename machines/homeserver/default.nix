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
  ...
}:

let

  homeServerLocalAddress = "192.168.2.2";
  adminEmailAddress = "admin@acpuchades.com";
  privateNetworks = [ "192.168.2.0/24" "10.0.0.0/24" ];

  # Cloudflare's published edge ranges (cloudflare.com/ips-v4 + ips-v6, fetched
  # 2026-08-18). fugazitrade.com is proxied through Cloudflare — its public A
  # records are CF anycast addresses — so these, not the visitor, are the peers
  # Caddy sees, and they are the hops the backend has to skip to find the real
  # caller. Used only by my.fugazi-web.trustedProxies below; nothing else on this
  # host is fronted by a CDN. Cloudflare changes the list rarely and announces it;
  # re-fetch if public callers start sharing a rate-limit bucket.
  cloudflareNetworks = [
    "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
    "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
    "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
    "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
    "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
    "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32"
  ];

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

        # Host-specific policy routing: ProtonVPN egress for wg0 clients.
        # DISABLED 2026-06-02: wg0 clients reached the LAN but had no usable
        # internet through the nested wgproton tunnel. TWO distinct faults:
        #   (a) PMTU black-holing — the 1340 tunnel dropped clients' large
        #       TCP/QUIC packets (a "need to frag (mtu 1340)" flood). Lowering
        #       the client profile MTU to 1280 (tried on alex-laptop) DID stop
        #       the flood — so this part is understood/fixable.
        #   (b) UNRESOLVED: even with (a) fixed, FORWARDED client traffic
        #       (masqueraded to 10.2.0.2) still gets NO replies back from Proton,
        #       while server-sourced egress (also 10.2.0.2, but OUTPUT path) AND
        #       the gateway's own 10.2.0.1<->10.2.0.2 ICMP ping-pong both work.
        #       The tunnel is healthy; only relayed/forwarded flows black-hole on
        #       the return leg. Root cause not found (needs an outer-path capture
        #       on wlp3s0 to see if forwarded encrypted pkts reach Proton / if
        #       encrypted replies come back).
        # Disabled so wg0 clients egress directly via the ISP (vpn-server's NAT,
        # no kill switch, real ISP IP). Re-enabling needs (b) solved, not just
        # the MTU. (sops secret left in place.)
        # ./vpn-egress.nix

        # Host-specific egress confinement + NAT-PMP for the transmission daemon.
        # DISABLED 2026-05-30: ProtonVPN port forwarding (NAT-PMP) is not serviced
        # for this account on its servers — the request egresses fine but Proton
        # never replies, so the BT tunnel gets no inbound peer port. Re-enable this
        # together with the wgproton-bt interface and my.transmission-server below
        # once port forwarding works. (sops secrets are intentionally left in place.)
        # ./transmission-egress.nix

        # Custom modules
        ../../modules/vpn-server
        ../../modules/wireguard-client
        ../../modules/transmission-server
        ../../modules/dns-filtering
        ../../modules/web-server
        ../../modules/postgresql-server
        ../../modules/cloud-suite
        ../../modules/samba-server
        ../../modules/media-server
        ../../modules/print-server
        ../../modules/gps-backend
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
        ../../modules/fugazi-web

        # The fugazi-web service itself (`services.fugazi-web`): the uvicorn unit,
        # the maintenance timer and the per-frequency deployment-tick timers all
        # live upstream. ../../modules/fugazi-web is only the host topology around
        # it (Caddy, Postgres, SMTP loopback, sops env) and drives this module.
        fugazi-web.nixosModules.default
      ];

      systemd.network.networks = {
        "10-wlp3s0" = {
          matchConfig.Name = "wlp3s0";
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

      environment.etc."crypttab".text = ''
        srv-encrypted /dev/disk/by-uuid/c5e7c042-5625-493f-9b8a-487ecdac277a - /tpm2-device=auto,discard
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
      my.caddy-plugins.hash = "sha256-7GoH8YLCoPmPExQxoga2FHB58zQDoZVf1BBwkVi0SsQ";

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
        upstreamInterface = "wlp3s0";
        peers = {
          alex-laptop = {
            publicKey = "96LNh5CjJQZuWpqquXlmc9cNU5sJzalzKcTcnMhqWSI=";
            allowedIPs = [ "10.0.0.2/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-laptop".path;
          };
          alex-ipad = {
            publicKey = "qek70rKtZ2KpDk5JvEJrc3HDP9E0i+uwyv8BJpFi4GQ=";
            allowedIPs = [ "10.0.0.3/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-ipad".path;
          };
          alex-phone-owner = {
            publicKey = "jzXucrFLPLL0og1QXP75R+oYUyTqNCRnD6gw3SMPI0M=";
            allowedIPs = [ "10.0.0.4/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-owner".path;
          };
          alex-phone-personal = {
            publicKey = "ayIoJHS1QIvbyixoVTRMuDB+RMoh6N7mgscfP7RY7wY=";
            allowedIPs = [ "10.0.0.5/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-personal".path;
          };
          alex-phone-work = {
            publicKey = "r/0vQN5JOLlWWOBwIi9SRJj8F06FrMP9xywO+PMs6Rc=";
            allowedIPs = [ "10.0.0.6/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-work".path;
          };
          mubin-laptop-personal = {
            publicKey = "Wk0VWDe0KNjrG8fDDTfFXpuNfZ8BNxLxhYiF1LFyCA4=";
            allowedIPs = [ "10.0.0.10/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-personal".path;
          };
          mubin-laptop-work = {
            publicKey = "3jUISZl3AQAScASjxNnoGPvayi1/3jbLUzVS+6Kzfmo=";
            allowedIPs = [ "10.0.0.11/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-work".path;
          };
          mubin-phone-personal = {
            publicKey = "y5XFrY1BT+lG25DM+0se9GBTiGcAv69Ag2twUbcWugE=";
            allowedIPs = [ "10.0.0.12/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-personal".path;
          };
          mubin-phone-work = {
            publicKey = "efhtt7/eRYIvoyda7u+0GUA7y6WOxZtbPjIUNwdOsF4=";
            allowedIPs = [ "10.0.0.13/32" ];
            presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-work".path;
          };
        };
      };

      # ProtonVPN egress tunnel (ES#95). Installs its default route into a
      # dedicated table (42, not main), so bringing it up never touches the
      # host's default route; machines/homeserver/vpn-egress.nix steers the
      # 10.0.0.0/24 client subnet into that table with a kill switch. DNS
      # (10.2.0.1) from the profile is intentionally ignored; resolution stays
      # on AdGuard Home.
      my.wireguard-client = {
        enable = true;
        # DISABLED 2026-06-02 together with ./vpn-egress.nix above: forwarded
        # wg0-client egress through this tunnel got no replies from Proton (full
        # reasoning on the import comment — MTU was only part of it). With egress
        # steering gone the tunnel would just sit up unused, so it's disabled too.
        # Re-enabling needs the forwarded-no-reply issue solved, not just the MTU.
        # interfaces.wgproton = {
        #   privateKeyFile = config.sops.secrets."wireguard-client/wgproton".path;
        #   address = [ "10.2.0.2/32" "2a07:b944::2:2/128" ];
        #   allowedIPsAsRoutes = true;
        #   table = "42";
        #   mtu = 1340; # nested inside wg0 — lower MTU avoids PMTU black-holing
        #   peer = {
        #     publicKey = "tEz96jcHEtBtZOmwMK7Derw0AOih8usKFM+n4Svhr1E=";
        #     endpoint = "130.195.250.66:51820";
        #     allowedIPs = [ "0.0.0.0/0" ]; # IPv4 only; wg0 clients have no IPv6, avoids a dead ::/0 route
        #   };
        # };

        # Second ProtonVPN tunnel, dedicated to the transmission daemon so its
        # BitTorrent traffic exits on a separate IP with NAT-PMP port forwarding.
        # Proton hands every config the same 10.2.0.2/32 address; that's fine here
        # because the route lives in its own table (43, not main), exactly like
        # wgproton/table 42 — the duplicate interface address never reaches the
        # main table. IPv4-only (table 43 carries no v6 route); the IPv6 address
        # is omitted since it would be unused. Confinement + kill switch + NAT-PMP
        # are in machines/homeserver/transmission-egress.nix.
        #
        # DISABLED 2026-05-30: Proton port forwarding isn't serviced for this
        # account (NAT-PMP never replies), so this tunnel has no purpose for now.
        # Re-enable with ./transmission-egress.nix and my.transmission-server.
        # interfaces.wgproton-bt = {
        #   privateKeyFile = config.sops.secrets."wireguard-client/wgproton-bt".path;
        #   address = [ "10.2.0.2/32" ];
        #   allowedIPsAsRoutes = true;
        #   table = "43";
        #   mtu = 1340; # nested inside wg0 — lower MTU avoids PMTU black-holing
        #   peer = {
        #     publicKey = "XkiKln3Se1dUvLL9s803TbYkfFNJtb051iGcGs1jgSk=";  # ES#124
        #     endpoint = "130.195.250.98:51820";
        #     allowedIPs = [ "0.0.0.0/0" ];
        #   };
        # };
      };

      # NOTE 2026-05-31: enabled WITHOUT VPN egress confinement for now — the
      # wgproton-bt tunnel and ./transmission-egress.nix (kill switch + NAT-PMP)
      # above stay disabled until Proton port forwarding works. So the daemon
      # currently egresses via the default route (real ISP IP, no kill switch)
      # and has no inbound peer port (peer-port stays at its placeholder, LAN
      # firewall closed). Re-enable wgproton-bt + transmission-egress to confine it.
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

      # TEMPORARY 2026-05-31: open the BitTorrent peer port (TCP+UDP 51413) on the
      # host firewall so a router port-forward to this machine reaches the daemon.
      # The module forces this off (openPeerPorts = false) on the assumption the
      # peer port lives on the wgproton-bt tunnel; with that tunnel disabled the
      # port has to be opened on the LAN firewall instead. Forward TCP+UDP 51413
      # on the router → 192.168.2.2. REVERT this when wgproton-bt + transmission-
      # egress come back (the tunnel's NAT-PMP supplies the inbound port instead).
      services.transmission.openPeerPorts = lib.mkForce true;

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
          { domain = "gps.acpuchades.com";       answer = homeServerLocalAddress; }
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

      # The backend + frontend packages come from the fugazi-web flake's overlay
      # (pkgs.fugazi-service, pkgs.fugazi-web-frontend), built against our nixpkgs.
      # Its NixOS module (imported above) derives the units from the same pkgs.
      nixpkgs.overlays = [ fugazi-web.overlays.default ];

      # ONE instance for now, and it is `testing`. Everything that has been built
      # so far — the accounts, the uploaded datasets, the tier table, the running
      # deployments — moves here rather than staying on a `prod` that is not ready
      # to be called that. The public name is deliberately dark until launch; see
      # the note under my.web-server for what fugazitrade.com serves meanwhile.
      #
      # `prod` will be a sibling entry when it launches: its own hostName, its own
      # port (8765 is left free for exactly that), its own database and its own JWT
      # secret. Its intended shape is in git — commit 3224eb7, which had both
      # instances defined — rather than sitting here commented out.
      my.fugazi-web.instances.testing = {
        hostName = "testing.fugazitrade.com";
        port = 8766;

        # The database and the JWT secret are the ones ALREADY IN USE, not fresh
        # ones. That is the whole point of the move: this instance is not a copy of
        # the deployment, it *is* the deployment, renamed. Keeping `fugazi` means
        # every account, dataset and running deployment carries over with no dump
        # and no migration, and keeping `fugazi/env` means nobody is logged out —
        # the JWT signature is all the API verifies, so a fresh key would
        # invalidate every session in existence.
        #
        # The names therefore read one notch off (instance `testing` on database
        # `fugazi`) and that is correct rather than sloppy: renaming a live
        # database to match a nix attribute would be moving real data to satisfy a
        # label. When `prod` launches it gets its own, and this one keeps what it
        # has.
        databaseName = "fugazi";
        environmentFile = config.sops.templates."fugazi/env".path;

        # The whole `packages` output of the second input, in one go, so a backend
        # and a frontend cannot end up from different branches. This single line is
        # the entire branch-tracking mechanism; see the fugazi-web-testing input in
        # flake.nix for why it is packages rather than a second imported module.
        packages = fugazi-web-testing.packages.${pkgs.stdenv.hostPlatform.system};

        # Reachable from the internet, and no allowedNetworks: this is not a
        # LAN-only service, it is an unlaunched public one. What stands between a
        # stranger and this box is the signup domain gate and the tier table
        # below, plus upstream's per-caller budgets on /v1/auth — and those
        # budgets are only as good as trustedProxies, hence the next line.
        #
        # Requests arrive Cloudflare -> Caddy -> uvicorn, so the hop Caddy appends
        # to X-Forwarded-For is a Cloudflare edge, not the visitor. Trusting only
        # loopback would make that edge the rate-limit bucket and every visitor
        # routed through it would share one register/login budget.
        trustedProxies = [ "127.0.0.1/32" "::1/128" ] ++ cloudflareNetworks;

        # Not launched, so not indexed. Signup is gated to @fugazitrade.com (see
        # below) and the app is perfectly usable by anyone holding such an address
        # — what this withholds is being *found*, which is the part that would be
        # hard to undo. A search result for a half-finished service outlives the
        # half-finished service.
        noIndex = true;

        # mailFrom stays the module default (noreply@acpuchades.com): this is the
        # only deployment sending mail, so there is no second sender to tell it
        # apart from. It gains a -testing suffix when prod launches beside it.
      };

      # Knobs modules/fugazi-web deliberately doesn't re-expose go straight on the
      # upstream option; `environment` is an attrsOf, so these merge with the keys
      # the module sets rather than replacing them. Per INSTANCE, so this is the
      # whole of the policy for the one deployment that exists — everything below
      # is what has been decided so far, moved here intact rather than re-derived.
      services.fugazi-web.instances.testing.environment = {
        # Registration is limited to @fugazitrade.com addresses. SIGNUP_MODE stays
        # upstream's "open" — the domain gate is the whole of the policy, and it
        # costs no codes to distribute or rotate. Checked in POST
        # /v1/auth/register, after the per-address rate limit and before the
        # argon2 hash: a non-matching address gets a 403 with no account row and
        # no verification mail, so the SPA surfaces it as a failed registration
        # rather than an inbox that never fills. The value is comma-separated and
        # compared lowercased against the part after the LAST `@`, exact match
        # only — a subdomain is a different domain — and unset (upstream's
        # default) means anybody, so widening this list is how more people get in.
        #
        # This gates REGISTRATION and nothing else. Accounts that already exist,
        # including any on another domain from the window when this was open, log
        # in, reset passwords and run backtests exactly as before; the gate is not
        # retroactive and does not evict anyone. When `prod` launches it is a
        # separate instance with its own environment and inherits none of this.
        #
        # An administrator can move `signup_mode` (open/invite/closed) from the
        # panel at runtime, but NOT this list: upstream treats an allow-list as
        # configuration rather than an operational lever, so both widening and
        # narrowing it are a rebuild.
        #
        # It is the outer of two locks, not a replacement for the inner one. What
        # is actually worth withholding is a venue connection, and that stays
        # `connect_brokers` — an entitlement `free` does not hold, refused with a
        # 403 at POST /v1/brokers before any credential reaches the network (and
        # FUGAZI_SERVICE_SECRET_KEY is still unwired besides, so a broker connect
        # 503s instance-wide). The domain gate decides who gets an account; the
        # tier ceilings below decide what an account may spend.
        #
        # Registration is not an open mail relay either: upstream budgets it at
        # 5/hour keyed on BOTH the source address and the target inbox, so neither
        # one attacker nor one victim's inbox can be spent past that. See
        # trustedProxies above for why that keying works behind Cloudflare.
        #
        # Worth knowing before handing anyone the link: fugazitrade.com's MX is a
        # registrar forwarder, not this host's Postfix, so an address only
        # receives its verification mail if a forwarder exists for it — and
        # requireVerifiedEmail is on (the module default), so a token is refused
        # at login until it is redeemed.
        FUGAZI_SERVICE_SIGNUP_ALLOWED_EMAIL_DOMAINS = "fugazitrade.com";

        # That leaves compute and disk, which is what everything below bounds.

        # The instance's own account goes on the `testing` TIER — which, awkwardly,
        # is now also the name of the instance and has nothing to do with it. The
        # tier is upstream's; the instance name is ours. Non-public means exactly
        # one thing here: the tier is never *named* to a user, so an
        # entitlement refusal cannot invite a stranger onto a plan nobody can
        # buy. Its ceilings are `unlimited`'s (none), so this is not a widening
        # over what it had; what it adds is the venue gates. `connect_okx` is
        # held by `testing` and by nothing on sale, because how far a venue's
        # live path has been exercised here is a different claim from what this
        # plan costs, and only the second is `unlimited`'s to make.
        #
        # Keyed on the username, matched case-insensitively, and deliberately the
        # *override* channel rather than the `users.tier` column: upstream
        # deleted the revision that wrote that column precisely because who is on
        # an internal tier is a property of this instance, not of the service —
        # the same handle belongs to a stranger on somebody else's deployment.
        # Configuration outranks the column, so this line is the whole of the
        # assignment and no migration is involved.
        #
        # Either way the HARD_* bounds that keep one request from exhausting the
        # process still apply, to this account as to every other.
        FUGAZI_SERVICE_TIER_ASSIGNMENTS = "fugazi:testing";

        # The same account is this instance's administrator: `/admin` in the SPA,
        # and `/v1/admin` behind it. Keyed on the USERNAME like the assignment
        # above, comma-separated, lowercased with a leading `@` stripped — so it
        # is the handle `fugazi`, not an address.
        #
        # This variable GRANTS AND NEVER REVOKES, which is where it differs from
        # TIER_ASSIGNMENTS. It is a union with the `is_admin` column rather than
        # the authority over it, because it names a *set*: treating it as
        # authoritative would silently demote, on the next restart, everyone
        # promoted through the panel. Nothing is written to the database by
        # setting it — the role appears on the next start and disappears if this
        # line goes, and the panel refuses to demote a name listed here on the
        # grounds that clearing the column would change nothing. It is how the
        # first administrator exists on a database that has none; after that the
        # panel is how the role moves.
        #
        # What it unlocks is the five controls that must not wait for a rebuild —
        # maintenance_mode, disabled_features, signup_mode, trading_halted,
        # max_concurrent_evaluations — plus the user and report queues. An
        # override set there OUTRANKS this file, deliberately: the panel is the
        # escape hatch, and one a deploy could silently overrule would be useless
        # for the incident it exists for. So if signup or maintenance stops
        # matching what is written here, look at /admin before looking at git.
        #
        # Note the domain gate above is NOT one of the five: `signup_mode` can be
        # moved from the panel, the allow-list cannot.
        #
        # An API key is refused at /v1/admin even with write scope — the account's
        # own key would otherwise be a way to do at one remove what the key is not
        # allowed to do directly. Administration is a session, in a browser.
        FUGAZI_SERVICE_ADMINS = "fugazi";

        # --- ceilings on the process, shared by everybody ------------------
        # A backtest is an OS process holding a multi-megabyte bar array, and the
        # pool defaults to one worker per core — 16 here, on a box that is also
        # running bitcoind, Jellyfin, Nextcloud, Postgres and the agents. 4 is the
        # same call already made for Nix builds in settings.nix, for the same
        # reason: this host's job is to stay responsive, not to finish one sweep
        # first.
        FUGAZI_SERVICE_MAX_WORKERS = "4";
        # Admission control in front of that pool. Unset (0) means an unbounded
        # queue, which does not degrade gracefully — it swaps, and every in-flight
        # run gets slower together. Twice the pool leaves a little queue depth;
        # past it callers get a 503 + Retry-After, which is the honest answer.
        FUGAZI_SERVICE_MAX_CONCURRENT_EVALUATIONS = "8";
        # The largest archive this instance accepts, and the two knobs that have
        # to agree about it. Both are pinned rather than left at upstream's
        # defaults so that modules/fugazi-web's edge cap (maxRequestBodySize,
        # 65 MiB = this plus a megabyte of multipart headroom) has something
        # stable to track. `pro` is named here for the same reason and not
        # because anyone is on it: the backend derives its transport ceiling from
        # the HIGHEST finite tier cap, and pro ships at 256 MiB — a size no
        # request could ever reach through Caddy, and one that would have the ASGI
        # middleware read a quarter-gigabyte before the parser refused it.
        FUGAZI_SERVICE_MAX_UPLOAD_BYTES = toString (64 * 1024 * 1024);
        FUGAZI_SERVICE_TIER_PRO_MAX_UPLOAD_BYTES = toString (64 * 1024 * 1024);

        # --- the `free` tier, which is what a stranger gets ----------------
        # Everything not named here stays at upstream's `free` value, which is
        # deliberately the constant the service shipped with — the sweep-shape
        # limits (200 grid points, 10 grids, 10 axes, 100 values) are already
        # sized for the smallest plausible account and need no help from us.
        #
        # This one is not a tightening but a gap: upstream leaves free's
        # concurrency deliberately absent rather than inventing a number that
        # would break existing instances on upgrade. Absent is fine single-tenant
        # and wrong the moment signup is open — without it one account can hold
        # all 8 slots above and everyone else gets 503s. At 2 it takes four
        # distinct accounts to fill the queue.
        FUGAZI_SERVICE_TIER_FREE_MAX_CONCURRENT_EVALUATIONS = "2";
        # Uploaded datasets are the only thing a stranger leaves on the disk that
        # outlives their request, and there is no per-account storage quota
        # anywhere in the knob surface — the archive caps ARE the disk policy.
        # Quartered from free's 64 MiB/512 MiB/128 MiB accordingly. Rows come down
        # with them to stay proportionate; series stays at free's 500, being a
        # count rather than a volume.
        FUGAZI_SERVICE_TIER_FREE_MAX_UPLOAD_BYTES = toString (16 * 1024 * 1024);
        FUGAZI_SERVICE_TIER_FREE_MAX_UNCOMPRESSED_BYTES = toString (128 * 1024 * 1024);
        FUGAZI_SERVICE_TIER_FREE_MAX_MEMBER_BYTES = toString (32 * 1024 * 1024);
        FUGAZI_SERVICE_TIER_FREE_MAX_ROWS_TOTAL = "2000000";
        # NB none of these may be "0" — in the tier namespace 0 means *no ceiling*
        # (it means "off" only for an entitlement), so a zero here would quietly
        # do the opposite of what it reads like.
      };

      # fugazi-web is a PRIVATE GitHub repo, pulled in as the `fugazi-web` flake
      # input — a tarball URL, so Nix's ordinary downloader fetches it and
      # authenticates via netrc (a `github:` input would go through
      # api.github.com + access-tokens and ignore netrc; see the module header).
      # Point nix at a sops-rendered netrc carrying a GitHub PAT (github/token →
      # nix/netrc template in sops.nix).
      # Your shell's $GITHUB_TOKEN can't help — the fetch has no login environment.
      # Flake-input fetching is CLIENT-side, so the template is root:wheel 0440 and
      # `nix flake update fugazi-web` / `nix eval .#nixosConfigurations.homeserver`
      # work as alex. With a root-only 0400 both 404 — the tarball URL tracks
      # refs/heads/main, so it is unpinned by flake.lock and refetches on eval.
      # BOOTSTRAP: this template only exists after the first switch activates, so
      # seed /etc/nix/netrc by hand once before that switch.
      # A single github.com entry is enough — GitHub 302-redirects the archive to
      # codeload.github.com with a signed `?token=` in the URL, so that leg needs
      # no netrc of its own:
      #   printf 'machine github.com\n  login x-access-token\n  password ghp_…\n' \
      #     | sudo tee /etc/nix/netrc >/dev/null && sudo chmod 0400 /etc/nix/netrc
      # (the running daemon still reads the default /etc/nix/netrc at that point).
      # After the switch, netrc-file points here and every later rebuild is unattended.
      nix.settings.netrc-file = config.sops.templates."nix/netrc".path;

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
        };
        email = {
          from = "noreply@acpuchades.com";
        };
        immich = {
          hostName = "photos.acpuchades.com";
          mediaLocation = "/srv/encrypted/immich";
          accelerationDevices = [ "/dev/dri/renderD128" ];
        };
        nextcloud = {
          hostName = "cloud.acpuchades.com";
          adminPasswordFile = config.sops.secrets."nextcloud/admin".path;
          maxUploadSize = "2G";
          phoneRegion = "ES";
          dataDir = "/srv/encrypted/nextcloud";
          allowedNetworks = privateNetworks;
          extraApps = [
            "bookmarks" "calendar" "contacts" "gpoddersync" "groupfolders"
            "news" "nextpod" "notes" "richdocuments" "tasks"
          ];
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

      my.gps-backend = {
        enable = true;
        hostName = "gps.acpuchades.com";
        email.from = "noreply@acpuchades.com";
        # Reverse-geocode positions with the self-hosted Nominatim (my.geocoding
        # below), over its loopback nginx port. Traccar turns fixes into
        # addresses without hitting the public OSM endpoint.
        geocoder.url = "http://127.0.0.1:${toString config.my.geocoding.port}/reverse";
      };

      # Nominatim. Kept LAN/WireGuard-only: a public geocoding endpoint is a
      # scraper magnet, and the only consumers here are Traccar and Home
      # Assistant. See the module header — enabling this creates an EMPTY
      # database; the Spain extract has to be imported by hand once.
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
      # openclawPatched workaround exists to paper over. A separate unstable pkgs
      # instance is imported with an openclaw-only insecure permit (openclaw is
      # marked knownVulnerabilities upstream); the predicate is version-agnostic
      # so it survives unstable's openclaw bumps without editing a version string.
      my.openclaw = {
        # SHARED across all agent instances — the one OpenClaw build they all run.
        package = (import nixpkgs-unstable {
          inherit (pkgs.stdenv.hostPlatform) system;
          config.allowInsecurePredicate = p: (pkgs.lib.getName p) == "openclaw";
        }).openclaw;

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
          config.my.cloud-suite.nextcloud.dataDir            # /srv/encrypted/nextcloud
          config.my.cloud-suite.bitwarden.dataDir            # /srv/encrypted/vaultwarden
          config.my.cloud-suite.immich.mediaLocation         # /srv/encrypted/immich
          "/srv/shared"                                      # Samba share (media/downloads excluded)
        ];

        # Keep the big, re-acquirable trees out of the off-site copy.
        exclude = [
          "/srv/shared/Media"
          "/srv/shared/Downloads"
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
              { name = "GPS Backend"; icon = "mdi-map-marker"; description = "Location tracking backend"; href = "https://${config.my.gps-backend.hostName}"; }
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
        # (they fail visibly at deploy time, not in steady state).
        failureUnits = [
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
          "ddclient"
          "openclaw-eva"
          "bitcoind-main"
          "upsd"
          "upsmon"
        ];
      };


      my.prefect-server = {
        enable = true;
        host = "0.0.0.0";
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
  modules = [

    ../../modules/r-dev/system.nix
    (import ../../modules/emacs-core/system.nix { inherit emacs-overlay; })

    configuration
    sops-nix.nixosModules.sops
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.alex = import ../../users/alex;
      home-manager.extraSpecialArgs = { host = "homeserver"; };
      home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];

      users.users.alex.home = "/home/alex";
    }
  ];
}
