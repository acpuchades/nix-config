{ config, lib, ... }:

# The public edge: nginx terminates TLS for every host, with certificates
# issued by lego (security.acme) over Cloudflare DNS-01 — one wildcard per
# zone, so private hostnames never reach the CT logs.
#
# Service modules write `services.nginx.virtualHosts.<name>` directly. This
# module extends that submodule so a vhost only states what is particular to
# it (its locations, and `allowedNetworks` if it is gated):
#
#   - a vhost whose name falls in one of `certificates` gets that wildcard
#     (`useACMEHost`) and `forceSSL` by default;
#   - `allowedNetworks` (an option added here) gates on the TCP PEER, not the
#     forwarded client: it is matched against $realip_remote_addr, which the
#     realip module never rewrites. A Cloudflare-proxied request to a LAN-only
#     host is therefore refused for coming from the edge, exactly as before,
#     and a vhost that admits the edges themselves (fugazi) still works.
#     Refused connections get 444 (closed, no response). Loopback always
#     passes: the host already reaches every gated vhost from its own LAN
#     address, and local probes (nextcloud-health) need the same through
#     127.0.0.1.
let
  cfg = config.my.web-server;
  nginxCfg = config.services.nginx;

  # The certificate whose wildcard covers `name`, or null.
  certFor =
    name:
    lib.findFirst (domain: name == domain || lib.hasSuffix ".${domain}" name) null (
      lib.attrNames cfg.certificates
    );

  # One geo variable per distinct network list, named by a hash of the list so
  # every vhost sharing a list shares the block.
  gateId =
    nets:
    builtins.substring 0 12 (builtins.hashString "sha256" (toString (lib.sort (a: b: a < b) nets)));
  gateVar = nets: "$peer_allowed_${gateId nets}";

  gatedLists = lib.unique (
    lib.filter (nets: nets != [ ]) (lib.mapAttrsToList (_: v: v.allowedNetworks) nginxCfg.virtualHosts)
  );

  # Rate-limit zone/variable names have to be nginx identifiers.
  sanitize = lib.replaceStrings [ "." "-" ] [ "_" "_" ];
in
{
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options.allowedNetworks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Source CIDRs (of the TCP peer) allowed to reach this vhost; others
              are dropped with 444. Empty = unrestricted. Added by
              modules/web-server.
            '';
          };

          config = lib.mkIf cfg.enable (
            lib.mkMerge [
              (lib.mkIf (certFor name != null) {
                useACMEHost = lib.mkDefault (certFor name);
                forceSSL = lib.mkDefault true;
              })
              (lib.mkIf (config.allowedNetworks != [ ]) {
                extraConfig = ''
                  if (${gateVar config.allowedNetworks} = 0) {
                    return 444;
                  }
                '';
              })
            ]
          );
        }
      )
    );
  };

  options.my.web-server = {
    enable = lib.mkEnableOption "nginx as the TLS-terminating public edge";

    adminEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact address for the ACME account.";
    };

    certificates = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.environmentFile = lib.mkOption {
            type = lib.types.path;
            description = "lego environment file with CF_DNS_API_TOKEN for this zone.";
          };
        }
      );
      default = { };
      example = {
        "example.com".environmentFile = "/run/secrets/acme-cloudflare-env";
      };
      description = ''
        Zones to issue a `<zone>` + `*.<zone>` certificate for (Cloudflare
        DNS-01). Every vhost named in a zone uses it automatically. The cert is
        group `acme`, which nginx joins; other consumers (Postfix) read it as
        root. Note the wildcard covers ONE label: `a.b.<zone>` is not served.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Source CIDRs (IPv4 and IPv6) the firewall accepts on 80/443; empty
        opens both ports to everyone. Unlike a vhost's allowedNetworks (an
        nginx-level 444), this drops the connection before TLS, so a source
        outside it never sees which certificates this host serves.
      '';
    };

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        CIDR ranges of reverse proxies (e.g. Cloudflare edges) whose
        X-Forwarded-For is trusted, making $remote_addr the real visitor for
        logging, rate limiting and the X-Real-IP / X-Forwarded-For handed to
        backends. `real_ip_recursive` walks the header right-to-left past
        these, so a client-supplied leftmost entry is never believed.
      '';
    };

    loginRateLimits = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              example = [ "/api/auth/login" ];
              description = "Login endpoints (POST only, exact paths) that share the budget.";
            };
            rate = lib.mkOption {
              type = lib.types.str;
              default = "10r/m";
              description = "Sustained refill rate, nginx `limit_req_zone` syntax (r/s or r/m).";
            };
            burst = lib.mkOption {
              type = lib.types.int;
              default = 10;
              description = "Attempts allowed back-to-back before the rate applies.";
            };
          };
        }
      );
      default = { };
      description = ''
        Per-vhost brute-force budget on login endpoints, keyed on the client
        address (see trustedProxies), for apps with no lockout of their own.
        Over budget is a 429. Applied in nginx rather than fail2ban because a
        firewall ban cannot reach the visitor behind a CDN — the packets come
        from the edge.
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

            redirect = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Permanent redirect target URL (request path and query are appended)";
            };
          };
        }
      );
      default = { };
      description = "Plain static sites and redirects, with HSTS.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = certFor name != null;
      message = "my.web-server.loginRateLimits.${name}: not in any my.web-server.certificates zone.";
    }) cfg.loginRateLimits;

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.allowedNetworks == [ ]) [
      80
      443
    ];

    # Source-restricted accepts (modules/firewall-allow), used instead of the
    # open ports above when allowedNetworks is set.
    my.firewall-allow.web = {
      networks = cfg.allowedNetworks;
      ports = [
        80
        443
      ];
    };

    security.acme = {
      acceptTerms = true;
      certs = lib.mapAttrs (zone: c: {
        domain = zone;
        extraDomainNames = [ "*.${zone}" ];
        email = lib.mkDefault cfg.adminEmail;
        dnsProvider = "cloudflare";
        inherit (c) environmentFile;
        group = "acme";
        # This host's own resolver (AdGuard) split-horizons these zones to the
        # LAN IP with no SOA for the apex, which breaks lego's zone detection
        # ("cloudflare: failed to find zone"). Ask a public resolver instead.
        dnsResolver = "1.1.1.1:53";
      }) cfg.certificates;
    };
    users.users.nginx.extraGroups = [ "acme" ];

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      # nginx's `if` + `return` gate and the rate-limit maps below need these
      # in http context, and so does realip (applies to every server).
      appendHttpConfig = lib.concatStringsSep "\n" (
        lib.optional (cfg.trustedProxies != [ ]) ''
          ${lib.concatMapStrings (net: "set_real_ip_from ${net};\n") cfg.trustedProxies}
          real_ip_header X-Forwarded-For;
          real_ip_recursive on;
        ''
        ++ map (nets: ''
          geo $realip_remote_addr ${gateVar nets} {
            default 0;
            127.0.0.0/8 1;
            ::1 1;
          ${lib.concatMapStrings (net: "  ${net} 1;\n") nets}}
        '') gatedLists
        ++ lib.mapAttrsToList (host: rl: ''
          map "$request_method $uri" $login_key_${sanitize host} {
            default "";
          ${lib.concatMapStrings (p: "  \"POST ${p}\" $binary_remote_addr;\n") rl.paths}}
          limit_req_zone $login_key_${sanitize host} zone=login_${sanitize host}:1m rate=${rl.rate};
        '') cfg.loginRateLimits
      );

      virtualHosts = lib.mkMerge [
        {
          # Anything not naming one of our hosts: no certificate, no response.
          # Without it the first vhost would answer for every SNI and Host.
          "_" = {
            default = true;
            rejectSSL = true;
            locations."/".return = "444";
          };
        }

        (lib.mapAttrs (host: rl: {
          extraConfig = ''
            limit_req zone=login_${sanitize host} burst=${toString rl.burst} nodelay;
            limit_req_status 429;
          '';
        }) cfg.loginRateLimits)

        (lib.mapAttrs (_: hostConfig: {
          inherit (hostConfig) root;
          # Every vhost here is TLS-only; pin that in the browser so one
          # plaintext hit can't strip the session.
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000" always;
          '';
          locations."/" = lib.mkIf (hostConfig.redirect != null) {
            return = "301 ${hostConfig.redirect}$request_uri";
          };
        }) cfg.virtualHosts)
      ];
    };
  };
}
