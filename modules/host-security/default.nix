{
  config,
  lib,
  pkgs,
  ...
}:

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

    localPortGuards = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            address = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Address the service listens on (IPv4).";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port of the service.";
            };
            users = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Local accounts allowed to connect, besides root.";
            };
          };
        }
      );
      default = { };
      example = {
        prefect = {
          port = 4200;
          users = [
            "caddy"
            "prefect"
          ];
        };
      };
      description = ''
        Local services with no authentication of their own, reachable only by
        the listed local accounts (an iptables owner match on new outbound
        connections). "Bound to loopback" keeps the network out but not every
        other process on the box — a compromised service or a prompt-injected
        agent included. Static accounts only: a DynamicUser has no name to
        match until it runs. Keep names short: the chain is
        `local-guard-<name>` and iptables caps chain names at 28 characters.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.localPortGuards != { }) {
        networking.firewall.extraCommands = lib.concatStrings (
          lib.mapAttrsToList (
            name: g:
            let
              chain = "local-guard-${name}";
              jump = "OUTPUT -d ${g.address} -p tcp --dport ${toString g.port} --syn -j ${chain}";
            in
            ''
              iptables -N ${chain} 2>/dev/null || iptables -F ${chain}
              iptables -A ${chain} -m owner --uid-owner root -j RETURN
              ${lib.concatMapStrings (u: ''
                iptables -A ${chain} -m owner --uid-owner ${u} -j RETURN \
                  || echo "local-guard-${name}: unknown user ${u}" >&2
              '') g.users}
              iptables -A ${chain} -p tcp -j REJECT --reject-with tcp-reset
              iptables -D ${jump} 2>/dev/null || true
              iptables -I ${jump}
            ''
          ) cfg.localPortGuards
        );
        networking.firewall.extraStopCommands = lib.concatStrings (
          lib.mapAttrsToList (name: g: ''
            iptables -D OUTPUT -d ${g.address} -p tcp --dport ${toString g.port} --syn -j local-guard-${name} 2>/dev/null || true
            iptables -F local-guard-${name} 2>/dev/null || true
            iptables -X local-guard-${name} 2>/dev/null || true
          '') cfg.localPortGuards
        );
      })

      (lib.mkIf cfg.fail2ban.enable {
        services.fail2ban = {
          enable = true;
          bantime = cfg.fail2ban.bantime;
          maxretry = cfg.fail2ban.maxretry;
          ignoreIP = cfg.fail2ban.ignoreIP;
          # A flat short ban caps the cost of a distributed guessing campaign at
          # (maxretry / bantime) per source forever; doubling per repeat offense
          # makes persistence exponentially expensive instead.
          bantime-increment = {
            enable = true;
            maxtime = "48h";
          };
        };
      })
    ]
  );
}
