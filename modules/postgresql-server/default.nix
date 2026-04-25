{ config, lib, ... }:

{
  options.my.postgresql-server = {
    enable = lib.mkEnableOption "PostgreSQL server";

    dataDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "PostgreSQL data directory (null = use NixOS default)";
    };
  };

  config = lib.mkIf config.my.postgresql-server.enable {
    services.postgresql.enable = true;

    services.postgresql.dataDir =
      lib.mkIf (config.my.postgresql-server.dataDir != null)
        config.my.postgresql-server.dataDir;

    systemd.tmpfiles.rules =
      lib.optionals (config.my.postgresql-server.dataDir != null) [
        "d ${config.my.postgresql-server.dataDir} 0700 postgres postgres -"
      ];
  };
}
