{ config, lib, pkgs, ... }:

# fugazi-web (github.com/acpuchades/fugazi-web) — a multi-user web service for
# live fugazi backtest stats. A React/Vite SPA served as static files by Caddy,
# talking to a FastAPI backend (`uvicorn fugazi_service.api.app:app`) on
# loopback. Persistence is Postgres; outbound mail goes through the host's local
# Postfix relay. The SPA calls the API at same-origin `/v1/*` and `/health`, so
# Caddy reverse-proxies those two prefixes to the backend and serves the built
# frontend for everything else (with SPA-history fallback to index.html).
#
# This module owns the HOST topology only — Caddy, Postgres, the SMTP loopback
# and the sops-backed environment. The service itself comes from upstream:
#   fugazi-web.nixosModules.default → `services.fugazi-web`
#     the uvicorn unit, the maintenance timer (purge expired verifications/2FA,
#     drain + prune the mail outbox) and one deployment-tick timer per trading
#     frequency (advance every live deployment on that cadence).
#   fugazi-web.overlays.default
#     pkgs.fugazi-service      — the backend buildPythonPackage (built against our
#                                nixpkgs), incl. the fugazi PyPI wheel pin
#     pkgs.fugazi-web-frontend — the built Vite SPA (buildNpmPackage + npmDepsHash)
# Both are wired in machines/homeserver/default.nix. The wheel pin, the
# npmDepsHash and the unit definitions are therefore maintained upstream, not
# here; bump them all by rolling the input: `nix flake update fugazi-web`.
#
# We deliberately do NOT re-expose every upstream knob through `my.fugazi-web`.
# Anything this module doesn't set (`maintenanceInterval`,
# `deploymentTickFrequencies`, signup/maintenance-window vars via `environment`,
# …) is set directly on `services.fugazi-web` in the host config.
#
# Not used, on purpose: upstream's `enableNginx`. It serves the SPA, terminates
# TLS and adds the response CSP + edge rate limiting — but this host's :443 is
# Caddy's, so the two would fight over the port. The parts of it that are policy
# rather than plumbing (the real CSP, the security headers, the immutable-asset
# caching, the body cap) are replicated in the Caddy vhost below; the one part
# that isn't is nginx's `limit_req` zones, which have no built-in Caddy
# equivalent (they'd need the caddy-ratelimit plugin, and so another hash to pin
# — see modules/acme-cloudflare). The in-process limiter covers those routes as
# long as `trustedProxies` is right, which is why it is set below.
#
# Not wired, on purpose: FUGAZI_SERVICE_SECRET_KEY, the Fernet key for the
# broker-credential vault. Without it the backend composes a NullVault — paper
# wallets are unaffected and connecting a real broker account fails loudly
# instead of persisting a plaintext API secret. Enabling it means a new sops
# secret, so it stays out until a broker account is actually needed:
#   openssl rand -base64 32 | tr '+/' '-_'   # urlsafe-base64 32 bytes
# then add `fugazi/secret-key` to machines/homeserver/secrets/default.yml and a
# second line to the `fugazi/env` template in sops.nix.
#
# The repo is PRIVATE, so fetching the flake input needs GitHub auth. It's a
# tarball-URL input, not a `github:` input, precisely because the `github:` fetcher
# resolves refs through api.github.com and authenticates only via the
# `access-tokens` setting (empty here) — it ignores netrc and 404s on a private
# repo. The tarball fetcher instead uses Nix's ordinary downloader, which consults
# `nix.settings.netrc-file` (unlike `pkgs.fetchFromGitHub`, whose sandboxed curl is
# never handed a netrc). Auth is a sops secret (github/token) rendered into that
# netrc. Flake-input fetching is client-side, and that netrc is root-only, so run
# `sudo nixos-rebuild switch` / `sudo nix flake update fugazi-web` as ROOT (which
# can read it); a non-root update 404s unless you pass an override
# (`--option access-tokens github.com=<PAT>`). See flake.nix and
# machines/homeserver/{sops.nix,default.nix} for the bootstrap.

let
  cfg = config.my.fugazi-web;

  frontend = pkgs.fugazi-web-frontend;
in
{
  options.my.fugazi-web = {
    enable = lib.mkEnableOption "fugazi-web backtest service";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Canonical virtual host for the SPA + API (e.g. www.fugazitrade.com).
        This name is baked into the verification / password-reset links the
        backend mails out, so changing it changes what users get sent.
      '';
    };

    aliases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Additional names served by the same site block (legacy or vanity
        domains). They serve the app directly rather than redirecting, so
        bookmarks against an old name keep working. Each still needs its own
        certificate, which Caddy gets over DNS-01 — so every name here must live
        in a zone the Cloudflare API token can write to.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = "Loopback port the uvicorn backend binds to";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "fugazi";
      description = "PostgreSQL database and role name (also the service user, for peer auth)";
    };

    mailFrom = lib.mkOption {
      type = lib.types.str;
      default = "noreply@acpuchades.com";
      description = "Envelope/From address for verification and password-reset mail";
    };

    smtpHost = lib.mkOption {
      type = lib.types.str;
      default = "mail.acpuchades.com";
      description = ''
        SMTP smarthost. The backend always STARTTLSes with certificate
        verification, so this must match the relay's certificate. Defaults to the
        host's own Postfix (which relays onward via Mailjet); the loopback
        hosts-entry below points this name at 127.0.0.1 so the connection stays
        local while the wildcard cert still validates.
      '';
    };

    smtpPort = lib.mkOption {
      type = lib.types.port;
      default = 25;
      description = "SMTP port on smtpHost";
    };

    requireVerifiedEmail = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require users to verify their email before they can use the service";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        systemd EnvironmentFile providing FUGAZI_SERVICE_JWT_SECRET (the JWT
        signing key). A restart with a fresh secret invalidates every session, so
        this must be a stable, out-of-store secret. Shared by the API, the
        maintenance job and every deployment tick.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Upstream only provisions its own default `fugazi-web` user/group; we run as
    # the role name instead so the Postgres connection can use peer auth.
    users.users.${cfg.databaseName} = {
      isSystemUser = true;
      group = cfg.databaseName;
    };
    users.groups.${cfg.databaseName} = {};

    # DB + role. The role is LOGIN with no password — the service connects over
    # the Unix socket and is identified by peer auth (default `local all all peer`).
    services.postgresql = {
      ensureDatabases = [ cfg.databaseName ];
      ensureUsers = [
        {
          name = cfg.databaseName;
          ensureDBOwnership = true;
        }
      ];
    };

    # Keep SMTP delivery local while satisfying the relay's TLS certificate:
    # mail.acpuchades.com resolves to loopback here, and the wildcard cert
    # (*.acpuchades.com) still validates on STARTTLS.
    networking.hosts = lib.mkIf (cfg.smtpHost == "mail.acpuchades.com") {
      "127.0.0.1" = [ "mail.acpuchades.com" ];
    };

    services.fugazi-web = {
      enable = true;
      host = "127.0.0.1";
      inherit (cfg) port;
      user = cfg.databaseName;
      group = cfg.databaseName;
      # Peer auth over the Unix socket (the fugazi OS user == the fugazi role).
      databaseUrl =
        "postgresql+psycopg://${cfg.databaseName}@/${cfg.databaseName}?host=/run/postgresql";
      environmentFile = cfg.environmentFile;
      # Caddy is the only thing that ever talks to the backend, and it does so
      # over loopback — so loopback is exactly the peer whose X-Forwarded-For may
      # be believed, and nothing wider. Without this every request reads as
      # coming from 127.0.0.1, which collapses all users into ONE rate-limit
      # bucket: the 10r/m budget on login/register/reset is shared, so one person
      # fumbling a password locks everyone out. Set wider than the proxy and the
      # header becomes unauthenticated input (a fresh bucket per request).
      trustedProxies = [ "127.0.0.1/32" "::1/128" ];
      # Reaches the API, the maintenance job and every deployment tick — the mail
      # settings matter to all three, since the outbox is drained from both the
      # API's in-process loop and the maintenance timer.
      environment = {
        # Turns on the startup preflight (refuse to boot without a JWT secret, a
        # database URL or a real mailer — each of which otherwise fails silently)
        # and takes /docs, /redoc and /openapi.json off the air. All four
        # preflight conditions are satisfied here; it exists to keep them that
        # way, loudly, if one ever regresses.
        FUGAZI_SERVICE_ENVIRONMENT = "production";
        FUGAZI_SERVICE_MAILER = "smtp";
        FUGAZI_SERVICE_SMTP_HOST = cfg.smtpHost;
        FUGAZI_SERVICE_SMTP_PORT = toString cfg.smtpPort;
        FUGAZI_SERVICE_MAIL_FROM = cfg.mailFrom;
        FUGAZI_SERVICE_REQUIRE_VERIFIED_EMAIL = if cfg.requireVerifiedEmail then "1" else "0";
        # Verification / reset links land on the SPA's public routes.
        FUGAZI_SERVICE_VERIFY_URL = "https://${cfg.hostName}/verify-email";
        FUGAZI_SERVICE_RESET_URL = "https://${cfg.hostName}/reset-password";
      };
    };

    # Host-side additions to upstream's unit. It orders itself after
    # postgresql.service, but on NixOS the database and role are created by
    # postgresql-setup.service — and the API runs Alembic to head on startup, so
    # it must not win that race on a first boot. `after`/`requires` are
    # list-merged with upstream's, not replaced.
    systemd.services.fugazi-web = {
      after = [ "postgresql-setup.service" "postfix.service" ];
      requires = [ "postgresql-setup.service" ];
      serviceConfig = {
        RestartSec = 5;
        WorkingDirectory = "/var/lib/fugazi-web";
        # No hardening here any more: upstream now applies one shared sandbox to
        # all three unit families (API, maintenance, every deployment tick),
        # which supersedes the two settings this used to add. It is stricter than
        # what ran before — a seccomp filter, no AF_NETLINK, ProtectProc — and
        # the backend forks a native process pool for runs, so if a backtest or
        # an SMTP send starts failing after an input bump, look here first:
        # `journalctl -u fugazi-web | grep -i 'signal\|denied'`.
      };
    };

    services.caddy.virtualHosts.${cfg.hostName} = {
      serverAliases = cfg.aliases;

      extraConfig = ''
        ${lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}"}
        # Vite fingerprints everything under /assets, so it may be cached
        # forever; index.html must not be, or a deploy is invisible until the
        # browser gives up its copy. Two matchers rather than two bare `header`
        # lines because directives inside a handle are sorted by Caddy's own
        # order, not the order written — mutually exclusive matchers make that
        # sort irrelevant.
        @assets path /assets/*
        @nocache not path /assets/*
        route {
          ${lib.optionalString (cfg.allowedNetworks != []) "abort @denied"}

          # The SPA's real Content-Security-Policy. The build-time <meta> one
          # that Vite injects is a stopgap: a meta CSP cannot express
          # frame-ancestors at all, and has to allow any https connect-src. This
          # is the same policy upstream's `enableNginx` branch serves, minus the
          # Sentry ingest origin (no DSN is compiled into our bundle — add it to
          # connect-src here if that changes, or the reports are blocked).
          #
          # 'unsafe-inline' on style-src is not slack: React writes style
          # attributes and recharts computes its layout that way, and there is no
          # nonce path for an attribute.
          header {
            Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "DENY"
            Referrer-Policy "no-referrer"
            Permissions-Policy "geolocation=(), camera=(), microphone=(), payment=()"
            # The SPA keeps its session token in localStorage, so a single
            # plaintext request hands it to anyone on the path.
            Strict-Transport-Security "max-age=63072000; includeSubDomains"
          }

          # Bounds an upload at the edge as well as in the app. The app's own cap
          # (FUGAZI_SERVICE_MAX_UPLOAD_BYTES, 64 MiB) is the real one — it also
          # covers a chunked body — this just stops a large one being buffered
          # here first.
          request_body {
            max_size 64MB
          }

          handle /v1/* {
            reverse_proxy 127.0.0.1:${toString cfg.port}
          }
          handle /health {
            reverse_proxy 127.0.0.1:${toString cfg.port}
          }
          handle {
            root * ${frontend}
            header @assets Cache-Control "public, max-age=31536000, immutable"
            header @nocache Cache-Control "no-cache"
            try_files {path} /index.html
            file_server
          }
        }
        encode gzip
      '';
    };
  };
}
