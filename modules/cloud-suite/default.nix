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

      mediaLocation = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/immich";
        description = "Immich media storage directory";
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

      smtpFrom = lib.mkOption {
        type = lib.types.str;
        description = "SMTP from address";
      };

      smtpFromName = lib.mkOption {
        type = lib.types.str;
        description = "SMTP from name";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/vaultwarden";
        description = "Vaultwarden DATA_FOLDER (attachments, icons, sends)";
      };
    };
  };

  config = lib.mkIf config.my.cloud-suite.enable {

    # Postgres for shared database
    services.postgresql = {
      enable = true;
      ensureDatabases = [
        "vaultwarden"
      ];
      ensureUsers = [
        {
          name = "vaultwarden";
          ensureDBOwnership = true;
        }
      ];
    };

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
      extraApps = with config.services.nextcloud.package.packages.apps; {
        inherit bookmarks calendar contacts gpoddersync groupfolders
                news nextpod notes richdocuments tasks;
      };
      extraAppsEnable = true;
      phpOptions = {
        "opcache.interned_strings_buffer" = "24";
        "opcache.memory_consumption" = "256";
        "opcache.max_accelerated_files" = "10000";
        "opcache.revalidate_freq" = "1";
        "opcache.save_comments" = "1";
        "opcache.jit" = "tracing";
        "opcache.jit_buffer_size" = "128M";
      };
      settings = {
        overwriteprotocol = "https";
        default_phone_region = config.my.cloud-suite.nextcloud.phoneRegion;
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
      database.enable = true;
      machine-learning.enable = true;
      openFirewall = false;
    };

    services.nginx.virtualHosts."${config.my.cloud-suite.immich.hostName}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.my.cloud-suite.immich.port}";
        proxyWebsockets = true;
      };
    };

    services.nginx.virtualHosts."${config.my.cloud-suite.bitwarden.hostName}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
      };
    };

    services.nginx.virtualHosts."${config.my.cloud-suite.nextcloud.hostName}" = {
      forceSSL = true;
      enableACME = true;
    };

    services.nginx.virtualHosts."${config.my.cloud-suite.collabora.hostName}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://[::1]:${toString config.my.cloud-suite.collabora.port}";
        proxyWebsockets = true;
      };
    };

    # Bitwarden (Vaultwarden)
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      config = {
        DOMAIN = "https://${config.my.cloud-suite.bitwarden.hostName}";
        DATABASE_URL = "postgresql://vaultwarden?host=/var/run/postgresql";
        SIGNUPS_ALLOWED = config.my.cloud-suite.bitwarden.signupsAllowed;
        DATA_FOLDER = config.my.cloud-suite.bitwarden.dataDir;
        SMTP_HOST = "127.0.0.1";
        SMTP_PORT = 25;
        SMTP_SSL = false;
        SMTP_FROM = config.my.cloud-suite.bitwarden.smtpFrom;
        SMTP_FROM_NAME = config.my.cloud-suite.bitwarden.smtpFromName;
      };
    };

    # vaultwarden runs with ProtectSystem=strict; allow writes to a custom DATA_FOLDER
    systemd.services.vaultwarden.serviceConfig.ReadWritePaths =
      [ config.my.cloud-suite.bitwarden.dataDir ];

  };
}
