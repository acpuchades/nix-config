{ config, lib, pkgs, ... }:

# fugazi-web (github.com/acpuchades/fugazi-web) — a multi-user web service for
# live fugazi backtest stats. A React/Vite SPA served as static files by Caddy,
# talking to a FastAPI backend (`uvicorn fugazi_service.api.app:app`) on
# loopback. Persistence is Postgres; outbound mail goes through the host's local
# Postfix relay. The SPA calls the API at same-origin `/v1/*` and `/health`, so
# Caddy reverse-proxies those two prefixes to the backend and serves the built
# frontend for everything else (with SPA-history fallback to index.html).
#
# NOTE: the fugazi-web repo is PRIVATE, so the machine building this config needs
# GitHub credentials reachable by the NIX DAEMON at fetch time. We fetch with the
# BUILT-IN `builtins.fetchTarball`, NOT `pkgs.fetchFromGitHub`, and that choice is
# load-bearing: only Nix's built-in fetchers consult `nix.settings.netrc-file` /
# `access-tokens`. `pkgs.fetchFromGitHub` runs its own curl inside a fixed-output
# build sandbox and that curl is NEVER handed a netrc (nixpkgs' fetchurl adds
# `--netrc-file` only when a `netrcPhase` attr is set, which fetchFromGitHub does
# not) — so against a private repo it 404s no matter what /etc/nix/netrc holds.
# fetchTarball authenticates via the daemon's netrc-file: a sops secret
# (github/token) rendered into a netrc that nix.settings.netrc-file points at —
# see machines/homeserver/{sops.nix,default.nix}. Because sops renders at
# ACTIVATION (after the build), the first switch that introduces it needs
# /etc/nix/netrc seeded by hand once; the machine default.nix note has the
# one-liner. The `sha256` is the hash of the UNPACKED tree (identical to what
# fetchFromGitHub's `hash` was); bump `rev`+`sha256` together to update.

let
  cfg = config.my.fugazi-web;
  python = pkgs.python313;

  src = builtins.fetchTarball {
    url = "https://github.com/acpuchades/fugazi-web/archive/16c327b2f927643efc50f66854ec8f98de75e2dc.tar.gz";
    sha256 = "sha256-oWjmVXRpxHDwrKicAXIoJJa1KtrzwzFM8LbpYe3SAuc=";
  };

  # fugazi is the Rust core's Python bindings (pyo3/abi3 wheel), published to
  # PyPI but not in nixpkgs. The abi3 manylinux x86_64 wheel runs on 3.13;
  # autoPatchelf fixes its rpath for the nix store.
  fugazi = python.pkgs.buildPythonPackage {
    pname = "fugazi";
    version = "0.31.1";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8e/e8/6e02b88ef852461fe20765db034902fb1f4a2be0a49f64d22e9d99a1832d/fugazi-0.31.1-cp39-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-wB6KaRbbL3v74RzagJYA86WUAxLWq61PSeX/xVK5O1U=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    pythonImportsCheck = [ "fugazi" ];
  };

  fugazi-service = python.pkgs.buildPythonPackage {
    pname = "fugazi-service";
    version = "0.0.1";
    pyproject = true;
    inherit src;
    build-system = [ python.pkgs.hatchling ];
    dependencies = with python.pkgs; [
      fugazi
      polars
      fastapi
      uvicorn
      # uvicorn[standard] runtime extras used in production
      uvloop
      httptools
      websockets
      pydantic
      email-validator # pydantic[email]
      argon2-cffi
      pyjwt
      httpx
      sqlalchemy
      alembic # DB schema migrations (added in 1e9e9f1)
      psycopg # psycopg[binary] → v3
      python-multipart
      pyyaml
    ];
    # Tests need live data providers / the fugazi engine; skip at build time.
    doCheck = false;
    pythonImportsCheck = [ "fugazi_service" ];
  };

  pythonEnv = python.withPackages (_: [ fugazi-service ]);

  # Static production bundle. Vite emits to ./dist; ship just that.
  frontend = pkgs.buildNpmPackage {
    pname = "fugazi-web-frontend";
    version = "0.0.1";
    # `src` is builtins.fetchTarball's already-unpacked tree — a store-path
    # STRING, not a derivation — so point straight at the frontend subdir
    # (`${src.name}` no longer works: a string has no `.name`).
    src = "${src}/frontend";
    npmDepsHash = "sha256-RgfAkz1oOEBTyxFGLvFxObXDYCIri281JramN2NbMEI=";
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

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
      description = "Virtual host for the SPA + API (e.g. fugazi.acpuchades.com)";
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

    services.caddy.virtualHosts.${cfg.hostName}.extraConfig = ''
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
}
