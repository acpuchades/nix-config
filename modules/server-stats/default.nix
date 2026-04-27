{ config, lib, pkgs, ... }:

{
  options.my.server-stats = {
    enable = lib.mkEnableOption "Netdata system monitoring dashboard";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for the monitoring dashboard reverse proxy";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 19999;
      description = "Netdata listen port";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };
  };

  config = lib.mkIf config.my.server-stats.enable {
    nixpkgs.config.allowUnfreePredicate = pkg:
      lib.getName pkg == "netdata";

    services.netdata = {
      enable = true;
      package = pkgs.netdata.override { withCloudUi = true; };
      config = {
        global = {
          "bind to" = "127.0.0.1:${toString config.my.server-stats.port}";
        };
      };
    };

    services.caddy.virtualHosts."${config.my.server-stats.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (config.my.server-stats.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " config.my.server-stats.allowedNetworks}\nabort @denied")
        "reverse_proxy http://127.0.0.1:${toString config.my.server-stats.port}"
        "encode gzip"
      ]);
  };
}
