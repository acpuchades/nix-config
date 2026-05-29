{ config, lib, ... }:

let
  cfg = config.my.service-dashboard;

  serviceType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Tile label";
      };
      href = lib.mkOption {
        type = lib.types.str;
        description = "URL the tile links to";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Short subtitle shown under the tile";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Homepage icon slug (e.g. \"nextcloud.png\", \"mdi-map-marker\")";
      };
      siteMonitor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "URL to health-check; defaults to href. Any HTTP response counts as up.";
      };
    };
  };

  groupType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Group heading";
      };
      columns = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Number of columns in this group's row layout";
      };
      services = lib.mkOption {
        type = lib.types.listOf serviceType;
        description = "Tiles in this group";
      };
    };
  };

  # Drop null-valued attrs so the generated YAML stays clean.
  prune = lib.filterAttrs (_: v: v != null);

  # Homepage's services.yaml is an ordered list of single-key group maps, each
  # mapping a group name to an ordered list of single-key service maps.
  servicesYaml = map (g: {
    ${g.name} = map (s: {
      ${s.name} = prune {
        inherit (s) href description icon;
        siteMonitor = if s.siteMonitor != null then s.siteMonitor else s.href;
      };
    }) g.services;
  }) cfg.groups;

  # Per-group row layout (columns/style). Keys are group names.
  layout = lib.listToAttrs (map (g: {
    name = g.name;
    value = { style = "row"; columns = g.columns; };
  }) cfg.groups);
in
{
  options.my.service-dashboard = {
    enable = lib.mkEnableOption "Homepage service dashboard for homeserver services";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for the dashboard reverse proxy";
    };

    port = lib.mkOption {
      type = lib.types.port;
      # NB: 8082 is Traccar's (gps-backend) default web port — keep these apart.
      default = 8083;
      description = "Dashboard listen port (loopback only)";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };

    title = lib.mkOption {
      type = lib.types.str;
      default = "Home Server";
      description = "Dashboard page title";
    };

    groups = lib.mkOption {
      type = lib.types.listOf groupType;
      default = [];
      description = "Service tile groups, rendered in order.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;

      # Homepage rejects requests whose Host header is not allow-listed. Behind
      # Caddy the header is the public hostname (no port); keep loopback too so
      # local health checks/curl still work.
      allowedHosts = "${cfg.hostName},localhost:${toString cfg.port},127.0.0.1:${toString cfg.port}";

      settings = {
        inherit (cfg) title;
        theme = "dark";
        color = "slate";
        headerStyle = "clean";
        inherit layout;
      };

      # System info bar + quick search. No external API keys required.
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
            uptime = true;
          };
        }
        {
          search = {
            provider = "duckduckgo";
            target = "_blank";
          };
        }
      ];

      services = servicesYaml;
    };

    # Reverse proxy via Caddy, gated to the private networks (same shape as the
    # other internal-only services). TLS is issued through the global Cloudflare
    # DNS-01 issuer, so the cert works even though the name never resolves
    # publicly.
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
  };
}
