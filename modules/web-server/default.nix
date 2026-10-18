{ config, lib, ... }:

let
  cfg = config.my.web-server;
in
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

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Source CIDRs (IPv4 and IPv6) the firewall accepts on 80/443; empty
        opens both ports to everyone. Unlike a vhost's allowedNetworks (a
        Caddy-level 403), this drops the connection before TLS, so a source
        outside it never sees which certificates this host serves.
      '';
    };

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        CIDR ranges of reverse proxies (e.g. Cloudflare edges) whose
        X-Forwarded-For is trusted, making {client_ip} the real visitor
        for logging and rate limiting on proxied vhosts.
      '';
    };

    loginRateLimits = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              example = [ "/api/auth/login" ];
              description = "Login endpoints (POST only) that share the budget.";
            };
            events = lib.mkOption {
              type = lib.types.int;
              default = 10;
              description = "Attempts allowed per client per window.";
            };
            window = lib.mkOption {
              type = lib.types.str;
              default = "1m";
              description = "Sliding window the budget refills over.";
            };
          };
        }
      );
      default = { };
      description = ''
        Per-vhost brute-force budget on login endpoints, keyed on {client_ip}
        (see trustedProxies), for apps with no lockout of their own. Applied
        in Caddy rather than fail2ban because a firewall ban cannot reach the
        visitor behind a CDN — the packets come from the edge.
      '';
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
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
              default = [ ];
              description = "Restrict access to these CIDR ranges (empty = unrestricted)";
            };
          };
        }
      );
      default = { };
      description = "Virtual hosts configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.allowedNetworks == [ ]) [
      80
      443
    ];

    # Source-restricted accepts, inserted at the head of nixos-fw like the
    # other per-service rules on this host. IPv6 ranges go to ip6tables —
    # iptables rejects them, and the v6 chain is otherwise closed.
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (
      net:
      "${
        if lib.hasInfix ":" net then "ip6tables" else "iptables"
      } -I nixos-fw -p tcp -s ${net} -m multiport --dports 80,443 -j nixos-fw-accept"
    ) cfg.allowedNetworks;

    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n" (
      net:
      "${
        if lib.hasInfix ":" net then "ip6tables" else "iptables"
      } -D nixos-fw -p tcp -s ${net} -m multiport --dports 80,443 -j nixos-fw-accept || true"
    ) cfg.allowedNetworks;

    services.caddy = {
      enable = true;
      email = cfg.adminEmail;

      # The admin API can read the full config (including basic-auth password
      # hashes) and POST a replacement — on the default 127.0.0.1:2019 that is
      # available to EVERY local account. A caddy-owned 0600 unix socket keeps
      # `caddy reload` working while shutting everyone else out. NOTE: on the
      # deploy that first applies this, the running caddy still listens on
      # 2019, so the reload cannot reach it — `systemctl restart caddy` once.
      # trusted_proxies_strict: by default Caddy takes the LEFTMOST
      # X-Forwarded-For entry, which is whatever the client sent — the CDN
      # appends to it, it does not replace it — so {client_ip} would be
      # attacker-chosen and every rate limit keyed on it bypassable. Strict
      # walks right-to-left past the trusted edges to the address the edge
      # itself saw.
      #
      # rate_limit is a plugin directive with no standard position; it must
      # run before basic_auth and the proxy, or a refused attempt would still
      # have been checked.
      globalConfig = ''
        admin unix//var/lib/caddy/admin.sock|0600
        ${lib.optionalString (cfg.loginRateLimits != { }) "order rate_limit before basic_auth"}
        ${lib.optionalString (cfg.serverMetrics || cfg.trustedProxies != [ ]) ''
          servers {
            ${lib.optionalString cfg.serverMetrics "metrics"}
            ${lib.optionalString (cfg.trustedProxies != [ ]) ''
              trusted_proxies static ${lib.concatStringsSep " " cfg.trustedProxies}
              trusted_proxies_strict''}
          }''}
      '';

      virtualHosts = lib.mkMerge [
        (lib.mapAttrs (_name: rl: {
          extraConfig = ''
            rate_limit {
              zone login {
                match {
                  method POST
                  path ${lib.concatStringsSep " " rl.paths}
                }
                key {client_ip}
                events ${toString rl.events}
                window ${rl.window}
              }
            }
          '';
        }) cfg.loginRateLimits)

        (lib.mapAttrs (_name: hostConfig: {
          extraConfig = lib.concatStringsSep "\n" (
            lib.filter (s: s != "") [
              (lib.optionalString (
                hostConfig.allowedNetworks != [ ]
              ) "@denied not remote_ip ${lib.concatStringsSep " " hostConfig.allowedNetworks}\nabort @denied")
              # Every vhost here is TLS-only; pin that in the browser so one
              # plaintext hit can't strip the session.
              ''header Strict-Transport-Security "max-age=31536000"''
              (lib.optionalString (hostConfig.basicAuthFile != null) "import ${hostConfig.basicAuthFile}")
              (lib.optionalString (hostConfig.root != null) "root * ${hostConfig.root}\nfile_server")
              (lib.optionalString (hostConfig.proxyPass != null) "reverse_proxy ${hostConfig.proxyPass}")
              (lib.optionalString (hostConfig.redirect != null) "redir ${hostConfig.redirect}{uri} permanent")
              "encode gzip"
            ]
          );
        }) cfg.virtualHosts)
      ];
    };

    my.caddy-plugins.plugins = lib.mkIf (cfg.loginRateLimits != { }) [
      "github.com/mholt/caddy-ratelimit@v0.1.0"
    ];
  };
}
