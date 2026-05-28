{ config, lib, ... }:

let
  cfg = config.my.print-server;
in
{
  options.my.print-server = {
    enable = lib.mkEnableOption "CUPS network print server (IPP/AirPrint)";

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        CIDR ranges allowed to reach CUPS (IPP, TCP 631). Enforced both at the
        firewall (source-restricted accept rules) and inside CUPS via
        `allowFrom`. Empty means no firewall opening is added (VPN peers on a
        trusted interface can still connect).
      '';
    };

    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Extra CUPS driver packages. Leave empty for driverless printers that
        speak IPP Everywhere / AirPrint — CUPS auto-negotiates the format.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      # Listen on all IPv4 interfaces (covers LAN + WireGuard peers); access is
      # constrained by allowFrom + firewall. Deliberately NOT "*:631": that binds
      # a dual-stack IPv6 socket, so IPv4 clients reach CUPS as v4-mapped
      # (::ffff:a.b.c.d) addresses that fail the IPv4 `allowFrom` rules → 403.
      listenAddresses = [ "0.0.0.0:631" ];
      allowFrom = [ "localhost" ] ++ cfg.allowedNetworks;
      browsing = true;
      # Newly added queues are shared (advertised over DNS-SD) by default.
      defaultShared = true;
      drivers = cfg.drivers;
    };

    # Advertise shared queues as AirPrint over mDNS. Defaulted so a globally
    # configured services.avahi (for .local) still takes precedence.
    services.avahi = {
      enable = lib.mkDefault true;
      publish.enable = lib.mkDefault true;
      publish.userServices = lib.mkDefault true;
    };

    # Allow IPP (TCP 631) only from the configured networks. Inserted at the top
    # of the nixos-fw chain so it precedes the default refuse rule. VPN peers are
    # already covered via the trusted wg interface; these rules cover the LAN.
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n"
      (net: "iptables -I nixos-fw -p tcp -s ${net} --dport 631 -j nixos-fw-accept")
      cfg.allowedNetworks;

    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n"
      (net: "iptables -D nixos-fw -p tcp -s ${net} --dport 631 -j nixos-fw-accept || true")
      cfg.allowedNetworks;
  };
}
