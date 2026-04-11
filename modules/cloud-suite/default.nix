{ config, lib, pkgs, ... }:

{
  options.my.cloud-suite = {
    enable = lib.mkEnableOption "Personal cloud suite (NextCloud + Collabora + Bitwarden)";
    
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
        inherit calendar contacts news notes richdocuments tasks;
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
        enabledPreviewProviders = [
          "OC\\Preview\\BMP"
          "OC\\Preview\\GIF"
          "OC\\Preview\\JPEG"
          "OC\\Preview\\Krita"
          "OC\\Preview\\MarkDown"
          "OC\\Preview\\MP3"
          "OC\\Preview\\OpenDocument"
          "OC\\Preview\\PNG"
          "OC\\Preview\\TXT"
          "OC\\Preview\\XBitmap"
          "OC\\Preview\\HEIC"
        ];
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

    # Bitwarden (Vaultwarden)
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      config = {
        DOMAIN = "https://${config.my.cloud-suite.bitwarden.hostName}";
        DATABASE_URL = "postgresql://vaultwarden?host=/var/run/postgresql";
        SIGNUPS_ALLOWED = config.my.cloud-suite.bitwarden.signupsAllowed;
        SMTP_HOST = "127.0.0.1";
        SMTP_PORT = 25;
        SMTP_SSL = false;
        SMTP_FROM = config.my.cloud-suite.bitwarden.smtpFrom;
        SMTP_FROM_NAME = config.my.cloud-suite.bitwarden.smtpFromName;
      };
    };
  };
}
