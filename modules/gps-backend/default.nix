{ config, lib, ... }:

#
# gps-backend — self-hosted GPS tracking backend.
#
# Wraps the upstream `services.traccar` module (Traccar) with:
#   - a PostgreSQL database/role reached over the local Unix socket with
#     peer authentication — no password, same model as the other services
#     on this host. Traccar's bundled pgjdbc driver cannot speak Unix
#     sockets on its own, so it is routed through the bundled junixsocket
#     library via pgjdbc's socketFactory.
#   - a Caddy reverse proxy for the web UI / API,
#   - a second Caddy listener that TLS-terminates the OsmAnd protocol
#     endpoint used by the Traccar Client mobile app. Traccar's own
#     protocol ports are plain HTTP, and modern mobile clients refuse
#     cleartext, so the app talks HTTPS to Caddy and Caddy proxies to a
#     loopback-only Traccar listener.
#
# The `$$` in the JDBC URL is intentional: the upstream module pipes the
# generated config through envsubst, which collapses `$$` to a literal `$`
# (needed for the AFUNIXSocketFactory$FactoryArg nested-class name). The
# `&amp;` keeps the generated config.xml well-formed.
#

let
  cfg = config.my.gps-backend;

  # PostgreSQL Unix socket on NixOS.
  pgSocket = "/run/postgresql/.s.PGSQL.5432";

  # Traccar's OsmAnd protocol listener. Bound to loopback and fronted by
  # Caddy, so it is never exposed directly. Kept clear of Traccar's own
  # protocol port range (~5000-5300) to avoid colliding with another decoder.
  osmAndBackendPort = 15055;
in
{
  options.my.gps-backend = {
    enable = lib.mkEnableOption "Self-hosted GPS tracking backend (Traccar)";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for the web UI / API and the OsmAnd endpoint";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Web UI / API port (bound to loopback, fronted by Caddy)";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Restrict web UI / API access to these CIDR ranges (empty =
        unrestricted). Does not apply to the OsmAnd endpoint, which must stay
        reachable for the Traccar Client app to report from anywhere.
      '';
    };

    osmAndPort = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = ''
        Public port on which Caddy serves the OsmAnd protocol endpoint over
        HTTPS, for the Traccar Client mobile app. Opened in the firewall;
        the router must forward it to this host. Caddy reuses the hostName
        TLS certificate and proxies to a loopback-only Traccar listener.
      '';
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "traccar";
        description = ''
          PostgreSQL database name. The role created for the backend shares
          this name; Traccar runs as a systemd DynamicUser of the same name
          and authenticates to Postgres by peer auth over the Unix socket.
        '';
      };
    };

    email = {
      from = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Sender address for notification emails. When null, no SMTP settings
          are written and Traccar e-mail is left unconfigured.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP server hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 25;
        description = "SMTP server port";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # PostgreSQL database + role. The role is created WITH LOGIN and no
    # password — Traccar connects over the Unix socket and is identified by
    # peer authentication (NixOS' default `local all all peer` hba line).
    services.postgresql = {
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.name;
          ensureDBOwnership = true;
        }
      ];
    };

    services.traccar = {
      enable = true;
      settings = {
        database = {
          driver = "org.postgresql.Driver";
          url = "jdbc:postgresql://localhost/${cfg.database.name}?socketFactory=org.newsclub.net.unix.AFUNIXSocketFactory$$FactoryArg&amp;socketFactoryArg=${pgSocket}";
          user = cfg.database.name;
        };
        web = {
          address = "127.0.0.1";
          port = toString cfg.port;
        };
        # OsmAnd protocol listener — loopback only; Caddy TLS-terminates it.
        osmand = {
          address = "127.0.0.1";
          port = toString osmAndBackendPort;
        };
      } // lib.optionalAttrs (cfg.email.from != null) {
        mail.smtp = {
          host = cfg.email.host;
          port = toString cfg.email.port;
          from = cfg.email.from;
        };
      };
    };

    # Traccar must not start until Postgres is up and its database/role have
    # been created (postgresql-setup pulls in postgresql.service).
    systemd.services.traccar = {
      after = [ "postgresql-setup.service" ];
      requires = [ "postgresql-setup.service" ];
    };

    # Public HTTPS port for the OsmAnd endpoint. The web UI rides on Caddy's
    # 80/443 (opened by the web-server module).
    networking.firewall.allowedTCPPorts = [ cfg.osmAndPort ];

    services.caddy.virtualHosts = {
      # Web UI / REST API.
      "${cfg.hostName}".extraConfig =
        lib.concatStringsSep "\n" (lib.filter (s: s != "") [
          (lib.optionalString (cfg.allowedNetworks != [])
            "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
          "reverse_proxy http://127.0.0.1:${toString cfg.port}"
          "encode gzip"
        ]);

      # OsmAnd protocol endpoint for the Traccar Client app, on its own port.
      # Always public — the app reports position from outside the network.
      "${cfg.hostName}:${toString cfg.osmAndPort}".extraConfig =
        "reverse_proxy http://127.0.0.1:${toString osmAndBackendPort}";
    };
  };
}
