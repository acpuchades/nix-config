{
  config,
  lib,
  pkgs,
  ...
}:

# fugazi-web (github.com/acpuchades/fugazi-web) — a multi-user web service for
# live fugazi backtest stats. A React/Vite SPA served as static files by nginx,
# talking to a FastAPI backend (`uvicorn fugazi_service.api.app:app`) on
# loopback. Persistence is Postgres; outbound mail goes through the host's local
# Postfix relay. The SPA calls the API at same-origin `/v1/*` and `/health`, so
# nginx reverse-proxies those two prefixes to the backend and serves the built
# frontend for everything else (with SPA-history fallback to index.html).
#
# This module owns the HOST topology only — nginx, Postgres, the SMTP loopback
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
# Both are wired in machines/homeserver/fugazi.nix. The wheel pin, the
# npmDepsHash and the unit definitions are therefore maintained upstream, not
# here; bump them all by rolling the input: `nix flake update fugazi-web`.
#
# INSTANCES. Both this module and upstream's are keyed by instance name, and a
# name is the whole of an instance's identity: `fugazi-web-<name>.service`,
# `/var/lib/fugazi-web-<name>`, its own Postgres database and role, its own
# nginx vhost. Nothing is shared but the box. That is what lets a staging
# deployment tracking a different branch sit beside the public one — see
# `packages` below for how a branch actually gets in, and the flake.nix header
# for why there are two inputs rather than two imported modules.
#
# We deliberately do NOT re-expose every upstream knob. Anything this module
# doesn't set (`maintenanceInterval`, `deploymentTickFrequencies`, signup and
# maintenance-window vars via `environment`, …) is set directly on
# `services.fugazi-web.instances.<name>` in the host config.
#
# Upstream does not serve the SPA or terminate TLS (it removed its `enableNginx`
# branch), so the vhost below is the only one, and the flake's module header
# states what it owes: the real CSP, the security headers, the immutable-asset
# caching, the body cap and the edge `limit_req` zones. The in-process limiter
# still covers those routes too, and only correctly while `trustedProxies` is
# right, which is why it is set below.
#
# Wired per instance, not here: FUGAZI_SERVICE_SECRET_KEY, the Fernet key for the
# broker-credential vault. Without one the backend composes a NullVault — paper
# wallets are unaffected and connecting a real broker account fails loudly with a
# 503 instead of persisting a plaintext API secret. It reaches the service the
# same way the JWT key does, through `environmentFile`, so this module never sees
# it: add `fugazi-web/<instance>/secret-key` to the host's secrets and a second
# line to that instance's `fugazi-web/<instance>/env` template.
#   openssl rand -base64 32 | tr '+/' '-_'   # urlsafe-base64 32 bytes, not 48
# Per instance for a sharper reason than the JWT key's: the vault decrypts what
# was sealed with it, so one key across two deployments lets staging read the
# venue credentials of the deployment beside it. And unlike the JWT key, losing
# it is not recoverable by logging in again — every stored credential becomes
# undecryptable and each account has to re-enter its venue API secret.
#
# The gate in front of it is separate and stays: connecting a broker needs the
# `connect_brokers` entitlement, plus the per-venue one (`connect_okx`,
# `connect_coinbase`). `free` holds none of them, `pro`/`unlimited` hold brokers
# + coinbase, and the non-public `testing` tier holds all three — so wiring a key
# does not by itself open a venue to anybody.
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

  # The SPA this instance's nginx vhost serves. Falls back to the overlay's
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
        default = [ ];
        description = ''
          Additional names served by the same site block (legacy or vanity
          domains). They serve the app directly rather than redirecting, so
          bookmarks against an old name keep working. Each must be covered by a
          my.web-server.certificates wildcard — the vhost's TLS comes from the zone
          of `hostName`, so an alias in another zone gets the wrong certificate.
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
        default = "m.acpuchades.com";
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
        default = [ ];
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
        default = [
          "127.0.0.1/32"
          "::1/128"
        ];
        description = ''
          Peers whose X-Forwarded-For the backend may believe, and the hops it skips
          when walking that header right-to-left looking for the caller. Every
          rate-limit bucket on /v1/auth is keyed off the address that walk returns,
          so this list decides who shares a budget with whom.

          The default is the local nginx and nothing else, which is right whenever
          nginx is the only hop. When a CDN or edge proxy sits in front, its ranges
          belong here too: the rightmost hop is then the edge, and leaving it
          untrusted makes *it* the bucket, so every caller arriving through one
          edge node shares one budget. The opposite error costs more — listing a
          network that is not actually a proxy turns the header into unauthenticated
          input, and a caller mints a fresh bucket per request by writing one.
        '';
      };

      maxRequestBodySize = lib.mkOption {
        type = lib.types.str;
        default = "65m";
        description = ''
          nginx's cap on a request body (client_max_body_size). It has to sit at or above the backend's
          own transport ceiling, or the edge quietly becomes the real upload limit
          and a caller gets a connection cut instead of the parser's 413.

          That ceiling is the largest archive any tier may upload PLUS a megabyte
          of multipart headroom, because the body is the archive *plus* its
          multipart framing and the name/description/tags fields sent beside it. A
          cap equal to the archive size makes the largest legal archive
          unuploadable — the backend has its own constant for this, and this option
          exists to keep the edge from reintroducing the bug it fixes.

          nginx's `m` is binary (2^20), like every limit on the backend side, so
          `65m` is 65 MiB.
        '';
      };
    };
  };
in
{
  options.my.fugazi-web.instances = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instanceModule);
    default = { };
    description = ''
      fugazi-web deployments on this host, keyed by name. Defining an entry
      enables it. Each gets its own Postgres database and role, its own service
      user, its own `fugazi-web-<name>` units and state directory (upstream) and
      its own nginx vhost (here).

      Set `packages` on an instance to run a different branch of the fugazi-web
      repo in it; leave it null to run the same build as the imported module.
    '';
  };

  config = {
    assertions = lib.mapAttrsToList (name: i: {
      assertion =
        i.packages == null
        || builtins.all (k: i.packages ? ${k}) [
          "default"
          "maintenance"
          "deployment-tick"
          "frontend"
        ];
      message = ''
        my.fugazi-web.instances.${name}.packages must be a fugazi-web flake's whole
        `packages` output — it needs `default`, `maintenance`, `deployment-tick`
        and `frontend`. Got: ${lib.concatStringsSep ", " (builtins.attrNames i.packages)}.
      '';
    }) cfg.instances;

    # Upstream only auto-provisions a user when the name is left at its default;
    # we run as the role name instead so the Postgres connection can use peer auth,
    # which means creating it here.
    users.users = overInstances (
      _: i: {
        ${i.databaseName} = {
          isSystemUser = true;
          group = i.databaseName;
        };
      }
    );
    users.groups = overInstances (_: i: { ${i.databaseName} = { }; });

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
    # m.acpuchades.com resolves to loopback here, and the wildcard cert
    # (*.acpuchades.com) still validates on STARTTLS. Computed across all
    # instances rather than per instance — `networking.hosts.<ip>` is a list, so
    # emitting it once per instance would put the same name in it N times.
    networking.hosts = lib.mkIf (lib.any (i: i.smtpHost == "m.acpuchades.com") (
      lib.attrValues cfg.instances
    )) { "127.0.0.1" = [ "m.acpuchades.com" ]; };

    services.fugazi-web.instances = overInstances (
      name: i: {
        ${name} = {
          host = "127.0.0.1";
          inherit (i) port;
          user = i.databaseName;
          group = i.databaseName;
          # Peer auth over the Unix socket (the OS user == the Postgres role).
          databaseUrl = "postgresql+psycopg://${i.databaseName}@/${i.databaseName}?host=/run/postgresql";
          inherit (i) environmentFile;
          # Who may be believed about the caller's address (see the option). Without
          # it every request reads as coming from 127.0.0.1, which collapses all users
          # into ONE rate-limit bucket: the login/register/reset budgets are shared,
          # so one person fumbling a password locks everyone out.
          inherit (i) trustedProxies;
          # Reaches the API, the maintenance job and every deployment tick — the mail
          # settings matter to all three, since the outbox is drained from both the
          # API's in-process loop and the maintenance timer.
          environment = {
            # WHICH deployment this is, as opposed to what kind it is:
            # FUGAZI_SERVICE_ENVIRONMENT is "production" on every instance, so
            # without this the admin panel's badge falls back to a word that cannot
            # tell `testing` from a second instance beside it — which is exactly the
            # pair somebody has open in two tabs while changing a runtime control.
            #
            # Taken from the attribute name rather than asked for again: the name is
            # already the whole of an instance's identity here (the unit, the state
            # directory, the database and role, the nginx vhost), so a second
            # spelling would be one more thing to keep in step, and the badge could
            # end up contradicting the unit whose logs are open beside it.
            #
            # Upstream sets this same variable from the same name — but on a branch
            # whose MODULE this host does not import (see the `packages` option), and
            # on the API unit alone, the API being the only reader (`/v1/admin/status`
            # serves it). Keeping it here stays correct once the input catches up:
            # `environment` is `attrsOf str`, so two definitions of one key merge
            # while they are equal, and both are this same `name`. The whole cost of
            # the overlap is that the crons carry a variable nothing there opens.
            FUGAZI_SERVICE_INSTANCE_NAME = name;
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
      }
    );

    # Host-side additions to upstream's units. They order themselves after
    # postgresql.service, but on NixOS the database and role are created by
    # postgresql-setup.service — and the API runs Alembic to head on startup, so
    # it must not win that race on a first boot. `after`/`requires` are
    # list-merged with upstream's, not replaced.
    systemd.services = overInstances (
      name: _: {
        "fugazi-web-${name}" = {
          after = [
            "postgresql-setup.service"
            "postfix.service"
          ];
          requires = [ "postgresql-setup.service" ];
          serviceConfig = {
            RestartSec = 5;
            WorkingDirectory = "/var/lib/fugazi-web-${name}";
            # No hardening here: upstream applies one shared sandbox to all three
            # unit families (API, maintenance, every deployment tick) of every
            # instance — a seccomp filter, no AF_NETLINK, ProtectProc — and the
            # backend forks a native process pool for runs, so if a backtest or an
            # SMTP send starts failing after an input bump, look here first:
            # `journalctl -u fugazi-web-${name} | grep -i 'signal\|denied'`.
          };
        };
      }
    );

    # Edge rate limiting is the half `adapters/rate_limit` structurally cannot do:
    # it counts per process, so behind N workers an attacker gets N times the
    # budget and every deploy resets it — its own docstring asks for this.
    #
    # Two budgets per instance, keyed on the client address — the real visitor
    # when the host declares the CDN's edges in my.web-server.trustedProxies,
    # and the TCP peer otherwise. `/v1/auth` is the one that matters: register,
    # login and reset each burn an argon2 hash, so an unbudgeted one is a CPU
    # amplifier pointed at this box, and forgot-password also sends mail to an
    # address the caller names. The zones are exclusive because nginx picks one
    # location per request: an auth request spends the auth budget only.
    services.nginx.appendHttpConfig = lib.concatStrings (
      lib.mapAttrsToList (name: _: ''
        limit_req_zone $binary_remote_addr zone=fugazi_${name}_auth:10m rate=20r/m;
        limit_req_zone $binary_remote_addr zone=fugazi_${name}_api:10m rate=60r/s;
      '') cfg.instances
    );

    services.nginx.virtualHosts = overInstances (
      name: i:
      let
        backend = "http://127.0.0.1:${toString i.port}";
        # Repeated in every location that sets a header of its own: an
        # add_header there drops ALL of the server-level ones.
        securityHeaders = ''
          add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header X-Frame-Options "DENY" always;
          add_header Referrer-Policy "no-referrer" always;
          add_header Permissions-Policy "geolocation=(), camera=(), microphone=(), payment=()" always;
          add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
          ${lib.optionalString i.noIndex ''add_header X-Robots-Tag "noindex, nofollow" always;''}
        '';
      in
      {
        ${i.hostName} = {
          serverAliases = i.aliases;
          inherit (i) allowedNetworks;
          root = frontendOf i;

          # The SPA's real Content-Security-Policy. The build-time <meta> one
          # that Vite injects is a stopgap: a meta CSP cannot express
          # frame-ancestors at all, and has to allow any https connect-src. No
          # Sentry ingest origin (no DSN is compiled into our bundle — add it to
          # connect-src here if that changes, or the reports are blocked).
          #
          # 'unsafe-inline' on style-src is not slack: React writes style
          # attributes and recharts computes its layout that way, and there is no
          # nonce path for an attribute.
          #
          # 'wasm-unsafe-eval' and `data:` on connect-src are not slack either:
          # a served policy owes both or it breaks a shipped feature. @react-pdf
          # lays out through yoga-layout, an emscripten module carrying its
          # WebAssembly inlined as base64: it fetches that base64 as a `data:` URL
          # for `instantiateStreaming` and falls back to instantiating the buffer
          # it already holds. There is no .wasm request to allow and no script to
          # hash. Without the token every PDF report dies as `RuntimeError:
          # Aborted(CompileError: call to WebAssembly.instantiate() blocked by
          # CSP)`, which names neither the directive nor the dependency; without
          # `data:` the report still renders but leaves two CSP errors per run in
          # the console. 'wasm-unsafe-eval' admits WebAssembly and nothing else --
          # `eval` and `new Function` stay refused, which is why it exists apart
          # from 'unsafe-eval'. Keep this in step with SPA_CSP in
          # frontend/vite.config.ts.
          #
          # HSTS: the SPA keeps its session token in localStorage, so a single
          # plaintext request hands it to anyone on the path.
          #
          # client_max_body_size bounds an upload at the edge as well as in the
          # app. The app's own caps — per tier, with
          # FUGAZI_SERVICE_MAX_UPLOAD_BYTES as the backstop — are the real ones,
          # and they also cover a chunked body; this just stops a large one being
          # buffered here first. See the option for why it sits a megabyte above
          # the archive cap.
          extraConfig = ''
            ${securityHeaders}
            client_max_body_size ${i.maxRequestBodySize};
            limit_req_status 429;
          '';

          # burst = the budget a caller may spend back-to-back; nodelay serves
          # it at once instead of queueing, then the rate refills it.
          locations."/v1/auth/" = {
            proxyPass = backend;
            extraConfig = "limit_req zone=fugazi_${name}_auth burst=20 nodelay;";
          };
          locations."/v1/" = {
            proxyPass = backend;
            extraConfig = "limit_req zone=fugazi_${name}_api burst=60 nodelay;";
          };
          locations."= /health".proxyPass = backend;

          # Vite fingerprints everything under /assets, so it may be cached
          # forever; index.html must not be, or a deploy is invisible until the
          # browser gives up its copy.
          #
          # The bundle ships .gz siblings, served by recommendedGzipSettings'
          # `gzip_static on` (quality 9 at build beats a per-request level).
          # Its .br siblings go unused: brotli needs a third-party nginx module,
          # i.e. a locally compiled nginx. Cloudflare re-encodes to brotli for
          # visitors anyway; only LAN clients see gzip.
          locations."/assets/" = {
            tryFiles = "$uri =404";
            extraConfig = ''
              ${securityHeaders}
              add_header Cache-Control "public, max-age=31536000, immutable";
            '';
          };
          locations."/" = {
            tryFiles = "$uri /index.html";
            extraConfig = ''
              ${securityHeaders}
              add_header Cache-Control "no-cache";
            '';
          };
        };
      }
    );
  };
}
