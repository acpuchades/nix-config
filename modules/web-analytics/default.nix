{ config, lib, ... }:

let
  cfg = config.my.web-analytics;
in
{
  options.my.web-analytics = {
    enable = lib.mkEnableOption "Umami web analytics";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for the Umami dashboard and tracker";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Umami listen port (loopback only)";
    };

    appSecretFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the APP_SECRET used to sign user sessions.
        Read through systemd credentials, so the umami user does not need
        direct read permissions on the file.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Restrict access to these CIDR ranges (empty = unrestricted).
        Note: leaving this empty is required if the tracker script must
        be loaded from the public internet.
      '';
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable Umami's anonymous upstream telemetry";
    };
  };

  config = lib.mkIf cfg.enable {
    services.umami = {
      enable = true;
      createPostgresqlDatabase = true;
      settings = {
        HOSTNAME = "127.0.0.1";
        PORT = cfg.port;
        APP_SECRET_FILE = cfg.appSecretFile;
        DISABLE_TELEMETRY = cfg.disableTelemetry;
      };
    };

    services.caddy.virtualHosts."${cfg.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
        "reverse_proxy http://127.0.0.1:${toString cfg.port}"
        "encode gzip"
      ]);
  };
}
