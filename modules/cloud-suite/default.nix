{ config, lib, pkgs, ... }:

{
  options.my.cloud-suite = {
    enable = lib.mkEnableOption "Personal cloud suite (NextCloud + Collabora + Bitwarden + Immich)";

    nextcloud = {
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
        default = [];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };

      extraApps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "calendar" "contacts" "notes" "richdocuments" "tasks"
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

      maxUploadSize = lib.mkOption {
        type = lib.types.str;
        default = "50G";
        description = "Maximum upload size";
      };

      uploadTimeout = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "Read/write timeout for Immich uploads through Caddy";
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
        default = [];
        description = "GPU/render devices for hardware acceleration (e.g. [ \"/dev/dri/renderD128\" ])";
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
        default = [];
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

  config = lib.mkIf config.my.cloud-suite.enable (let
    emailParts = lib.splitString "@" config.my.cloud-suite.email.from;
    emailLocalPart = lib.elemAt emailParts 0;
    emailDomain = lib.elemAt emailParts 1;
    smtpAuth = config.my.cloud-suite.email.username != null
      && config.my.cloud-suite.email.passwordFile != null;
  in {

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

    # NextCloud
    services.nextcloud = {
      enable = true;
      hostName = config.my.cloud-suite.nextcloud.hostName;
      datadir = config.my.cloud-suite.nextcloud.dataDir;
      package = pkgs.nextcloud33;
      database.createLocally = true;
      configureRedis = true;
      maxUploadSize = config.my.cloud-suite.nextcloud.maxUploadSize;
      https = true;
      config = {
        dbtype = "pgsql";
        adminuser = "admin";
        adminpassFile = config.my.cloud-suite.nextcloud.adminPasswordFile;
      };
      appstoreEnable = true;
      autoUpdateApps.enable = true;
      extraApps = lib.genAttrs config.my.cloud-suite.nextcloud.extraApps
        (name: config.services.nextcloud.package.packages.apps.${name});
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
        trusted_proxies = [ "127.0.0.1" "::1" ];
        "integrity.check.disabled" = lib.mkForce false;
        mail_smtpmode = "smtp";
        mail_sendmailmode = "smtp";
        mail_from_address = emailLocalPart;
        mail_domain = emailDomain;
        mail_smtphost = config.my.cloud-suite.email.host;
        mail_smtpport = config.my.cloud-suite.email.port;
        mail_smtpsecure = if config.my.cloud-suite.email.ssl then "ssl" else "";
        mail_smtpauth = smtpAuth;
      } // lib.optionalAttrs smtpAuth {
        mail_smtpname = config.my.cloud-suite.email.username;
      } // lib.optionalAttrs (config.my.cloud-suite.nextcloud.maintenanceWindowStart != null) {
        maintenance_window_start = config.my.cloud-suite.nextcloud.maintenanceWindowStart;
      };
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
          post_allow.host = ["::1"];
        };
        # Restrict loading documents from WOPI Host
        storage.wopi = {
          "@allow" = true;
          host = [config.my.cloud-suite.nextcloud.hostName];
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
      } // lib.optionalAttrs (config.my.cloud-suite.immich.accelerationDevices != []) {
        ffmpeg = {
          accel = "vaapi";
          accelDecode = true;
        };
      };
    };

    services.caddy.virtualHosts."${config.my.cloud-suite.immich.hostName}".extraConfig = ''
      request_body {
        max_size ${config.my.cloud-suite.immich.maxUploadSize}
      }
      reverse_proxy http://127.0.0.1:${toString config.my.cloud-suite.immich.port} {
        transport http {
          read_timeout ${config.my.cloud-suite.immich.uploadTimeout}
          write_timeout ${config.my.cloud-suite.immich.uploadTimeout}
          versions 1.1
          keepalive off
        }
        flush_interval -1
      }
    '';

    services.caddy.virtualHosts."${config.my.cloud-suite.bitwarden.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (config.my.cloud-suite.bitwarden.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " config.my.cloud-suite.bitwarden.allowedNetworks}\nabort @denied")
        "reverse_proxy http://127.0.0.1:8000"
        "encode gzip"
      ]);

    services.caddy.virtualHosts."${config.my.cloud-suite.collabora.hostName}".extraConfig = ''
      reverse_proxy http://[::1]:${toString config.my.cloud-suite.collabora.port}
      encode gzip
    '';

    # NextCloud: nginx serves PHP-FPM on localhost; Caddy terminates TLS in front
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
    };
    services.nginx.virtualHosts."${config.my.cloud-suite.nextcloud.hostName}" = {
      listen = [{ addr = "127.0.0.1"; port = 8080; ssl = false; }];
      forceSSL = lib.mkForce false;
      enableACME = lib.mkForce false;
    };
    services.caddy.virtualHosts."${config.my.cloud-suite.nextcloud.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (config.my.cloud-suite.nextcloud.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " config.my.cloud-suite.nextcloud.allowedNetworks}\nabort @denied")
        ''
          reverse_proxy http://127.0.0.1:8080 {
            transport http {
              versions 1.1
            }
          }
          encode gzip''
      ]);

    # Bitwarden (Vaultwarden)
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      config = {
        DOMAIN = "https://${config.my.cloud-suite.bitwarden.hostName}";
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
    systemd.services.vaultwarden.serviceConfig.ReadWritePaths =
      [ config.my.cloud-suite.bitwarden.dataDir ];

  });
}
