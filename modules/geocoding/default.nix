{
  config,
  lib,
  pkgs,
  ...
}:

#
# geocoding — self-hosted OpenStreetMap geocoding / reverse geocoding
# (Nominatim).
#
# Wraps the upstream `services.nominatim` module with:
#   - upstream's own nginx vhost served as the public one: nginx is this
#     host's edge (../web-server), so the vhost only trades upstream's
#     per-host `enableACME` for the zone wildcard and gains the LAN gate.
#   - a replication timer. Upstream carries a literal
#     `# TODO: add nominatim-update service`, so without this the database is
#     frozen at whatever the initial import contained.
#   - the usual `allowedNetworks` CIDR restriction used by the other services
#     on this host.
#
# Nominatim shares the host PostgreSQL cluster (see ../postgresql-server),
# which also backs NextCloud, Prefect, Umami and Immich. The initial import is
# extremely write-heavy — expect those services to be sluggish while it runs,
# and prefer to kick it off when the host is otherwise idle.
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
        "SEARCH_DATA"
        "SEARCH_INDEX"
        "OSM_DATA"
        "OSM_INDEX"
        "PLACE_DATA"
        "PLACE_INDEX"
        "ADDRESS_DATA"
        "ADDRESS_INDEX"
        "AUX_DATA"
        "AUX_INDEX"
      ]
    )
  );

  replicationSettings = lib.optionalAttrs cfg.updates.enable {
    NOMINATIM_REPLICATION_URL = cfg.updates.replicationUrl;
    NOMINATIM_REPLICATION_UPDATE_INTERVAL = toString cfg.updates.publishInterval;
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
    dependencies = (old.dependencies or [ ]) ++ [ pkgs.python3Packages.pyosmium ];
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

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
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

      publishInterval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          How often the replication feed publishes a new diff, in seconds.
          Nominatim refuses to poll faster than the feed advertises, so this
          has to match it: Geofabrik publishes daily (86400), planet.osm
          minute-diffs every 60.

          Nominatim's packaged default is 75, which suits the planet feed it
          also defaults to. Against a Geofabrik feed that aborts every single
          run with "Update interval too low for download.geofabrik.de" —
          silently freezing the database at whatever the last import held,
          because the only symptom is a failed timer unit.
        '';
      };

      viaTunnel = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          When set, route nominatim replication traffic through this VPN
          routing table using uid-based policy routing for the nominatim
          user. Needed when the replication host blocks the server's
          direct IP address (Geofabrik blocks many datacenter IPs).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ nominatim-admin ];

    services.nominatim = {
      enable = true;
      inherit (cfg) hostName;
      settings = nominatimSettings;

      ui.enable = cfg.ui.enable;

      # With customConfig null, nixpkgs' nominatim-ui bakes a placeholder
      # endpoint into theme/config.theme.js:
      #
      #   Nominatim_Config.Nominatim_API_Endpoint='https://127.0.0.1/';
      #
      # That address is resolved by the *browser*, not the server, so the UI
      # loads from this host and then tries to fetch results from whatever is
      # on the visitor's own machine at port 443 — failing with a bare
      # "NetworkError when attempting to fetch resource" that says nothing
      # about the endpoint being the cause. The API and the UI share one
      # vhost (upstream proxies `/` to the API and serves the UI under
      # `/ui/`), so the public hostname is the right value.
      ui.config = ''
        Nominatim_Config.Nominatim_API_Endpoint='https://${cfg.hostName}/';
      '';
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
    systemd.services.postgresql.serviceConfig.ReadWritePaths = lib.mkIf cfg.tablespace.enable [
      cfg.tablespace.location
    ];

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

    # Upstream's vhost, served directly. enableACME is a plain lib.mkDefault
    # upstream; it has to go because it is mutually exclusive with the
    # wildcard's useACMEHost.
    services.nginx.virtualHosts.${cfg.hostName} = {
      enableACME = false;
      inherit (cfg) allowedNetworks;
    };

    # Route the nominatim user's egress through the specified VPN table.
    # Geofabrik blocks many datacenter IPs; routing via a residential VPN exit
    # (ProtonVPN Spain) works around this. The rule is added after
    # protonvpn-policy so the table exists, and swept alongside it on restart
    # via partOf — nominatim-route restarts too, re-adding the rule cleanly.
    systemd.services.nominatim-route = lib.mkIf (cfg.updates.enable && cfg.updates.viaTunnel != null) {
      description = "Policy routing: nominatim replication via VPN table ${toString cfg.updates.viaTunnel}";
      after = [ "protonvpn-policy.service" ];
      partOf = [ "protonvpn-policy.service" ];
      wantedBy = [ "protonvpn-policy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = toString (
          pkgs.writeShellScript "nominatim-route-start" ''
            uid="$(${pkgs.coreutils}/bin/id -u nominatim)"
            ${pkgs.iproute2}/bin/ip rule add uidrange "$uid-$uid" \
              lookup ${toString cfg.updates.viaTunnel} priority 1003
          ''
        );
        ExecStop = toString (
          pkgs.writeShellScript "nominatim-route-stop" ''
            uid="$(${pkgs.coreutils}/bin/id -u nominatim 2>/dev/null)" || exit 0
            ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" \
              lookup ${toString cfg.updates.viaTunnel} priority 1003 2>/dev/null || true
          ''
        );
      };
    };

    # The replication timer upstream leaves as a TODO. `--once` applies every
    # diff published since the last run and exits, so the timer controls the
    # cadence rather than a long-lived daemon loop. Requires
    # `nominatim replication --init`
    # to have been run once (see the header comment) — until then the unit
    # fails, which is the intended loud signal rather than silent staleness.
    systemd.services.nominatim-update = lib.mkIf cfg.updates.enable {
      description = "Apply OSM replication updates to the Nominatim database";
      after = [
        "postgresql.service"
        "nominatim-init.service"
      ]
      ++ lib.optionals (cfg.updates.viaTunnel != null) [ "nominatim-route.service" ];
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
