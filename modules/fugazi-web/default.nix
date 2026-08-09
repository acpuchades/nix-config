{ config, lib, pkgs, ... }:

# fugazi-web (github.com/acpuchades/fugazi-web) — a multi-user web service for
# live fugazi backtest stats. A React/Vite SPA served as static files by Caddy,
# talking to a FastAPI backend (`uvicorn fugazi_service.api.app:app`) on
# loopback. Persistence is Postgres; outbound mail goes through the host's local
# Postfix relay. The SPA calls the API at same-origin `/v1/*` and `/health`, so
# Caddy reverse-proxies those two prefixes to the backend and serves the built
# frontend for everything else (with SPA-history fallback to index.html).
#
# This module owns the DEPLOYMENT topology only. The packages come from the
# fugazi-web flake's overlay (applied in machines/homeserver/default.nix):
#   pkgs.fugazi-service       — the backend buildPythonPackage (built against our
#                               nixpkgs), incl. the fugazi PyPI wheel pin
#   pkgs.fugazi-web-frontend  — the built Vite SPA (buildNpmPackage + npmDepsHash)
# so the wheel pin and npmDepsHash are maintained upstream, not here. Bump both by
# rolling the input: `nix flake update fugazi-web`.
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
  python = pkgs.python313;

  # Backend + frontend from the fugazi-web flake overlay (see the header).
  pythonEnv = python.withPackages (_: [ pkgs.fugazi-service ]);
  frontend = pkgs.fugazi-web-frontend;

  serviceEnv = {
    # Peer auth over the Unix socket (the fugazi OS user == the fugazi role).
    FUGAZI_SERVICE_DATABASE_URL =
      "postgresql+psycopg://${cfg.databaseName}@/${cfg.databaseName}?host=/run/postgresql";
    FUGAZI_SERVICE_MAILER = "smtp";
    FUGAZI_SERVICE_SMTP_HOST = cfg.smtpHost;
    FUGAZI_SERVICE_SMTP_PORT = toString cfg.smtpPort;
    FUGAZI_SERVICE_MAIL_FROM = cfg.mailFrom;
    FUGAZI_SERVICE_REQUIRE_VERIFIED_EMAIL = if cfg.requireVerifiedEmail then "1" else "0";
    # Verification / reset links land on the SPA's public routes.
    FUGAZI_SERVICE_VERIFY_URL = "https://${cfg.hostName}/verify-email";
    FUGAZI_SERVICE_RESET_URL = "https://${cfg.hostName}/reset-password";
  };
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
        this must be a stable, out-of-store secret.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };
  };

  config = lib.mkIf cfg.enable {
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

    systemd.services.fugazi-web = {
      description = "fugazi-web backend (uvicorn)";
      after = [ "network.target" "postgresql-setup.service" "postfix.service" ];
      requires = [ "postgresql-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = serviceEnv;
      serviceConfig = {
        User = cfg.databaseName;
        Group = cfg.databaseName;
        EnvironmentFile = cfg.environmentFile;
        ExecStart =
          "${pythonEnv}/bin/uvicorn fugazi_service.api.app:app "
          + "--host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
        StateDirectory = "fugazi-web";
        WorkingDirectory = "/var/lib/fugazi-web";
        # Hardening (kept light: the backend forks a process pool for runs).
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
      };
    };

    services.caddy.virtualHosts.${cfg.hostName} = {
      serverAliases = cfg.aliases;

      extraConfig = ''
        ${lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}"}
        route {
          ${lib.optionalString (cfg.allowedNetworks != []) "abort @denied"}
          handle /v1/* {
            reverse_proxy 127.0.0.1:${toString cfg.port}
          }
          handle /health {
            reverse_proxy 127.0.0.1:${toString cfg.port}
          }
          handle {
            root * ${frontend}
            try_files {path} /index.html
            file_server
          }
        }
        encode gzip
      '';
    };
  };
}
