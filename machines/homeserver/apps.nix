# User-facing applications: the cloud suite (Nextcloud, Collabora, Vaultwarden,
# Immich) on PostgreSQL, file/media/print sharing, geocoding, Home Assistant,
# web analytics and Prefect. Almost all LAN/VPN-only (privateNetworks).
{
  config,
  pkgs,
  pkgsUnstable,
  adminEmailAddress,
  ...
}:

let
  inherit (import ./networks.nix) privateNetworks;
in
{
  imports = [
    ../../modules/postgresql-server
    ../../modules/cloud-suite
    ../../modules/samba-server
    ../../modules/media-server
    ../../modules/print-server
    ../../modules/geocoding
    ../../modules/home-assistant
    ../../modules/web-analytics
    ../../modules/prefect-server
  ];

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
      package = pkgs.nextcloud34;
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
        "bookmarks"
        "calendar"
        "contacts"
        "gpoddersync"
        "groupfolders"
        "guests"
        "news"
        "nextpod"
        "notes"
        "richdocuments"
        "tasks"
        "twofactor_webauthn"
      ];
      # Probes status.php every 15 min; nextcloud-health is wired into
      # my.ntfy-alert.failureUnits (./monitoring.nix), closing the gap where a dead
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
    libraries = [
      "Movies"
      "Shows"
      "Music"
    ];
    shareGroup = "share";
    # Internal hosts only — nginx restricts the vhost to the LAN/VPN subnets.
    allowedNetworks = privateNetworks;
    # TV/mobile apps talk straight to :8096; drop this if every client moves
    # to the vhost.
    allowedDirectNetworks = privateNetworks;
    # Same GPU render node Immich uses; enable the codecs in Jellyfin's UI.
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };

  my.print-server = {
    enable = true;
    allowedNetworks = privateNetworks;
    # Driverless printers (IPP Everywhere / AirPrint) need no driver package.
    drivers = [ ];
    # Network printer at 192.168.2.3, driverless (IPP Everywhere). model =
    # "everywhere" derives the PPD by querying the device, so the printer must
    # be reachable at `nixos-rebuild switch` time. Print to it with
    # `lp -d HomePrinter <file>`.
    defaultPrinter = "HomePrinter";
    printers = [
      {
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
      }
    ];
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
      # Geofabrik blocks the server's direct IP; route nominatim's egress
      # through the Spain ProtonVPN exit (table 42 = proton-es).
      viaTunnel = 42;
    };
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

  my.web-analytics = {
    enable = true;
    hostName = "analytics.acpuchades.com";
    appSecretFile = config.sops.secrets."umami/app-secret".path;
  };

  my.prefect-server = {
    enable = true;
    # Loopback only: the Prefect API has NO authentication, and it can run
    # arbitrary code as the prefect user (deployments/flow runs). The nginx
    # vhost (basic-auth) is the only intended way in; the local workers
    # already target 127.0.0.1:4200 directly.
    host = "127.0.0.1";
    port = 4200;
    dataDir = "/srv/prefect";
    baseUrl = "https://prefect.acpuchades.com";
    virtualHost = "prefect.acpuchades.com";
    basicAuthFile = config.sops.templates."nginx/prefect-htpasswd".path;
    # Not in public DNS, but the name is in CT logs and the vhost answered
    # from the internet; every client reaches it over LAN or VPN anyway.
    allowedNetworks = privateNetworks;
    workerPools.default.installPolicy = "if-not-present";
  };
}
