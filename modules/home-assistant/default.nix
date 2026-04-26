{ config, lib, pkgs, ... }:

{
  options.my.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant home automation platform";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for nginx reverse proxy";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant listen port";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hass";
      description = "Home Assistant configuration directory";
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "hass";
        description = "PostgreSQL database name";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "hass";
        description = "PostgreSQL username";
      };
    };

    extraComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra built-in components to include";
    };

    customComponents = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Extra custom components to install";
    };

    email = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Sender email address";
      };

      recipient = lib.mkOption {
        type = lib.types.str;
        description = "Recipient email address for notifications";
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

  config = lib.mkIf config.my.home-assistant.enable {
    environment.systemPackages = [ pkgs.home-assistant-cli ];

    systemd.tmpfiles.rules = [
      "d ${config.my.home-assistant.configDir} 0750 hass hass -"
    ];

    services.postgresql = {
      ensureDatabases = [ config.my.home-assistant.database.name ];
      ensureUsers = [
        {
          name = config.my.home-assistant.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    services.home-assistant = {
      enable = true;
      openFirewall = false;
      configDir = config.my.home-assistant.configDir;
      extraPackages = python3Packages: [ python3Packages.psycopg2 python3Packages.isal ];
      extraComponents = config.my.home-assistant.extraComponents;
      customComponents = config.my.home-assistant.customComponents;
      config = {
        default_config = {};
        http = {
          server_host = "127.0.0.1";
          server_port = config.my.home-assistant.port;
          use_x_forwarded_for = true;
          trusted_proxies = [ "127.0.0.1" "::1" ];
        };
        recorder.db_url =
          "postgresql://${config.my.home-assistant.database.user}@/${config.my.home-assistant.database.name}?host=/var/run/postgresql";
        notify = [
          {
            platform = "smtp";
            name = "email";
            server = config.my.home-assistant.email.host;
            port = config.my.home-assistant.email.port;
            sender = config.my.home-assistant.email.from;
            recipient = config.my.home-assistant.email.recipient;
            encryption = if config.my.home-assistant.email.ssl then "starttls" else "none";
          }
        ];
      };
    };

    services.nginx.virtualHosts."${config.my.home-assistant.hostName}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.my.home-assistant.port}";
        proxyWebsockets = true;
      };
    };
  };
}
