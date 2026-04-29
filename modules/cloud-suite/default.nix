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
    };
  };

  config = lib.mkIf config.my.cloud-suite.enable {

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

    systemd.tmpfiles.rules = [
      "d ${config.my.cloud-suite.nextcloud.dataDir} 0750 nextcloud nextcloud -"
      "d ${config.my.cloud-suite.bitwarden.dataDir} 0700 vaultwarden vaultwarden -"
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
        trusted_proxies = [ "127.0.0.1" "::1" ];
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
      } // lib.optionalAttrs (config.my.cloud-suite.immich.accelerationDevices != []) {
        ffmpeg = {
          accel = "vaapi";
          accelDecode = true;
        };
      };
    };

    services.caddy.virtualHosts."${config.my.cloud-suite.immich.hostName}".extraConfig = ''
      reverse_proxy http://127.0.0.1:${toString config.my.cloud-suite.immich.port}
      encode gzip
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

  };
}
