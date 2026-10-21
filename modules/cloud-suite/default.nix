{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.my.cloud-suite = {
    enable = lib.mkEnableOption "Personal cloud suite (NextCloud + Collabora + Bitwarden + Immich)";

    nextcloud = {
      # The NextCloud build. Exposed as an option because major upgrades are
      # SEQUENTIAL — Nextcloud refuses to skip a major, so the host has to be
      # able to say which major it is currently on and step it one at a time
      # (33 -> 34 -> ...) as its data directory migrates.
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.nextcloud33;
        defaultText = lib.literalExpression "pkgs.nextcloud33";
        description = "NextCloud package (also the source of extraApps)";
      };

      hostName = lib.mkOption {
        type = lib.types.str;
        description = "NextCloud hostname";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to admin password file";
      };

      maxUploadSize = lib.mkOption {
        type = lib.types.str;
        default = "2G";
        description = "Maximum upload size";
      };

      phoneRegion = lib.mkOption {
        type = lib.types.str;
        default = "ES";
        description = "Default phone region";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nextcloud";
        description = "NextCloud data directory (user files and config.php)";
      };

      allowedNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };

      extraApps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "calendar"
          "contacts"
          "notes"
          "richdocuments"
          "tasks"
        ];
        description = "Extra NextCloud apps to install from the appstore";
      };

      maintenanceWindowStart = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 0 23);
        default = 1;
        description = ''
          Hour (UTC, 0-23) at which the 4-hour maintenance window starts.
          Heavy background jobs (e.g. preview pre-generation, database
          optimization) only run during this window. Set to null to disable
          (every cron run will then attempt these jobs).
        '';
      };

      healthCheck = {
        enable = lib.mkEnableOption ''
          a periodic HTTP probe of status.php. Exists because unit state is a
          liar here: a Nextcloud dead from a broken stateful config.php (e.g.
          a GC'd apps_paths entry) keeps phpfpm-nextcloud and nextcloud-cron
          green — only an actual HTTP request notices. Wire the
          nextcloud-health unit into my.ntfy-alert.failureUnits to get paged
        '';

        interval = lib.mkOption {
          type = lib.types.str;
          default = "*:0/15";
          description = "OnCalendar expression for how often to probe";
        };
      };
    };

    collabora = {
      hostName = lib.mkOption {
        type = lib.types.str;
        description = "Collabora hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9980;
        description = "Collabora port";
      };

      allowedNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };
    };

    immich = {
      hostName = lib.mkOption {
        type = lib.types.str;
        description = "Immich hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 2283;
        description = "Immich listen port";
      };

      allowedNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };

      maxUploadSize = lib.mkOption {
        type = lib.types.str;
        default = "50G";
        description = "Maximum upload size";
      };

      uploadTimeout = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "Read/send timeout for Immich uploads through nginx (nginx time syntax)";
      };

      cacheLocation = lib.mkOption {
        type = lib.types.str;
        default = "/var/cache/immich";
        description = "Immich cache storage directory";
      };

      mediaLocation = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/immich";
        description = "Immich media storage directory";
      };

      accelerationDevices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "GPU/render devices for hardware acceleration (e.g. [ \"/dev/dri/renderD128\" ])";
      };

      # The Immich build. Exposed as an option because nixpkgs' stable branch
      # freezes Immich at a release that upstream stops patching mid-cycle (2.x
      # was marked insecure on 26.05 with no 3.x to move to), and the only way
      # out is a package from another channel. The NixOS module itself is
      # version-agnostic enough for that to work — nothing here is keyed on the
      # Immich version.
      #
      # Overriding this ALSO moves machine learning: the module takes the ML
      # binary from `package.machine-learning` (a passthru of the server
      # derivation), so the two halves cannot drift apart by construction.
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.immich;
        defaultText = lib.literalExpression "pkgs.immich";
        description = "Immich server package (its passthru also provides machine learning)";
      };
    };

    bitwarden = {
      hostName = lib.mkOption {
        type = lib.types.str;
        description = "Bitwarden hostname";
      };

      signupsAllowed = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow new user signups";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/vaultwarden";
        description = "Vaultwarden DATA_FOLDER (attachments, icons, sends)";
      };

      allowedNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };
    };

    email = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Sender email address for all cloud-suite services";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP server hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 25;
        description = "SMTP server port";
      };

      ssl = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SMTP SSL/TLS";
      };

      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SMTP authentication username (null disables auth)";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing SMTP authentication password";
      };
    };
  };

  config = lib.mkIf config.my.cloud-suite.enable (
    let
      emailParts = lib.splitString "@" config.my.cloud-suite.email.from;
      emailLocalPart = lib.elemAt emailParts 0;
      emailDomain = lib.elemAt emailParts 1;
      smtpAuth =
        config.my.cloud-suite.email.username != null && config.my.cloud-suite.email.passwordFile != null;
    in
    {

      # Postgres databases/users for cloud-suite services
      services.postgresql = {
        ensureDatabases = [ "vaultwarden" ];
        ensureUsers = [
          {
            name = "vaultwarden";
            ensureDBOwnership = true;
          }
        ];
      };

      systemd.services.immich-server.environment = {
        XDG_CACHE_HOME = "/var/cache/immich";
      };

      systemd.tmpfiles.rules = [
        "d ${config.my.cloud-suite.nextcloud.dataDir} 0750 nextcloud nextcloud -"
        "d ${config.my.cloud-suite.bitwarden.dataDir} 0700 vaultwarden vaultwarden -"
        "d ${config.my.cloud-suite.immich.cacheLocation} 0750 immich immich -"
        "d ${config.my.cloud-suite.immich.mediaLocation} 0750 immich immich -"
      ];

      # Order every unit after the filesystem holding the data dir it writes to.
      #
      # These dirs are options, so they may well sit on a separate disk (they all
      # do here). Without this a unit can start while that filesystem is still
      # mounting and operate on the empty stub directory *underneath* the
      # mountpoint — the tmpfiles rules above will even have created it. Two
      # distinct failure modes, depending on how the unit is sandboxed:
      #
      #   * With RootDirectory= (a constructed root), the sandbox sees only what
      #     was explicitly bound in, and the bind is a one-time snapshot: the real
      #     filesystem arriving later is invisible for the lifetime of the process.
      #   * Without it (the case here — vaultwarden et al. inherit the host mount
      #     tree), the real mount does propagate in and shadows the stale bind, so
      #     the path self-heals. What does NOT heal is whatever the unit wrote to
      #     the stub during the startup window; it is stranded on the parent
      #     filesystem, invisible under the mountpoint.
      #
      # systemd derives an implicit mount dependency only from RootDirectory=,
      # WorkingDirectory= and RootImage= — never from BindPaths=/ReadWritePaths=,
      # which is what vaultwarden's DATA_FOLDER exception below uses. So it has to
      # be declared. RequiresMountsFor takes a path and resolves it to whichever
      # mount unit actually provides it, so it stays correct if these options are
      # pointed somewhere else (and is a harmless no-op when they are on /).
      systemd.services.vaultwarden.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.bitwarden.dataDir
      ];

      systemd.services.immich-server.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.immich.mediaLocation
        config.my.cloud-suite.immich.cacheLocation
      ];

      systemd.services.immich-machine-learning.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.immich.cacheLocation
      ];

      systemd.services.nextcloud-setup.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.nextcloud.dataDir
      ];

      systemd.services.nextcloud-cron.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.nextcloud.dataDir
      ];

      systemd.services.phpfpm-nextcloud.unitConfig.RequiresMountsFor = [
        config.my.cloud-suite.nextcloud.dataDir
      ];

      # NextCloud
      services.nextcloud = {
        enable = true;
        hostName = config.my.cloud-suite.nextcloud.hostName;
        datadir = config.my.cloud-suite.nextcloud.dataDir;
        package = config.my.cloud-suite.nextcloud.package;
        database.createLocally = true;
        configureRedis = true;
        maxUploadSize = config.my.cloud-suite.nextcloud.maxUploadSize;
        https = true;
        config = {
          dbtype = "pgsql";
          adminuser = "admin";
          adminpassFile = config.my.cloud-suite.nextcloud.adminPasswordFile;
        };
        # Apps are pinned declaratively via extraApps (updated on nixpkgs bumps),
        # so the App Store is redundant and actively harmful: it pulls a second
        # copy of a declaratively-managed app into the mutable store-apps dir,
        # colliding with the /nix/store copy and killing occ upgrade on a
        # duplicate-class redeclare. Disabling autoUpdateApps alone was not
        # enough (it bit contacts, then richdocuments): `occ upgrade` runs its
        # own app-store update pass, gated on appstoreEnable rather than on the
        # auto-updater. That failure leaves maintenance mode latched on, so the
        # whole site stays down until the stray store-apps copy is removed by
        # hand. Cost of false: no in-UI app browser, so adding an app is an
        # extraApps edit plus a rebuild.
        #
        # Related trap, in the STATEFUL config.php this time (bit us 2026-09-19):
        # Nextcloud writes its merged in-memory config back to config.php on some
        # setValue paths, so the generated apps_paths entries get copied there and
        # ride along across upgrades — including a store path that GC later
        # removes. The 503 then appears when nix-collect-garbage runs, not when
        # the package is bumped, and occ cannot repair it because occ itself
        # refuses to start on the broken config. Fix by editing config.php
        # directly: delete the whole apps_paths key so override.config.php is its
        # only source. (trusted_domains being absent from config.php is fine — it
        # comes from the declarative settings via override.config.php.)
        appstoreEnable = false;
        autoUpdateApps.enable = false;
        extraApps = lib.genAttrs config.my.cloud-suite.nextcloud.extraApps (
          name: config.services.nextcloud.package.packages.apps.${name}
        );
        extraAppsEnable = true;
        phpOptions = {
          "opcache.interned_strings_buffer" = "32";
          "opcache.memory_consumption" = "256";
          "opcache.max_accelerated_files" = "10000";
          "opcache.revalidate_freq" = "1";
          "opcache.save_comments" = "1";
          "opcache.jit" = "tracing";
          "opcache.jit_buffer_size" = "128M";
        };
        secrets = lib.optionalAttrs smtpAuth {
          mail_smtppassword = config.my.cloud-suite.email.passwordFile;
        };
        settings = {
          overwriteprotocol = "https";
          default_phone_region = config.my.cloud-suite.nextcloud.phoneRegion;
          "integrity.check.disabled" = lib.mkForce false;
          mail_smtpmode = "smtp";
          mail_sendmailmode = "smtp";
          mail_from_address = emailLocalPart;
          mail_domain = emailDomain;
          mail_smtphost = config.my.cloud-suite.email.host;
          mail_smtpport = config.my.cloud-suite.email.port;
          mail_smtpsecure = if config.my.cloud-suite.email.ssl then "ssl" else "";
          mail_smtpauth = smtpAuth;
        }
        // lib.optionalAttrs smtpAuth {
          mail_smtpname = config.my.cloud-suite.email.username;
        }
        // lib.optionalAttrs (config.my.cloud-suite.nextcloud.maintenanceWindowStart != null) {
          maintenance_window_start = config.my.cloud-suite.nextcloud.maintenanceWindowStart;
        };

        # Client Push: the desktop/mobile clients hold a websocket to /push/
        # and are told when something changed, instead of re-PROPFINDing the
        # tree on a timer — changes land in seconds and the polling load goes.
        # Upstream wires the nginx location, the app and its self-test
        # (notify_push_setup). bendDomainToLocalhost points this host's own
        # lookups of the hostname at 127.0.0.1, which the self-test needs: the
        # push daemon and Nextcloud reach each other through nginx, and the
        # loopback address is what goes into trusted_proxies (and passes the
        # vhost's LAN gate).
        notify_push = {
          enable = true;
          bendDomainToLocalhost = true;
        };
      };

      # Every Nextcloud write is a handful of small transactions (filecache
      # row, parent etags, activity), and on this host each COMMIT waits for
      # an fsync on a spinning disk — which is most of what a sync of many
      # small files spends its time on. Asynchronous commit, for this one
      # database only, drops that wait; the trade is that a crash can lose
      # the last fraction of a second of metadata (never corrupt it), which
      # `nextcloud-occ files:scan --all` re-derives from the files on disk.
      # Everything else in the cluster (fugazi in particular) keeps durable
      # commits.
      systemd.services.nextcloud-db-async-commit = {
        description = "Asynchronous commit for the Nextcloud database";
        after = [ "postgresql-setup.service" ];
        requires = [ "postgresql-setup.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ config.services.postgresql.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
        };
        script = ''
          psql -d postgres -v ON_ERROR_STOP=1 \
            -c 'ALTER DATABASE "${config.services.nextcloud.config.dbname}" SET synchronous_commit = off'
        '';
      };

      # Collabora Online
      services.collabora-online = {
        enable = true;
        port = config.my.cloud-suite.collabora.port;
        settings = {
          # Rely on reverse proxy for SSL
          ssl = {
            enable = false;
            termination = true;
          };
          # Listen on loopback interface only, and accept requests from ::1
          net = {
            listen = "loopback";
            post_allow.host = [ "::1" ];
          };
          # Restrict loading documents from WOPI Host
          storage.wopi = {
            "@allow" = true;
            host = [ config.my.cloud-suite.nextcloud.hostName ];
          };
          # Set FQDN of server
          server_name = config.my.cloud-suite.collabora.hostName;
        };
      };

      # Immich
      services.immich = {
        enable = true;
        host = "127.0.0.1";
        port = config.my.cloud-suite.immich.port;
        mediaLocation = config.my.cloud-suite.immich.mediaLocation;
        package = config.my.cloud-suite.immich.package;
        accelerationDevices = config.my.cloud-suite.immich.accelerationDevices;
        database.enable = true;
        machine-learning.enable = true;
        openFirewall = false;
        settings = {
          server.externalDomain = "https://${config.my.cloud-suite.immich.hostName}";
          notifications.smtp = {
            enabled = true;
            from = config.my.cloud-suite.email.from;
            transport = {
              host = config.my.cloud-suite.email.host;
              port = config.my.cloud-suite.email.port;
              ignoreCert = !config.my.cloud-suite.email.ssl;
              username = "";
              password = "";
            };
          };
          backup.database = {
            enabled = true;
            cronExpression = "0 2 * * *";
            keepLastAmount = 14;
          };
        }
        // lib.optionalAttrs (config.my.cloud-suite.immich.accelerationDevices != [ ]) {
          ffmpeg = {
            accel = "vaapi";
            accelDecode = true;
          };
        };
      };

      # Uploads are streamed straight through (no request buffering to disk,
      # no response buffering), with a timeout long enough for a large video.
      services.nginx.virtualHosts.${config.my.cloud-suite.immich.hostName} = {
        inherit (config.my.cloud-suite.immich) allowedNetworks;
        extraConfig = "client_max_body_size ${config.my.cloud-suite.immich.maxUploadSize};";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.my.cloud-suite.immich.port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_request_buffering off;
            proxy_buffering off;
            proxy_read_timeout ${config.my.cloud-suite.immich.uploadTimeout};
            proxy_send_timeout ${config.my.cloud-suite.immich.uploadTimeout};
          '';
        };
      };

      # Vaultwarden takes the client IP (login rate limit, failed-login log)
      # from X-Real-IP, which recommendedProxySettings sets to $remote_addr.
      services.nginx.virtualHosts.${config.my.cloud-suite.bitwarden.hostName} = {
        inherit (config.my.cloud-suite.bitwarden) allowedNetworks;
        # Attachments and Sends; the size Vaultwarden's own docs use.
        extraConfig = "client_max_body_size 525m;";
        locations."/" = {
          proxyPass = "http://127.0.0.1:8000";
          # Live sync notifications.
          proxyWebsockets = true;
        };
      };

      services.nginx.virtualHosts.${config.my.cloud-suite.collabora.hostName} = {
        inherit (config.my.cloud-suite.collabora) allowedNetworks;
        extraConfig = "client_max_body_size 100m;";
        locations."/" = {
          proxyPass = "http://[::1]:${toString config.my.cloud-suite.collabora.port}";
          # An open document is one long-lived websocket; Collabora's own
          # proxy examples allow it ten hours of silence.
          proxyWebsockets = true;
          extraConfig = "proxy_read_timeout 36000s;";
        };
      };

      # Periodic HTTP probe of Nextcloud, because unit state alone cannot see the
      # failure mode that already happened once (2026-09-19): a broken stateful
      # config.php 503s every request while phpfpm-nextcloud, nextcloud-cron and
      # nextcloud-setup all stay green. The probe goes through nginx on loopback
      # (--resolve; the gates admit the host itself), so it exercises nginx →
      # php-fpm → config.php. Maintenance mode
      # is treated as healthy: the nightly backup quiesce is expected state.
      systemd.services.nextcloud-health = lib.mkIf config.my.cloud-suite.nextcloud.healthCheck.enable {
        description = "Nextcloud HTTP health probe (status.php)";
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
        };
        script = ''
          body=$(${pkgs.curl}/bin/curl -sf --max-time 30 \
            --resolve ${config.my.cloud-suite.nextcloud.hostName}:443:127.0.0.1 \
            https://${config.my.cloud-suite.nextcloud.hostName}/status.php) \
            || { echo "status.php unreachable" >&2; exit 1; }
          printf '%s' "$body" | ${pkgs.jq}/bin/jq -e \
            '(.maintenance == true) or (.installed == true)' >/dev/null \
            || { echo "unhealthy status.php: $body" >&2; exit 1; }
        '';
      };
      systemd.timers.nextcloud-health = lib.mkIf config.my.cloud-suite.nextcloud.healthCheck.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = config.my.cloud-suite.nextcloud.healthCheck.interval;
          RandomizedDelaySec = "2m";
        };
      };

      # NextCloud: upstream's nginx vhost (PHP-FPM) is the public one; nginx is
      # this host's edge, so it only needs the LAN gate (TLS comes from the zone
      # wildcard, see ../web-server).
      services.nginx.virtualHosts.${config.my.cloud-suite.nextcloud.hostName} = {
        inherit (config.my.cloud-suite.nextcloud) allowedNetworks;
        # Upstream's vhost sends its own HSTS.
        hsts = false;
      };

      # Bitwarden (Vaultwarden)
      services.vaultwarden = {
        enable = true;
        dbBackend = "postgresql";
        config = {
          DOMAIN = "https://${config.my.cloud-suite.bitwarden.hostName}";
          # Setting `config` replaces the module's loopback default; pin it so
          # the port nginx proxies to never ends up on every interface.
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = 8000;
          DATABASE_URL = "postgresql://vaultwarden?host=/var/run/postgresql";
          SIGNUPS_ALLOWED = config.my.cloud-suite.bitwarden.signupsAllowed;
          DATA_FOLDER = config.my.cloud-suite.bitwarden.dataDir;
          SMTP_HOST = config.my.cloud-suite.email.host;
          SMTP_PORT = config.my.cloud-suite.email.port;
          SMTP_SSL = config.my.cloud-suite.email.ssl;
          SMTP_FROM = config.my.cloud-suite.email.from;
        };
      };

      # vaultwarden runs with ProtectSystem=strict; allow writes to a custom DATA_FOLDER
      systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [
        config.my.cloud-suite.bitwarden.dataDir
      ];

    }
  );
}
