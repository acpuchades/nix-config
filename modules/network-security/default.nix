{ config, lib, pkgs, ... }:

{
  options.my.network-security = {
    enable = lib.mkEnableOption "network security monitoring";

    arpwatch = {
      enable = lib.mkEnableOption "arpwatch ARP monitoring";

      interfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "eth0" "wlp3s0" ];
        description = "Network interfaces to monitor for ARP changes";
      };

      emailTo = lib.mkOption {
        type = lib.types.str;
        description = "Email address to send arpwatch notifications to";
      };

      promiscuous = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable promiscuous mode on monitored interfaces";
      };
    };
  };

  config = lib.mkIf (config.my.network-security.enable && config.my.network-security.arpwatch.enable) {
    services.arpwatch = {
      enable = true;
      interfaces = lib.genAttrs config.my.network-security.arpwatch.interfaces (_: {
        promiscuous = config.my.network-security.arpwatch.promiscuous;
        emailTo = config.my.network-security.arpwatch.emailTo;
      });
    };
  };
}
