{ config, lib, ... }:

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

    workerPools = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Worker pool definitions";
    };
  };

  config = lib.mkIf config.my.prefect-server.enable {
    users.users.prefect = {
      isSystemUser = true;
      group = "prefect";
    };
    users.groups.prefect = {};

    systemd.tmpfiles.rules = [
      "d ${config.my.prefect-server.dataDir} 0750 prefect prefect -"
    ];

    services.prefect = {
      enable = true;
      host = config.my.prefect-server.host;
      port = config.my.prefect-server.port;
      database = "postgres";
      databaseHost = "";
      databasePort = 0;
      databaseUser = config.my.prefect-server.databaseUser;
      databaseName = config.my.prefect-server.databaseName;
      dataDir = config.my.prefect-server.dataDir;
      baseUrl = config.my.prefect-server.baseUrl;
      workerPools = config.my.prefect-server.workerPools;
    };

    systemd.services.prefect-server.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "prefect";
      Group = "prefect";
      ReadWritePaths = [ config.my.prefect-server.dataDir ];
    };
  };
}
