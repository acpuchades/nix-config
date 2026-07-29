{ config, lib, ... }:

let
  cfg = config.my.ups-monitor;
in
{
  options.my.ups-monitor = {
    enable = lib.mkEnableOption "UPS monitoring via NUT (Network UPS Tools)";

    name = lib.mkOption {
      type = lib.types.str;
      default = "cyberpower";
      description = "UPS identifier — referenced as <name>@localhost in upsc/upsmon";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "CyberPower CP900EPFCLCD";
      description = "Human-readable UPS description";
    };

    driver = lib.mkOption {
      type = lib.types.str;
      default = "usbhid-ups";
      description = "NUT driver — usbhid-ups handles CyberPower USB HID models";
    };

    port = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "Driver port — \"auto\" is correct for USB-connected UPSes";
    };

    monitorUser = lib.mkOption {
      type = lib.types.str;
      default = "monitor";
      description = "NUT username used by upsmon and remote clients";
    };

    monitorPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the monitor user's password (typically a sops secret path)";
    };

    notify = {
      command = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          NUT NOTIFYCMD to run on power events. When null (default) no
          notifications are wired. Typically set to
          config.my.ntfy-alert.powerNotifyCommand.
        '';
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          EnvironmentFile added to the upsmon service, so NOTIFYCMD inherits any
          secrets it needs (e.g. NTFY_TOKEN). Read by systemd as root before the
          upsmon user drop, then inherited by the forked NOTIFYCMD.
        '';
      };

      events = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "ONLINE" "ONBATT" "LOWBATT" "FSD" "COMMOK" "COMMBAD" "SHUTDOWN" "REPLBATT" "NOCOMM" ];
        description = "UPS event classes whose NOTIFYFLAG gets EXEC (so NOTIFYCMD fires).";
      };
    };

    network = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose upsd on the LAN — otherwise it only listens on localhost";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3493;
        description = "upsd listen port";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address upsd binds to when network access is enabled";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    power.ups = {
      enable = true;
      mode = "standalone";

      ups.${cfg.name} = {
        driver = cfg.driver;
        port = cfg.port;
        description = cfg.description;
      };

      users.${cfg.monitorUser} = {
        passwordFile = cfg.monitorPasswordFile;
        upsmon = "primary";
      };

      upsmon.monitor.${cfg.name} = {
        system = "${cfg.name}@localhost";
        user = cfg.monitorUser;
        passwordFile = cfg.monitorPasswordFile;
        type = "primary";
      };

      upsd.listen = lib.mkIf cfg.network.enable
        [ { address = cfg.network.listenAddress; port = cfg.network.port; } ];

      # Route power events to NOTIFYCMD (default upssched has no EXEC flags, so
      # it is dormant; overriding is safe — clean shutdown is FSD/SHUTDOWNCMD
      # driven, not upssched). Each event gets SYSLOG+WALL+EXEC so upsmon execs
      # the command in addition to its usual logging.
      upsmon.settings = lib.mkIf (cfg.notify.command != null) {
        NOTIFYCMD = lib.mkForce cfg.notify.command;
        NOTIFYFLAG = map (e: [ e "SYSLOG+WALL+EXEC" ]) cfg.notify.events;
      };
    };

    systemd.services.upsmon.serviceConfig.EnvironmentFile =
      lib.mkIf (cfg.notify.environmentFile != null) [ cfg.notify.environmentFile ];

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.network.enable [ cfg.network.port ];
  };
}
