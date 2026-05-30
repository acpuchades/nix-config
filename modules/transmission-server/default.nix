{ config, lib, pkgs, ... }:

# Transmission BitTorrent daemon + web UI.
#
# This module is intentionally UNAWARE of any VPN/egress concern. It just runs
# the daemon, exposes the web UI behind Caddy, and applies bandwidth limits.
# Confining the daemon's traffic to a VPN tunnel (policy routing, kill switch,
# NAT-PMP port forwarding) is a host-specific topology concern handled outside
# this module — see machines/homeserver/transmission-egress.nix, the same way
# modules/wireguard-client (tunnel) is kept separate from
# machines/homeserver/vpn-egress.nix (routing). The egress layer hooks onto the
# daemon purely by its UID (the upstream-static `transmission` user), so nothing
# VPN-related ever leaks into this module's interface.

let
  cfg = config.my.transmission-server;
in
{
  options.my.transmission-server = {
    enable = lib.mkEnableOption "Transmission BitTorrent daemon with web UI";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Virtual host for the Caddy-fronted web UI.";
      example = "torrent.acpuchades.com";
    };

    downloadDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/shared/Downloads";
      description = "Directory completed downloads are saved to.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = ''
        Primary group of the transmission user. Defaults to the Samba `share`
        group so downloads land group-writable for other share members (the
        download dir is a setgid `share` directory). Set together with
        `umask = "002"` below.
      '';
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Loopback port the RPC/web UI binds to (fronted by Caddy).";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict web UI access to these CIDR ranges (empty = unrestricted).";
    };

    basicAuthFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Caddy basic_auth snippet to `import` in front of the web UI.";
    };

    # Bandwidth / ratio / peer limits — sensible defaults for a residential
    # uplink; the values are in KB/s.
    maxUpKBps = lib.mkOption {
      type = lib.types.int;
      default = 1500;
      description = "Global upload speed limit (KB/s) — protects the uplink.";
    };

    maxDownKBps = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = "Global download speed limit (KB/s).";
    };

    altUpKBps = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = "Turtle-mode upload speed limit (KB/s), used on the daytime schedule.";
    };

    altDownKBps = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "Turtle-mode download speed limit (KB/s), used on the daytime schedule.";
    };

    ratioLimit = lib.mkOption {
      type = lib.types.float;
      default = 2.0;
      description = "Stop seeding a torrent once it reaches this share ratio.";
    };

    peerLimitGlobal = lib.mkOption {
      type = lib.types.int;
      default = 200;
      description = "Maximum peers across all torrents.";
    };

    peerLimitPerTorrent = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Maximum peers per torrent.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.transmission = {
      enable = true;
      # stateVersion < 25.11 makes the package default a `throw`; set it explicitly.
      package = pkgs.transmission_4;
      group = cfg.group;
      downloadDirPermissions = "0770";
      # Peer port lives on the VPN tunnel (handled by the egress layer) and the
      # web UI is proxied locally by Caddy — nothing belongs on the LAN firewall.
      openPeerPorts = false;
      openRPCPort = false;

      settings = {
        # Web UI / RPC — loopback only, Caddy fronts it.
        rpc-bind-address = "127.0.0.1";
        rpc-port = cfg.rpcPort;
        rpc-whitelist-enabled = true;
        rpc-whitelist = "127.0.0.1";
        # Caddy forwards Host: ${hostName}; the host whitelist would 409 it, and
        # access is already gated by allowedNetworks + basic auth.
        rpc-host-whitelist-enabled = false;
        # No RPC auth: the endpoint is loopback-only (rpc-whitelist 127.0.0.1) and
        # reached solely through Caddy, which is the single auth gate (basicAuthFile
        # + allowedNetworks). A second password here only collides with Caddy's,
        # since Caddy forwards the Authorization header upstream.
        rpc-authentication-required = false;

        # Storage — keep incomplete inside the download tree so it stays within
        # the daemon's RootDirectory bind mounts and AppArmor whitelist.
        download-dir = cfg.downloadDir;
        incomplete-dir = "${cfg.downloadDir}/.incomplete";
        incomplete-dir-enabled = true;
        # Group-writable so other `share` members can manage the files.
        umask = "002";

        # Peer port is a placeholder; the NAT-PMP renewal loop overwrites it at
        # runtime with Proton's forwarded port (see transmission-egress.nix).
        peer-port = 51413;
        peer-port-random-on-start = false;

        # P2P discovery — DHT/PEX on; LPD off (pointless on a VPN-only iface).
        dht-enabled = true;
        pex-enabled = true;
        lpd-enabled = false;
        encryption = 1;

        # Bandwidth / ratio / peers.
        ratio-limit = cfg.ratioLimit;
        ratio-limit-enabled = true;
        speed-limit-down = cfg.maxDownKBps;
        speed-limit-down-enabled = true;
        speed-limit-up = cfg.maxUpKBps;
        speed-limit-up-enabled = true;
        peer-limit-global = cfg.peerLimitGlobal;
        peer-limit-per-torrent = cfg.peerLimitPerTorrent;

        # Turtle schedule: slower during the day (08:00–23:00, all days),
        # full speed overnight.
        alt-speed-down = cfg.altDownKBps;
        alt-speed-up = cfg.altUpKBps;
        alt-speed-time-enabled = true;
        alt-speed-time-day = 127; # bitmask: every day
        alt-speed-time-begin = 480; # 08:00 (minutes past midnight)
        alt-speed-time-end = 1380; # 23:00
      };
    };

    # Reverse proxy the web UI, restricted to private nets + basic auth. Mirrors
    # the snippet used by modules/dns-filtering.
    services.caddy.virtualHosts.${cfg.hostName}.extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
      (lib.optionalString (cfg.allowedNetworks != [])
        "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
      (lib.optionalString (cfg.basicAuthFile != null)
        "import ${cfg.basicAuthFile}")
      "reverse_proxy http://127.0.0.1:${toString cfg.rpcPort}"
      "encode gzip"
    ]);
  };
}
