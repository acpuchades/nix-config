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
# and the sops-backed environment, once per instance. The service itself comes
# from upstream:
#   fugazi-web.nixosModules.default → `services.fugazi-web.instances.<name>`
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
# INSTANCES. Both this module and upstream's are keyed by instance name, and a
# name is the whole of an instance's identity: `fugazi-web-<name>.service`,
# `/var/lib/fugazi-web-<name>`, its own Postgres database and role, its own
# Caddy vhost. Nothing is shared but the box. That is what lets a staging
# deployment tracking a different branch sit beside the public one — see
# `packages` below for how a branch actually gets in, and the flake.nix header
# for why there are two inputs rather than two imported modules.
#
# We deliberately do NOT re-expose every upstream knob. Anything this module
# doesn't set (`maintenanceInterval`, `deploymentTickFrequencies`, signup and
# maintenance-window vars via `environment`, …) is set directly on
# `services.fugazi-web.instances.<name>` in the host config.
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
# The repo is PRIVATE, so fetching either flake input needs GitHub auth. They are
# tarball-URL inputs, not `github:` inputs, precisely because the `github:` fetcher
# resolves refs through api.github.com and authenticates only via the
# `access-tokens` setting (empty here) — it ignores netrc and 404s on a private
# repo. The tarball fetcher instead uses Nix's ordinary downloader, which consults
# `nix.settings.netrc-file` (unlike `pkgs.fetchFromGitHub`, whose sandboxed curl is
# never handed a netrc). Auth is a sops secret (github/token) rendered into that
# netrc. Flake-input fetching is CLIENT-side (and the `refs/heads/*` tarball URLs
# are unpinned by flake.lock, so they refetch on eval), which is why that netrc is
# rendered root:wheel 0440 rather than root-only — otherwise `nix flake update
# fugazi-web` and even a plain `nix eval` of the host 404 unless run as root. See
# flake.nix and machines/homeserver/{sops.nix,default.nix} for the bootstrap.

let
  cfg = config.my.fugazi-web;

  # One function per top-level attribute path, each applied to every instance and
  # merged under a *literal* key. Writing this the obvious way —
  # `config = mkMerge (mapAttrsToList mkInstance cfg.instances)` — makes this
  # module's config *keys* depend on `cfg.instances`, so the module system has to
  # force the very option it is computing. That is an infinite recursion reported
  # against `_module.freeformType`, with nothing in the trace pointing here.
  # Upstream's module is written this way for the same reason.
  overInstances = f: lib.mkMerge (lib.mapAttrsToList f cfg.instances);

  # The SPA this instance's Caddy vhost serves. Falls back to the overlay's
  # frontend — i.e. the build whose NixOS module was imported — when the instance
  # is not pinned to a second input.
  frontendOf = i: if i.packages == null then pkgs.fugazi-web-frontend else i.packages.frontend;

  instanceModule = { name, ... }: {
    options = {
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
        description = ''
          Loopback port this instance's uvicorn backend binds to. No default:
          upstream's is 8000 for every instance, so two instances collide unless
          each is told a port, and a port is not something to let a module guess
          when a firewall rule or a proxy config has to name it.
        '';
      };

      databaseName = lib.mkOption {
        type = lib.types.str;
        description = ''
          PostgreSQL database and role name — also the OS user the service runs
          as, which is what makes peer auth over the socket work (the three names
          have to agree).

          One per instance, never shared. Two instances on one database are two
          processes running Alembic to whichever head their own branch pins, and
          the one that starts second wins.
        '';
      };

      mailFrom = lib.mkOption {
        type = lib.types.str;
        default = "noreply@acpuchades.com";
        description = ''
          Envelope/From address for verification and password-reset mail. Worth
          differing per instance: it is the only thing distinguishing a staging
          deployment's mail from the real one in a recipient's inbox, and in a
          bounce report.
        '';
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
          this must be a stable, out-of-store secret. Shared by this instance's
          API, maintenance job and every deployment tick — and by nothing else:
          two instances holding the same JWT secret accept each other's session
          tokens, so an account on the staging deployment is an account on the
          public one.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.package);
        default = null;
        example = lib.literalExpression "fugazi-web-testing.packages.\${pkgs.stdenv.hostPlatform.system}";
        description = ''
          The build this instance runs, as a whole flake `packages` output —
          which is how an instance ends up on a different branch of the fugazi-web
          repo from the one whose NixOS module is imported.

          Pass the entire attrset rather than picking members out of it. Upstream
          takes four separate package options, and mixing branches across them is
          a backend serving routes the frontend does not call, with nothing wrong
          at build time; taking one attrset makes that unspellable. It must carry
          `default`, `maintenance`, `deployment-tick` and `frontend` (an
          assertion checks), which every version of that flake's `packages`
          output does.

          null — the default — runs the build whose module is imported: upstream's
          own package defaults for the units, and `pkgs.fugazi-web-frontend` from
          its overlay for the SPA.

          What this does NOT carry across is the module. Unit shape, the systemd
          sandbox and the option surface all come from the imported input, so an
          instance pinned here is running one branch's application under another
          branch's plumbing. That holds while a branch only changes the app, and
          it is the first thing to suspect when one that changes how the service
          is *launched* misbehaves.
        '';
      };

      allowedNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Restrict access to these CIDR ranges (empty = unrestricted)";
      };

      noIndex = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Serve `X-Robots-Tag: noindex, nofollow` on everything.

          For any instance that is reachable from the internet but is not the one
          users are meant to find. Two hostnames serving the same app otherwise
          compete for the same queries, and a crawler that finds the staging copy
          will index whatever half-finished state the branch is in. A header
          rather than a robots.txt because it covers the API responses too, and
          because it does not depend on a file surviving a frontend rebuild.
        '';
      };

      trustedProxies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "127.0.0.1/32" "::1/128" ];
        description = ''
          Peers whose X-Forwarded-For the backend may believe, and the hops it skips
          when walking that header right-to-left looking for the caller. Every
          rate-limit bucket on /v1/auth is keyed off the address that walk returns,
          so this list decides who shares a budget with whom.

          The default is the local Caddy and nothing else, which is right whenever
          Caddy is the only hop. When a CDN or edge proxy sits in front, its ranges
          belong here too: the rightmost hop is then the edge, and leaving it
          untrusted makes *it* the bucket, so every caller arriving through one
          edge node shares one budget. The opposite error costs more — listing a
          network that is not actually a proxy turns the header into unauthenticated
          input, and a caller mints a fresh bucket per request by writing one.
        '';
      };

      maxRequestBodySize = lib.mkOption {
        type = lib.types.str;
        default = "65MiB";
        description = ''
          Caddy's cap on a request body. It has to sit at or above the backend's
          own transport ceiling, or the edge quietly becomes the real upload limit
          and a caller gets a connection cut instead of the parser's 413.

          That ceiling is the largest archive any tier may upload PLUS a megabyte
          of multipart headroom, because the body is the archive *plus* its
          multipart framing and the name/description/tags fields sent beside it. A
          cap equal to the archive size makes the largest legal archive
          unuploadable — the backend has its own constant for this, and this option
          exists to keep the edge from reintroducing the bug it fixes.

          Mind the unit. Caddy reads `MB` as 10^6 and `MiB` as 2^20, while every
          limit on the backend side is binary: `64MB` is about 3 MiB SHORT of
          64 MiB. Spell it in MiB.
        '';
      };
    };
  };
in
{
  options.my.fugazi-web.instances = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instanceModule);
    default = {};
    description = ''
      fugazi-web deployments on this host, keyed by name. Defining an entry
      enables it. Each gets its own Postgres database and role, its own service
      user, its own `fugazi-web-<name>` units and state directory (upstream) and
      its own Caddy vhost (here).

      Set `packages` on an instance to run a different branch of the fugazi-web
      repo in it; leave it null to run the same build as the imported module.
    '';
  };

  config = {
    assertions = lib.mapAttrsToList (name: i: {
      assertion = i.packages == null
        || builtins.all (k: i.packages ? ${k}) [ "default" "maintenance" "deployment-tick" "frontend" ];
      message = ''
        my.fugazi-web.instances.${name}.packages must be a fugazi-web flake's whole
        `packages` output — it needs `default`, `maintenance`, `deployment-tick`
        and `frontend`. Got: ${lib.concatStringsSep ", " (builtins.attrNames i.packages)}.
      '';
    }) cfg.instances;

    # Upstream only auto-provisions a user when the name is left at its default;
    # we run as the role name instead so the Postgres connection can use peer auth,
    # which means creating it here.
    users.users = overInstances (_: i: {
      ${i.databaseName} = {
        isSystemUser = true;
        group = i.databaseName;
      };
    });
    users.groups = overInstances (_: i: { ${i.databaseName} = {}; });

    # DB + role, one per instance. The role is LOGIN with no password — the service
    # connects over the Unix socket and is identified by peer auth (default
    # `local all all peer`).
    services.postgresql = {
      ensureDatabases = lib.mapAttrsToList (_: i: i.databaseName) cfg.instances;
      ensureUsers = lib.mapAttrsToList (_: i: {
        name = i.databaseName;
        ensureDBOwnership = true;
      }) cfg.instances;
    };

    # Keep SMTP delivery local while satisfying the relay's TLS certificate:
    # mail.acpuchades.com resolves to loopback here, and the wildcard cert
    # (*.acpuchades.com) still validates on STARTTLS. Computed across all
    # instances rather than per instance — `networking.hosts.<ip>` is a list, so
    # emitting it once per instance would put the same name in it N times.
    networking.hosts = lib.mkIf
      (lib.any (i: i.smtpHost == "mail.acpuchades.com") (lib.attrValues cfg.instances))
      { "127.0.0.1" = [ "mail.acpuchades.com" ]; };

    services.fugazi-web.instances = overInstances (name: i: {
      ${name} = {
        host = "127.0.0.1";
        inherit (i) port;
        user = i.databaseName;
        group = i.databaseName;
        # Peer auth over the Unix socket (the OS user == the Postgres role).
        databaseUrl =
          "postgresql+psycopg://${i.databaseName}@/${i.databaseName}?host=/run/postgresql";
        environmentFile = i.environmentFile;
        # Who may be believed about the caller's address (see the option). Without
        # it every request reads as coming from 127.0.0.1, which collapses all users
        # into ONE rate-limit bucket: the login/register/reset budgets are shared,
        # so one person fumbling a password locks everyone out.
        inherit (i) trustedProxies;
        # Reaches the API, the maintenance job and every deployment tick — the mail
        # settings matter to all three, since the outbox is drained from both the
        # API's in-process loop and the maintenance timer.
        environment = {
          # Turns on the startup preflight (refuse to boot without a JWT secret, a
          # database URL or a real mailer — each of which otherwise fails silently)
          # and takes /docs, /redoc and /openapi.json off the air. All four
          # preflight conditions are satisfied here; it exists to keep them that
          # way, loudly, if one ever regresses. It is also what makes a branch
          # pinned through `packages` fail visibly rather than quietly when it
          # wants configuration the imported module cannot express.
          FUGAZI_SERVICE_ENVIRONMENT = "production";
          FUGAZI_SERVICE_MAILER = "smtp";
          FUGAZI_SERVICE_SMTP_HOST = i.smtpHost;
          FUGAZI_SERVICE_SMTP_PORT = toString i.smtpPort;
          FUGAZI_SERVICE_MAIL_FROM = i.mailFrom;
          FUGAZI_SERVICE_REQUIRE_VERIFIED_EMAIL = if i.requireVerifiedEmail then "1" else "0";
          # Verification / reset links land on the SPA's public routes.
          FUGAZI_SERVICE_VERIFY_URL = "https://${i.hostName}/verify-email";
          FUGAZI_SERVICE_RESET_URL = "https://${i.hostName}/reset-password";
        };
      }
      # All four together or none — see the `packages` option for why the whole
      # attrset is taken rather than four picks from it.
      // lib.optionalAttrs (i.packages != null) {
        package = i.packages.default;
        maintenancePackage = i.packages.maintenance;
        deploymentTickPackage = i.packages."deployment-tick";
        frontendPackage = i.packages.frontend;
      };
    });

    # Host-side additions to upstream's units. They order themselves after
    # postgresql.service, but on NixOS the database and role are created by
    # postgresql-setup.service — and the API runs Alembic to head on startup, so
    # it must not win that race on a first boot. `after`/`requires` are
    # list-merged with upstream's, not replaced.
    systemd.services = overInstances (name: _: {
      "fugazi-web-${name}" = {
        after = [ "postgresql-setup.service" "postfix.service" ];
        requires = [ "postgresql-setup.service" ];
        serviceConfig = {
          RestartSec = 5;
          WorkingDirectory = "/var/lib/fugazi-web-${name}";
          # No hardening here any more: upstream applies one shared sandbox to
          # all three unit families (API, maintenance, every deployment tick) of
          # every instance, which supersedes the two settings this used to add. It
          # is stricter than what ran before — a seccomp filter, no AF_NETLINK,
          # ProtectProc — and the backend forks a native process pool for runs, so
          # if a backtest or an SMTP send starts failing after an input bump, look
          # here first:
          # `journalctl -u fugazi-web-${name} | grep -i 'signal\|denied'`.
        };
      };
    });

    services.caddy.virtualHosts = overInstances (_: i: {
      ${i.hostName} = {
        serverAliases = i.aliases;

        extraConfig = ''
          ${lib.optionalString (i.allowedNetworks != [])
            "@denied not remote_ip ${lib.concatStringsSep " " i.allowedNetworks}"}
          # Vite fingerprints everything under /assets, so it may be cached
          # forever; index.html must not be, or a deploy is invisible until the
          # browser gives up its copy. Two matchers rather than two bare `header`
          # lines because directives inside a handle are sorted by Caddy's own
          # order, not the order written — mutually exclusive matchers make that
          # sort irrelevant.
          @assets path /assets/*
          @nocache not path /assets/*
          route {
            ${lib.optionalString (i.allowedNetworks != []) "abort @denied"}

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
              ${lib.optionalString i.noIndex ''X-Robots-Tag "noindex, nofollow"''}
            }

            # Bounds an upload at the edge as well as in the app. The app's own
            # caps — per tier, with FUGAZI_SERVICE_MAX_UPLOAD_BYTES as the backstop
            # — are the real ones, and they also cover a chunked body; this just
            # stops a large one being buffered here first. See the option for why
            # it sits a megabyte above the archive cap and why the unit is MiB.
            request_body {
              max_size ${i.maxRequestBodySize}
            }

            handle /v1/* {
              reverse_proxy 127.0.0.1:${toString i.port}
            }
            handle /health {
              reverse_proxy 127.0.0.1:${toString i.port}
            }
            handle {
              root * ${frontendOf i}
              header @assets Cache-Control "public, max-age=31536000, immutable"
              header @nocache Cache-Control "no-cache"
              try_files {path} /index.html
              file_server
            }
          }
          encode gzip
        '';
      };
    });
  };
}
