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
  ...
}:

let

  homeServerLocalAddress = "192.168.2.2";
  adminEmailAddress = "admin@acpuchades.com";
  privateNetworks = [ "192.168.2.0/24" "10.0.0.0/24" ];

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
        ../../modules/host-security
        ../../modules/ups-monitor
        ../../modules/backup
        ../../modules/ntfy-alert
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

      my.mail-server = {
        enable = true;
        hostname = "mail.acpuchades.com";
        origin = "acpuchades.com";
        # Public identity e.lebbot@acpuchades.com is a Cloudflare Email Routing
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
        acmeEnvironmentFile = config.sops.templates."acme/cloudflare-env".path;
      };

      # Encrypted off-site backups to Backblaze B2 (restic, client-side AES-256).
      # Covers the irreplaceable, non-declarative state: DB dumps, eva's home +
      # agent state, and the cloud-suite data dirs. Deliberately EXCLUDES the
      # large/reproducible sets — Bitcoin chainstate, the Nominatim DB, and the
      # Samba media/downloads — so the off-site copy stays small and cheap.
      # Repo password + B2 credentials come from sops (backup/* below).
      my.backup = {
        enable = true;
        repository = "b2:acpuchades-homeserver-restic:restic";
        passwordFile = config.sops.secrets."backup/restic-password".path;
        environmentFile = config.sops.templates."backup/b2-env".path;

        # Data-directory paths tracked off their owning modules' options so they
        # follow any relocation. eva's /home covers her Maildir too.
        paths = [
          "/home/eva"                                        # eva home + Maildir
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
          "/home/eva/.cache"
          "/var/lib/hass/*.log*"
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
