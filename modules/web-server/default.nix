{ config, lib, ... }:

{
  options.my.web-server = {
    enable = lib.mkEnableOption "Web server with SSL and reverse proxy";

    adminEmail = lib.mkOption {
      type = lib.types.str;
      description = "Admin email for ACME certificates";
    };

    # Caddy allows exactly ONE global `servers` block, so this module owns it
    # and other modules feed it through these two options instead of writing
    # their own services.caddy.globalConfig fragment (two fragments each
    # emitting `servers { }` is an adapter error, not a merge).
    serverMetrics = lib.mkEnableOption "per-server Caddy metrics collection";

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        CIDR ranges of reverse proxies (e.g. Cloudflare edges) whose
        X-Forwarded-For is trusted, making {client_ip} the real visitor
        for logging and rate limiting on proxied vhosts.
      '';
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          root = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Document root for static content";
          };

          proxyPass = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Proxy pass URL";
          };

          proxyWebsockets = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable websocket proxying";
          };

          redirect = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Permanent redirect target URL (request path and query are appended)";
          };

          basicAuthFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Basic auth file";
          };

          allowedNetworks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Restrict access to these CIDR ranges (empty = unrestricted)";
          };
        };
      });
      default = {};
      description = "Virtual hosts configuration";
    };
  };

  config = lib.mkIf config.my.web-server.enable {
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.caddy = {
      enable = true;
      email = config.my.web-server.adminEmail;

      # The admin API can read the full config (including basic-auth password
      # hashes) and POST a replacement — on the default 127.0.0.1:2019 that is
      # available to EVERY local account. A caddy-owned 0600 unix socket keeps
      # `caddy reload` working while shutting everyone else out. NOTE: on the
      # deploy that first applies this, the running caddy still listens on
      # 2019, so the reload cannot reach it — `systemctl restart caddy` once.
      globalConfig = ''
        admin unix//var/lib/caddy/admin.sock|0600
        ${lib.optionalString
          (config.my.web-server.serverMetrics || config.my.web-server.trustedProxies != []) ''
        servers {
          ${lib.optionalString config.my.web-server.serverMetrics "metrics"}
          ${lib.optionalString (config.my.web-server.trustedProxies != [])
            "trusted_proxies static ${lib.concatStringsSep " " config.my.web-server.trustedProxies}"}
        }''}
      '';

      virtualHosts = lib.mapAttrs (_name: hostConfig: {
        extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
          (lib.optionalString (hostConfig.allowedNetworks != [])
            "@denied not remote_ip ${lib.concatStringsSep " " hostConfig.allowedNetworks}\nabort @denied")
          # Every vhost here is TLS-only; pin that in the browser so one
          # plaintext hit can't strip the session.
          ''header Strict-Transport-Security "max-age=31536000"''
          (lib.optionalString (hostConfig.basicAuthFile != null)
            "import ${hostConfig.basicAuthFile}")
          (lib.optionalString (hostConfig.root != null)
            "root * ${hostConfig.root}\nfile_server")
          (lib.optionalString (hostConfig.proxyPass != null)
            "reverse_proxy ${hostConfig.proxyPass}")
          (lib.optionalString (hostConfig.redirect != null)
            "redir ${hostConfig.redirect}{uri} permanent")
          "encode gzip"
        ]);
      }) config.my.web-server.virtualHosts;
    };
  };
}
