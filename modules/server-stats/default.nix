{ config, lib, pkgs, ... }:

let
  cfg = config.my.server-stats;

  btrfsMounts = lib.attrNames
    (lib.filterAttrs (_: fs: fs.fsType == "btrfs") config.fileSystems);

  smartPort = 9633;
in
{
  options.my.server-stats = {
    enable = lib.mkEnableOption "Prometheus + Grafana system monitoring dashboard";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for the Grafana dashboard reverse proxy";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana listen port";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };

    btrfsScrubInterval = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
      description = "systemd OnCalendar expression for btrfs auto-scrub (only takes effect when btrfs filesystems are present).";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [ {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9100;
        enabledCollectors = [ "systemd" ];
      };
      exporters.smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = smartPort;
      };
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
        }
        {
          job_name = "smartctl";
          static_configs = [{ targets = [ "127.0.0.1:${toString smartPort}" ]; }];
        }
      ];
    };

    systemd.services.grafana-image-renderer = {
      description = "Grafana Image Renderer";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.chromium ];
      serviceConfig = {
        ExecStart = "${pkgs.grafana-image-renderer}/bin/grafana-image-renderer server";
        User = "grafana";
        Restart = "on-failure";
        Environment = [
          "HTTP_HOST=127.0.0.1"
          "HTTP_PORT=8081"
          "ENABLE_METRICS=true"
        ];
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = config.my.server-stats.port;
          domain = config.my.server-stats.hostName;
          root_url = "https://${config.my.server-stats.hostName}";
        };
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        rendering = {
          server_url = "http://127.0.0.1:8081/render";
          callback_url = "http://127.0.0.1:${toString config.my.server-stats.port}/";
        };
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
        ];
      };
    };

    services.caddy.virtualHosts."${cfg.hostName}".extraConfig =
      if cfg.allowedNetworks != [] then ''
        @allowed remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}
        handle @allowed {
          reverse_proxy http://127.0.0.1:${toString cfg.port}
          encode gzip
        }
        respond 403
      '' else ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
        encode gzip
      '';
  }

  (lib.mkIf (btrfsMounts != []) {
    services.btrfs.autoScrub = {
      enable = true;
      fileSystems = btrfsMounts;
      interval = cfg.btrfsScrubInterval;
    };
  })

  (lib.mkIf config.services.postgresql.enable {
    services.prometheus.exporters.postgres = {
      enable = true;
      runAsLocalSuperUser = true;
      listenAddress = "127.0.0.1";
      port = 9187;
    };
    services.prometheus.scrapeConfigs = [{
      job_name = "postgres";
      static_configs = [{ targets = [ "127.0.0.1:9187" ]; }];
    }];
  })

  (lib.mkIf config.services.caddy.enable {
    services.caddy.globalConfig = ''
      servers {
        metrics
      }
    '';
    services.prometheus.scrapeConfigs = [{
      job_name = "caddy";
      static_configs = [{ targets = [ "127.0.0.1:2019" ]; }];
    }];
  })

  ]);
}
