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
      description = "Basic auth file for web interface";
    };

    workerPools = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Worker pool definitions";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.prefect = {
      isSystemUser = true;
      group = "prefect";
    };
    users.groups.prefect = {};

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 prefect prefect -"
    ];

    services.prefect = {
      enable = true;
      host = cfg.host;
      port = cfg.port;
      database = "postgres";
      databaseHost = "";
      databasePort = 0;
      databaseUser = cfg.databaseUser;
      databaseName = cfg.databaseName;
      dataDir = cfg.dataDir;
      baseUrl = cfg.baseUrl;
      workerPools = cfg.workerPools;
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
      # public baseUrl (https://.../api), which sits behind Caddy basic_auth and
      # answers 401 — so the worker can never reach api/work_pools/<pool>. The
      # local server has no auth, so workers must talk to it directly.
      (lib.mapAttrs'
        (name: _: lib.nameValuePair "prefect-worker-${name}" {
          environment.PREFECT_API_URL = "http://127.0.0.1:${toString cfg.port}/api";
        })
        cfg.workerPools)
    ];

    services.caddy.virtualHosts = lib.mkIf (cfg.virtualHost != null) {
      ${cfg.virtualHost}.extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (cfg.basicAuthFile != null) "import ${cfg.basicAuthFile}")
        "reverse_proxy http://127.0.0.1:${toString cfg.port}"
        "encode gzip"
      ]);
    };
  };
}
