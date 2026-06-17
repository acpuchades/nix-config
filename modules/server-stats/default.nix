{ config, lib, pkgs, ... }:

let
  cfg = config.my.server-stats;

  btrfsMounts = lib.attrNames
    (lib.filterAttrs (_: fs: fs.fsType == "btrfs") config.fileSystems);

  smartPort = 9633;

  # Fetch a community Grafana dashboard from grafana.com and rewrite its datasource
  # references so the provisioned "Prometheus" datasource is picked up automatically.
  # On first build, set hash = lib.fakeHash; the build will fail and print the real hash.
  fetchDashboard = { id, revision, hash }:
    let
      raw = pkgs.fetchurl {
        url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString revision}/download";
        inherit hash;
      };
    in pkgs.runCommand "grafana-dashboard-${toString id}.json" {
      nativeBuildInputs = [ pkgs.jq ];
    } ''
      jq 'walk(
            if type == "object" and (.datasource | type) == "string"
              then .datasource = "Prometheus"
            elif type == "object" and (.datasource | type) == "object" and .datasource.type == "prometheus"
              then .datasource = "Prometheus"
            else . end
          ) | del(.__inputs, .__elements, .__requires)' \
        ${raw} > $out
    '';

  # Grafana's file provider expects a directory, so wrap a single JSON file as one.
  mkProvider = name: jsonFile: {
    inherit name;
    folder = "Server Stats";
    options.path = pkgs.runCommand "${name}-dashboard-dir" { } ''
      mkdir -p $out
      cp ${jsonFile} $out/${name}.json
    '';
  };

  # Minimal inline btrfs dashboard — no community dashboard exists on grafana.com
  # for node_exporter's btrfs collector, so build one from the relevant series.
  btrfsDashboard = pkgs.writeText "btrfs.json" (builtins.toJSON {
    uid = "server-stats-btrfs";
    title = "Btrfs";
    schemaVersion = 38;
    refresh = "30s";
    time = { from = "now-6h"; to = "now"; };
    panels = [
      {
        id = 1;
        type = "timeseries";
        title = "Allocation ratio (used / size)";
        gridPos = { h = 8; w = 12; x = 0; y = 0; };
        datasource = "Prometheus";
        targets = [{
          expr = "node_btrfs_allocation_ratio";
          legendFormat = "{{device}} {{block_group_type}}";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percentunit";
      }
      {
        id = 2;
        type = "timeseries";
        title = "Size vs used bytes";
        gridPos = { h = 8; w = 12; x = 12; y = 0; };
        datasource = "Prometheus";
        targets = [
          { expr = "node_btrfs_size_bytes"; legendFormat = "size {{device}} {{block_group_type}}"; refId = "A"; }
          { expr = "node_btrfs_used_bytes"; legendFormat = "used {{device}} {{block_group_type}}"; refId = "B"; }
        ];
        fieldConfig.defaults.unit = "bytes";
      }
      {
        id = 3;
        type = "stat";
        title = "Device errors";
        gridPos = { h = 6; w = 12; x = 0; y = 8; };
        datasource = "Prometheus";
        targets = [{
          expr = "sum by (device, type) (node_btrfs_device_errors_total)";
          legendFormat = "{{device}} {{type}}";
          refId = "A";
        }];
      }
      {
        id = 4;
        type = "timeseries";
        title = "Global reservation size";
        gridPos = { h = 6; w = 12; x = 12; y = 8; };
        datasource = "Prometheus";
        targets = [{
          expr = "node_btrfs_global_rsv_size_bytes";
          legendFormat = "{{uuid}}";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "bytes";
      }
    ];
  });
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

    secretKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file holding Grafana's `security.secret_key` (used to encrypt
        secrets stored in its database). Read at runtime via Grafana's
        `$__file{}` provider, so the value never enters the Nix store. Point this
        at a sops secret owned by the grafana user.
      '';
    };

    rendererTokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file holding the raw image-renderer token. Read by Grafana via
        its `$__file{}` provider into `[rendering] renderer_token`, so the value
        never enters the Nix store. Must match the renderer's `AUTH_TOKEN`
        (see {option}`rendererAuthEnvFile`). Point at a sops secret owned by the
        grafana user. Generate with: openssl rand -hex 32
      '';
    };

    rendererAuthEnvFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an EnvironmentFile defining `AUTH_TOKEN=<token>` for
        grafana-image-renderer. The renderer takes its auth token only from the
        environment (its CLI/config args land in the Nix store and `ps`, so a
        secret can't go there), and as of the 26.05 bump it refuses the built-in
        default token in production. Must hold the same value as
        {option}`rendererTokenFile`. Point at a sops template.
      '';
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

    # Native image-renderer module. `provisionGrafana` wires Grafana's
    # rendering.server_url/callback_url automatically (renderer listens on the
    # default localhost:8081). The auth token is the only secret and can't live
    # in `settings` (those become CLI args, visible in the store and `ps`), so it
    # comes in as AUTH_TOKEN via an EnvironmentFile — read by the service manager
    # as root, so the DynamicUser sandbox doesn't block it.
    services.grafana-image-renderer = {
      enable = true;
      provisionGrafana = true;
    };
    systemd.services.grafana-image-renderer.serviceConfig.EnvironmentFile =
      cfg.rendererAuthEnvFile;

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = config.my.server-stats.port;
          domain = config.my.server-stats.hostName;
          root_url = "https://${config.my.server-stats.hostName}";
        };
        security.secret_key = "$__file{${cfg.secretKeyFile}}";
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        # server_url/callback_url are provisioned by services.grafana-image-renderer
        # (provisionGrafana). Only the token is set here, via the file provider so
        # it never enters the Nix store, matching the renderer's AUTH_TOKEN.
        rendering.renderer_token = "$__file{${cfg.rendererTokenFile}}";
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
        dashboards.settings.providers = [
          # Node Exporter Full
          (mkProvider "node" (fetchDashboard {
            id = 1860; revision = 45; hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
          }))
          # SMARTctl Exporter Dashboard
          (mkProvider "smartctl" (fetchDashboard {
            id = 22604; revision = 2; hash = "sha256-ci8WE23fZ+ltEKFoUdNNVXsUIV0jqtas79ia2lYIo88=";
          }))
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
    # Btrfs metrics (node_btrfs_*) come from node_exporter's built-in btrfs collector.
    services.grafana.provision.dashboards.settings.providers = [
      (mkProvider "btrfs" btrfsDashboard)
    ];
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
    services.grafana.provision.dashboards.settings.providers = [
      # Caddy Monitoring
      (mkProvider "caddy" (fetchDashboard {
        id = 20802; revision = 1; hash = "sha256-vSt63PakGp5NzKFjbU5Yh0nDbKET5QRWp5nusM76/O4=";
      }))
    ];
  })

  ]);
}
