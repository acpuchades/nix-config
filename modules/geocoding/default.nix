{ config, lib, pkgs, ... }:

#
# geocoding — self-hosted OpenStreetMap geocoding / reverse geocoding
# (Nominatim).
#
# Wraps the upstream `services.nominatim` module with:
#   - the nginx-behind-Caddy pattern already used for NextCloud in
#     ../cloud-suite. The upstream module hardcodes an nginx vhost with
#     `enableACME` and `forceSSL`, which would fight Caddy for :443. Both are
#     plain `lib.mkDefault` upstream, so a plain `false` here is enough to
#     override them (unlike NextCloud, which needs `lib.mkForce`). nginx is
#     pinned to a loopback port and Caddy terminates TLS in front.
#   - a replication timer. Upstream carries a literal
#     `# TODO: add nominatim-update service`, so without this the database is
#     frozen at whatever the initial import contained.
#   - the usual `allowedNetworks` CIDR restriction used by the other services
#     on this host.
#
# Nominatim shares the host PostgreSQL cluster (see ../postgresql-server),
# which also backs NextCloud, Traccar, Prefect, Umami and Immich. The initial
# import is extremely write-heavy — expect those services to be sluggish while
# it runs, and prefer to kick it off when the host is otherwise idle.
#
# `tablespace` exists because that cluster lives on /srv/encrypted, which is a
# 5.5 TB spinning disk behind LUKS on btrfs. Nominatim is almost entirely
# random index reads, and a spinner serves ~100-200 random IOPS against the
# NVMe's ~100k. RAM normally hides this — the docs' "128 GB for a planet
# import" is really "enough page cache that the disk stops mattering" — but the
# honest fix on this host is to put the database on the NVMe instead, where a
# country extract fits with room to spare. Sizing rule of thumb, extrapolated
# from the upstream planet figures (87 GB PBF -> >=1 TB on disk): budget around
# 12x the extract's PBF size, and rather more for densely-mapped regions.
#
# This is sized for a country/region extract. A continent import would exceed
# both the NVMe and any plausible page cache here, so it is not practical on
# this hardware regardless of the free space on /srv.
#
# IMPORTANT: enabling this module does NOT import any map data. The upstream
# `nominatim-init` unit only runs `import --prepare-database`, which creates an
# empty PostGIS database. The initial import is a manual one-off:
#
#   # 1. Fetch an extract (Geofabrik mirrors OSM by region):
#   curl -LO https://download.geofabrik.de/europe/spain-latest.osm.pbf
#
#   # 2. Import it. Takes hours for a country extract; run it under tmux.
#   #    Peer auth over the Unix socket means no password is needed — the
#   #    `nominatim` role is a superuser created by the upstream module.
#   #
#   #    Use `nominatim-admin`, NOT `nominatim`: the wrapper carries the
#   #    tablespace and replication settings that the systemd units get. A bare
#   #    `nominatim import` writes to the default tablespace on the slow disk.
#   sudo -u nominatim nominatim-admin import --osm-file spain-latest.osm.pbf
#
#   # 3. Initialise replication state, so the timer below has a starting point:
#   sudo -u nominatim nominatim-admin replication --init
#
# Until step 2 completes, the API answers but returns no results.
#

let
  cfg = config.my.geocoding;

  # Nominatim splits its storage across five table groups, each with a separate
  # data and index tablespace setting. Pointing all ten at one tablespace moves
  # the whole database; there is no benefit in splitting them here, since the
  # goal is simply "not on the spinning disk".
  tablespaceSettings = lib.optionalAttrs cfg.tablespace.enable (
    lib.listToAttrs (
      map (n: lib.nameValuePair "NOMINATIM_TABLESPACE_${n}" cfg.tablespace.name) [
        "SEARCH_DATA"  "SEARCH_INDEX"
        "OSM_DATA"     "OSM_INDEX"
        "PLACE_DATA"   "PLACE_INDEX"
        "ADDRESS_DATA" "ADDRESS_INDEX"
        "AUX_DATA"     "AUX_INDEX"
      ]
    )
  );

  replicationSettings = lib.optionalAttrs cfg.updates.enable {
    NOMINATIM_REPLICATION_URL = cfg.updates.replicationUrl;
  };

  nominatimSettings = tablespaceSettings // replicationSettings;

  # Upstream `pkgs.nominatim` ships without pyosmium — Nominatim declares it as
  # the optional `[replication]` extra, so the CLI's `replication` subcommand
  # aborts with "pyosmium not installed. Replication functions not available."
  # and the daily nominatim-update unit fails on every run (the DB then freezes
  # at whatever the initial import contained). Add it back so replication works
  # for both the manual `--init` (via nominatim-admin) and the periodic `--once`
  # (nominatim-update). pyosmium comes from the same python3Packages set the
  # package is built with, so the interpreter versions match.
  nominatimPkg = pkgs.nominatim.overridePythonAttrs (old: {
    dependencies = (old.dependencies or []) ++ [ pkgs.python3Packages.pyosmium ];
  });

  # The settings above only reach the systemd units. The initial import is run
  # by hand, and a bare `nominatim import` would inherit none of them — sending
  # the whole database to the default tablespace on the spinning disk, silently,
  # and only discoverably several hours later. This wrapper carries the same
  # environment the units use, so the manual step cannot drift from the
  # declarative config.
  nominatim-admin = pkgs.writeShellScriptBin "nominatim-admin" ''
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (n: v: "export ${n}=${lib.escapeShellArg v}") (
        nominatimSettings
        // {
          NOMINATIM_DATABASE_DSN =
            "pgsql:dbname=${config.services.nominatim.database.dbname};"
            + "user=${config.services.nominatim.database.superUser}";
          NOMINATIM_DATABASE_WEBUSER = config.services.nominatim.database.apiUser;
        }
      )
    )}
    exec ${lib.getExe nominatimPkg} "$@"
  '';
in
{
  options.my.geocoding = {
    enable = lib.mkEnableOption "Self-hosted OSM geocoding (Nominatim)";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for the Nominatim API and web UI";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = ''
        Port for the module's own nginx vhost, bound to loopback and fronted
        by Caddy. Not the Nominatim API itself, which upstream only exposes
        over a Unix socket at /run/nominatim.sock.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Restrict access to these CIDR ranges (empty = unrestricted). A public
        Nominatim instance attracts scrapers, so prefer to keep this closed
        unless something off-LAN genuinely needs to geocode.
      '';
    };

    ui.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Serve the nominatim-ui search front-end at /ui/";
    };

    tablespace = {
      enable = lib.mkEnableOption "dedicated PostgreSQL tablespace on fast storage";

      name = lib.mkOption {
        type = lib.types.str;
        default = "nominatim";
        description = "Name of the PostgreSQL tablespace to create and use.";
      };

      location = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nominatim-tablespace";
        description = ''
          Directory backing the tablespace. Must be on a filesystem PostgreSQL
          can own exclusively; it is created 0700 postgres:postgres and must be
          empty when the tablespace is first created.

          The default lives under /var/lib, which on this host is the ext4 NVMe
          root rather than the spinning btrfs volume holding the rest of the
          cluster — which is the entire point of this option. Nominatim's
          workload is dominated by random index reads, and the two disks differ
          by roughly three orders of magnitude in random IOPS.

          Watch the free space on that filesystem: if it fills, PostgreSQL
          fails writes for every table in this tablespace. Note also that a
          tablespace adds a symlink under pg_tblspc, which backup and
          pg_upgrade tooling has to be aware of.
        '';
      };
    };

    updates = {
      enable = lib.mkEnableOption "periodic OSM replication updates" // {
        default = false;
      };

      replicationUrl = lib.mkOption {
        type = lib.types.str;
        example = "https://download.geofabrik.de/europe/spain-updates/";
        description = ''
          Replication feed matching the extract that was imported. Geofabrik
          publishes a `<region>-updates/` feed alongside each extract; using a
          feed that does not match the imported region corrupts the database.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd calendar expression for the update timer";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ nominatim-admin ];

    services.nominatim = {
      enable = true;
      inherit (cfg) hostName;
      ui.enable = cfg.ui.enable;
      settings = nominatimSettings;
    };

    # PostgreSQL requires the tablespace directory to exist, be empty on first
    # use, and be owned 0700 by the cluster's OS user.
    systemd.tmpfiles.rules = lib.mkIf cfg.tablespace.enable [
      "d ${cfg.tablespace.location} 0700 postgres postgres -"
    ];

    # The postgresql unit runs ProtectSystem=strict with only its dataDir in
    # ReadWritePaths, so a tablespace living anywhere else is read-only to the
    # server — CREATE TABLESPACE then fails with "Read-only file system". Grant
    # the server write access to the location. (systemd list-valued serviceConfig
    # options concatenate across modules, so this merges with the dataDir entry.)
    systemd.services.postgresql.serviceConfig.ReadWritePaths =
      lib.mkIf cfg.tablespace.enable [ cfg.tablespace.location ];

    # NixOS has no declarative tablespace equivalent to `ensureDatabases`, so
    # create it here — before nominatim-init runs `import --prepare-database`,
    # which is the first thing that would reference it.
    systemd.services.nominatim-tablespace = lib.mkIf cfg.tablespace.enable {
      description = "Create the PostgreSQL tablespace backing Nominatim";
      after = [ "postgresql-setup.service" ];
      requires = [ "postgresql-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        RemainAfterExit = true;
      };
      script = ''
        exists=$(psql --dbname postgres -tAc \
          "SELECT COUNT(*) FROM pg_tablespace WHERE spcname='${cfg.tablespace.name}'")

        if [ "$exists" = "0" ]; then
          psql --dbname postgres -c \
            "CREATE TABLESPACE ${cfg.tablespace.name} LOCATION '${cfg.tablespace.location}'"
        else
          echo "Tablespace ${cfg.tablespace.name} already exists. Skipping ..."
        fi
      '';
      path = [ config.services.postgresql.package ];
    };

    # Merged into the upstream unit's existing ordering, so the tablespace is
    # guaranteed to exist before the database that uses it is prepared.
    systemd.services.nominatim-init = lib.mkIf cfg.tablespace.enable {
      after = [ "nominatim-tablespace.service" ];
      requires = [ "nominatim-tablespace.service" ];
    };

    # Pin the upstream nginx vhost to loopback and hand TLS to Caddy. Both
    # forceSSL and enableACME are lib.mkDefault upstream, so plain values win.
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
    };

    services.nginx.virtualHosts."${cfg.hostName}" = {
      listen = [{ addr = "127.0.0.1"; port = cfg.port; ssl = false; }];
      forceSSL = false;
      enableACME = false;

      # Upstream redirects `/` to the UI with `return 301 $scheme://$http_host/...`.
      # Behind Caddy nginx only ever sees plain HTTP, so $scheme would emit an
      # http:// Location and cost a second round trip through Caddy's
      # http->https redirect. This vhost is only ever reached over TLS, so
      # hardcoding the scheme is both correct and cheaper. mkForce because
      # upstream sets this location's extraConfig unconditionally.
      locations."= /".extraConfig = lib.mkForce (
        lib.optionalString cfg.ui.enable
          "return 301 https://$http_host/ui/search.html;"
      );
    };

    services.caddy.virtualHosts."${cfg.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
        "reverse_proxy http://127.0.0.1:${toString cfg.port}"
        "encode gzip"
      ]);

    # The replication timer upstream leaves as a TODO. `--once` applies every
    # diff published since the last run and exits, so the timer controls the
    # cadence rather than a long-lived daemon loop. Requires
    # `nominatim replication --init`
    # to have been run once (see the header comment) — until then the unit
    # fails, which is the intended loud signal rather than silent staleness.
    systemd.services.nominatim-update = lib.mkIf cfg.updates.enable {
      description = "Apply OSM replication updates to the Nominatim database";
      after = [ "postgresql.service" "nominatim-init.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.nominatim.database.superUser;
        # Imports touch large temporary indexes; give them a real /tmp.
        PrivateTmp = true;
        ExecStart = "${lib.getExe nominatimPkg} replication --once";
      };
      environment = {
        NOMINATIM_DATABASE_DSN =
          "pgsql:dbname=${config.services.nominatim.database.dbname};"
          + "user=${config.services.nominatim.database.superUser}";
        NOMINATIM_DATABASE_WEBUSER = config.services.nominatim.database.apiUser;
      }
      // nominatimSettings;
    };

    systemd.timers.nominatim-update = lib.mkIf cfg.updates.enable {
      description = "Periodic OSM replication updates for Nominatim";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updates.interval;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
