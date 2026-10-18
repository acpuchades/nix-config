# Monitoring and alerting: ntfy (push server), the ntfy-alert wiring and its
# list of alerted units, Grafana/Prometheus, the UPS, and host hardening
# (fail2ban, local port guards). The failureUnits list is the host-level
# statement of what gets alerted on — every service's units go there, fugazi's
# included.
{ config, ... }:

let
  inherit (import ./networks.nix) privateNetworks;
in
{
  imports = [
    ../../modules/push-notifications
    ../../modules/ntfy-alert
    ../../modules/server-stats
    ../../modules/ups-monitor
    ../../modules/host-security
  ];

  # ntfy. Deliberately NOT restricted to privateNetworks — a push server
  # that only works on the LAN is pointless. Auth is deny-all instead, so
  # users/tokens must be created with the CLI before anything can publish
  # or subscribe. See the module header.
  my.push-notifications = {
    enable = true;
    hostName = "ntfy.acpuchades.com";
    # The name is Cloudflare-proxied; ntfy locks out repeated auth
    # failures per visitor on its own, given the real one.
    trustedProxies = config.my.web-server.trustedProxies;
  };

  # Opt-in ntfy alerting. The module forces nothing; alerts fire only for the
  # units listed here (and the UPS wiring in this file). One shared ntfy token
  # (ntfy/token) backs all of it, backup included.
  my.ntfy-alert = {
    enable = true;
    environmentFile = config.sops.templates."ntfy/env".path;
    # ntfy is served from this host: connect straight to Caddy, so alerts
    # still go out when DNS is what broke (it did on 2026-09-26, when the
    # resolver's tunnel died).
    resolveTo = "127.0.0.1";
    healthCheck = {
      enable = true;
      diskPaths = [
        "/"
        "/boot"
        "/srv"
        "/srv/encrypted"
      ];
    };
    bootNotice.enable = true;
    # All suitable long-running services whose failure means a real outage.
    # Bare unit names (no .service). Setup/one-shot units are excluded
    # (they fail visibly at deploy time, not in steady state) — with one
    # deliberate exception: nextcloud-health, the timer-driven probe that
    # exists precisely because a Nextcloud dead from a broken stateful
    # config.php keeps phpfpm-nextcloud and nextcloud-cron green.
    failureUnits = [
      "nextcloud-health"
      "restic-backups-homeserver"
      "postgresql"
      "redis-nextcloud"
      "redis-immich"
      "caddy"
      "postfix"
      "vaultwarden"
      "phpfpm-nextcloud"
      "nextcloud-cron"
      "immich-server"
      "home-assistant"
      "prefect-server"
      "fugazi-web-testing"
      # The resident deployment tickers, and only those: the twelve timed
      # cadences are oneshots, which this list deliberately excludes. These
      # three are long-running units with no timer behind them, so one that
      # systemd stops retrying advances nothing until a human notices.
      "fugazi-web-testing-deployment-tick-1m"
      "fugazi-web-testing-deployment-tick-3m"
      "fugazi-web-testing-deployment-tick-5m"
      # titan's API. Not titan-sync: a vendor outage fails one hourly
      # oneshot and the next run catches up.
      "titan"
      "ddclient"
      "openclaw-eva"
      "bitcoind-main"
      "upsd"
      "upsmon"
      # DNS for the LAN and the VPN.
      "adguardhome"
      "dnscrypt-proxy"
      # Nextcloud's vhost is Caddy -> nginx -> php-fpm; Collabora behind it.
      "nginx"
      "coolwsd"
      "immich-machine-learning"
      "jellyfin"
      "transmission"
      "samba-smbd"
      "cups"
      "rspamd"
      "sshd"
      "fail2ban"
      "tor"
      "prefect-worker-default"
      # Proton egress. policy/p2p/veth are RemainAfterExit oneshots: they
      # only fail at start, and when they do, routing or the P2P netns is
      # broken. The tunnels themselves alert through the watchdog.
      "protonvpn-policy"
      "protonvpn-proton-p2p"
      "protonvpn-veth-torrent"
      "protonvpn-natpmp"
      # Rare scheduled jobs, excepted from the no-oneshots rule because a
      # failure is both infrequent and serious: an expiring certificate,
      # and a scrub that hit errors on the data disks.
      "acme-order-renew-acpuchades.com"
      "btrfs-scrub-srv"
      "btrfs-scrub-srv-encrypted"
    ];
  };

  my.server-stats = {
    enable = true;
    hostName = "status.acpuchades.com";
    port = 3001;
    allowedNetworks = privateNetworks;
    secretKeyFile = config.sops.secrets."grafana/secret-key".path;
    rendererTokenFile = config.sops.secrets."grafana/renderer-token".path;
    rendererAuthEnvFile = config.sops.templates."grafana/renderer-env".path;
  };

  my.ups-monitor = {
    enable = true;
    monitorPasswordFile = config.sops.secrets."nut/monitor".path;
    network.enable = true;
    network.allowedNetworks = privateNetworks;
    # Push power events (on-battery, low-battery, back-online…) to ntfy.
    notify.command = config.my.ntfy-alert.powerNotifyCommand;
    notify.environmentFile = config.sops.templates."ntfy/env".path;
  };

  my.host-security = {
    enable = true;
    fail2ban = {
      enable = true;
      ignoreIP = privateNetworks;
    };
    # Unauthenticated control APIs: Caddy (which adds basic-auth and the
    # LAN gate) and their own clients only.
    localPortGuards = {
      # DNS rewrites for every LAN/VPN client.
      adguard = {
        port = config.my.dns-filtering.adguardPort;
        users = [ "caddy" ];
      };
      # Runs arbitrary code as prefect. alex uses the CLI against it.
      prefect = {
        port = config.my.prefect-server.port;
        users = [
          "caddy"
          "prefect"
          "alex"
        ];
      };
      # Spam thresholds, maps and learning.
      rspamd = {
        port = 11334;
        users = [ config.services.rspamd.user ];
      };
      # Download dir and torrent-done script (code exec as transmission).
      transmission = {
        address = config.my.protonvpn.transmission.veth.namespaceAddress;
        port = config.my.transmission-server.rpcPort;
        users = [ "caddy" ];
      };
    };
  };
}
