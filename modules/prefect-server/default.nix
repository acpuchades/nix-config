{ config, lib, ... }:

let
  cfg = config.my.prefect-server;
in
{
  options.my.prefect-server = {
    enable = lib.mkEnableOption "Prefect workflow server";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4200;
      description = "Port to listen on";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/prefect";
      description = "Directory for Prefect data storage";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      description = "Public base URL for the Prefect UI";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "prefect";
      description = "PostgreSQL user";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "prefect";
      description = "PostgreSQL database name";
    };

    virtualHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Virtual host for reverse proxy";
    };

    basicAuthFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "htpasswd file for the web interface (nginx auth_basic_user_file).";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Restrict the vhost to these CIDR ranges (empty = unrestricted). Behind
        it is an unauthenticated API that runs code, so basic auth alone makes
        that one password the whole boundary, guessable from anywhere.
      '';
    };

    workerPools = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Worker pool definitions";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.prefect = {
      isSystemUser = true;
      group = "prefect";
    };
    users.groups.prefect = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 prefect prefect -"
    ];

    services.prefect = {
      enable = true;
      inherit (cfg) host;
      inherit (cfg) port;
      database = "postgres";
      databaseHost = "";
      databasePort = 0;
      inherit (cfg) databaseUser;
      inherit (cfg) databaseName;
      inherit (cfg) dataDir;
      inherit (cfg) baseUrl;
      inherit (cfg) workerPools;
    };

    systemd.services = lib.mkMerge [
      {
        prefect-server.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "prefect";
          Group = "prefect";
          ReadWritePaths = [ cfg.dataDir ];
        };
      }

      # Pin every worker to the LOCAL API. Otherwise the worker resolves the
      # public baseUrl (https://.../api), which sits behind nginx basic auth and
      # answers 401 — so the worker can never reach api/work_pools/<pool>. The
      # local server has no auth, so workers must talk to it directly.
      #
      # The upstream module bakes PREFECT_API_URL=${baseUrl}/api into the worker's
      # `serviceConfig.Environment` LIST. Setting the top-level `environment`
      # attr only ADDS a second `Environment=` line, and systemd applies the last
      # one — the upstream (public) URL — so a top-level override is silently
      # ignored. Force-replace the whole list instead, keeping the PREFECT_HOME
      # entry upstream also sets (StateDirectory = prefect-worker-${name}).
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair "prefect-worker-${name}" {
          # A static account rather than upstream's DynamicUser, so a firewall
          # owner match (my.host-security.localPortGuards) can name it.
          serviceConfig.DynamicUser = lib.mkForce false;
          serviceConfig.User = "prefect";
          serviceConfig.Group = "prefect";
          serviceConfig.Environment = lib.mkForce [
            "PREFECT_HOME=%S/prefect-worker-${name}"
            "PREFECT_API_URL=http://127.0.0.1:${toString cfg.port}/api"
          ];
        }
      ) cfg.workerPools)
    ];

    services.nginx.virtualHosts = lib.mkIf (cfg.virtualHost != null) {
      ${cfg.virtualHost} = {
        inherit (cfg) allowedNetworks basicAuthFile;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          # The UI's live event feed is a websocket.
          proxyWebsockets = true;
        };
      };
    };
  };
}
