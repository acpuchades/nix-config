{ config, lib, pkgs, ... }:

let
  cfg = config.my.host-security;
in
{
  options.my.host-security = {
    enable = lib.mkEnableOption "host security services";

    fail2ban = {
      enable = lib.mkEnableOption "fail2ban intrusion prevention";

      bantime = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = "Default ban duration for jails";
      };

      maxretry = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Default number of failures before a host is banned";
      };

      ignoreIP = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "192.168.1.0/24" ];
        description = "Addresses/networks that should never be banned";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.fail2ban.enable {
      services.fail2ban = {
        enable = true;
        bantime = cfg.fail2ban.bantime;
        maxretry = cfg.fail2ban.maxretry;
        ignoreIP = cfg.fail2ban.ignoreIP;
      };
    })
  ]);
}
