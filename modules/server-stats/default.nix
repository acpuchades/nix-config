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

    postgresDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optionals config.services.postgresql.enable
        ([ "postgres" ] ++ config.services.postgresql.ensureDatabases);
      defaultText = lib.literalExpression ''[ "postgres" ] ++ config.services.postgresql.ensureDatabases'';
      description = ''
        Databases in which to CREATE EXTENSION pg_stat_statements. Only takes
        effect when services.postgresql.enable is true. Defaults to every
        managed database plus "postgres".
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

  (lib.mkIf config.services.postgresql.enable {
    services.prometheus.exporters.postgres = {
      enable = true;
      runAsLocalSuperUser = true;
      listenAddress = "127.0.0.1";
      port = 9187;
      extraFlags = [
        "--auto-discover-databases"
        "--extend.query-path=${./queries.yaml}"
      ];
    };
    services.prometheus.scrapeConfigs = [{
      # Dashboard 12485 templates `$Instance` from label_values({job="postgres-exporter"}, instance);
      # the job label must match or the dashboard's instance dropdown stays empty.
      job_name = "postgres-exporter";
      static_configs = [{ targets = [ "127.0.0.1:9187" ]; }];
    }];
    services.grafana.provision.dashboards.settings.providers = [
      # PostgreSQL Exporter
      (mkProvider "postgres" (fetchDashboard {
        id = 12485; revision = 1; hash = "sha256-IUTfM+Jm80QFqbaWJme6l7Ov52anVeN62nsS0zZXQVQ=";
      }))
    ];

    # pg_stat_statements feeds the dashboard's query-rate / runtime panels.
    # Loaded as a shared library here (not in postgresql-server) to keep
    # observability concerns inside the module that needs them.
    services.postgresql.settings.shared_preload_libraries = "pg_stat_statements";
    services.postgresql.settings."pg_stat_statements.track" = "all";

    # Auto-create the extension in every database listed in cfg.postgresDatabases.
    # `|| true` keeps postgres healthy if a database doesn't exist (e.g. when a
    # service isn't actually using the system postgres).
    systemd.services.postgresql.postStart =
      let psql = "${config.services.postgresql.package}/bin/psql";
      in lib.mkAfter (
        lib.concatMapStringsSep "\n"
          (db: "${psql} -tAc 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements' ${db} || true")
          cfg.postgresDatabases
      );
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
