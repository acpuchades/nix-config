# fugazi-web — the homeserver's backtest service (testing.fugazitrade.com).
#
# Split out of ./default.nix, which it had grown to roughly half of: ~470 lines
# of policy helpers in the `let` block plus ~280 of instance configuration, for
# ONE service among thirty. Everything here is fugazi-specific and nothing else
# on this host reads any of it, so the split costs no cross-references —
# `cloudflareNetworks` came along because fugazitrade.com is the only name here
# behind a CDN.
#
# Curried over the flake inputs rather than taking them from `_module.args`,
# because `imports` below needs `fugazi-web` and a module argument used in
# `imports` is an infinite recursion. Same pattern as
# modules/emacs-core/system.nix at the bottom of ./default.nix.
#
# STAYS IN default.nix, deliberately:
#   * the sops secrets and templates (machines/homeserver/sops.nix) — one place
#     to answer "what secrets does this host hold" beats proximity
#   * the `my.ntfy-alert.units` entries naming the fugazi units — that list is a
#     host-level statement of what gets alerted on, and reads as one thing
#   * nixpkgs.overlays keeps the caddy entry; this file contributes its own
#
{ fugazi-web, fugazi-web-testing }:

{ config, lib, pkgs, ... }:

let
  # Cloudflare's published edge ranges (cloudflare.com/ips-v4 + ips-v6, fetched
  # 2026-08-18). fugazitrade.com is proxied through Cloudflare — its public A
  # records are CF anycast addresses — so these, not the visitor, are the peers
  # Caddy sees, and they are the hops the backend has to skip to find the real
  # caller. Used only by my.fugazi-web.trustedProxies below; nothing else on this
  # host is fronted by a CDN. Cloudflare changes the list rarely and announces it;
  # re-fetch if public callers start sharing a rate-limit bucket.
  cloudflareNetworks = [
    "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
    "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
    "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
    "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
    "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
    "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32"
  ];

  # Every cadence a venue this service fetches from actually publishes — the union
  # of Binance's, OKX's and Coinbase's candle intervals, which is the same closed
  # list the SPA offers when composing a dataset (`TRADING_CADENCES` in
  # frontend/src/frequencies.ts). Fine to coarse, because a list is served to the
  # deployment picker in the order it is written and the SPA does not sort it (which
  # is also why this is a LIST — `lib.attrNames` would file "15m" before "1d" and put
  # "4h" last, an order that reads as nothing).
  #
  # Every entry carries the systemd cadence its timer would run on, including the
  # two no kind enables today. What makes a cadence available IS a timer, so writing
  # the whole table once means offering a finer one later is moving a floor rather
  # than inventing an OnCalendar under time pressure.
  fugaziAvailableCadences = [
    { freq = "1m"; onCalendar = "minutely"; }
    { freq = "3m"; onCalendar = "*:0/3"; }
    { freq = "5m"; onCalendar = "*:0/5"; }
    { freq = "15m"; onCalendar = "*:0/15"; }
    { freq = "30m"; onCalendar = "*:0/30"; }
    { freq = "1h"; onCalendar = "hourly"; }
    { freq = "2h"; onCalendar = "0/2:00"; }
    { freq = "4h"; onCalendar = "0/4:00"; }
    { freq = "6h"; onCalendar = "0/6:00"; }
    { freq = "8h"; onCalendar = "0/8:00"; }
    { freq = "12h"; onCalendar = "0/12:00"; }
    { freq = "1d"; onCalendar = "daily"; }
    # Every third day OF THE MONTH, not every third day: systemd steps day-of-month,
    # so the sequence restarts at each month boundary (…, 28, 31, then the 1st).
    # Every gap that produces is three days or SHORTER, so the error is an extra tick
    # that finds no closed bar rather than a bar nobody traded — the direction to be
    # wrong in, and the reason this is not written as a 72-hour OnUnitActiveSec.
    { freq = "3d"; onCalendar = "*-*-01/3"; }
    { freq = "1w"; onCalendar = "weekly"; }
    { freq = "1M"; onCalendar = "monthly"; }
  ];

  # The finest cadence a KIND schedules — everything from here up is enabled, since
  # the table above is ordered. Said as a token rather than a number of seconds so
  # it reads as one of the entries it selects.
  #
  # `1m` for staging, moved down from `5m` on 2026-08-30. It was held at `5m` on the
  # grounds that at 1440 and 480 ticks a day the tick would be starting again as
  # often as it finishes — which was true of a process that pays a fresh start every
  # bar, and is the measurement that had to come first. It has: a 5m tick ran
  # 1.26-1.77s wall and 828ms CPU to advance one deployment, of which ~0.53s was the
  # interpreter and fugazi import. What retires the objection is not the number but
  # the driver — `deploymentTickResident` below puts 1m, 3m and 5m on long-running
  # units that pay that start once instead of 1440 times, so the three finest
  # cadences no longer start a process per bar at all. Coarser ones keep their
  # timers, where a start amortised over an hour is not worth a resident process.
  #
  # Still a cost, and still the operator's own: each of these is a venue round trip
  # and a wallet resume per live deployment, on a box also running bitcoind,
  # Postgres, Nextcloud and the agents. What keeps it that way is the
  # `sub_hourly_cadence` gate below, which no tier on sale holds.
  #
  # `1h` for prod, and deliberately not inherited from staging: what a PLAN may tick
  # at is a pricing decision with a cost attached, and launch day is not the morning
  # to discover it was made by a default here.
  fugaziTickFloor = kind: if kind == "prod" then "1h" else "1m";

  # The cadences a kind schedules: the available table from its floor upward.
  #
  # This is one fact answering two questions that must not be allowed to disagree —
  # which timers exist (`deploymentTickFrequencies` on the instance below) and which
  # cadences the API will let a deployment be CREATED on
  # (FUGAZI_SERVICE_DEPLOYMENT_FREQUENCIES, derived in fugaziEnvironment). The cron
  # matches a deployment to a run by EXACT frequency equality, so a cadence offered
  # without a timer behind it saves, reads as RUNNING and is then never advanced: no
  # error, ever, and an empty ledger for as long as anybody leaves it there. An
  # assertion below re-checks that the two still agree, since deriving both from one
  # list only helps until somebody sets one of them by hand.
  fugaziTickCadences = kind:
    let
      floor = fugaziTickFloor kind;
      index = lib.lists.findFirstIndex (c: c.freq == floor)
        (throw "fugaziTickFloor: ${floor} is not in fugaziAvailableCadences")
        fugaziAvailableCadences;
    in
    lib.drop index fugaziAvailableCadences;

  # The same table in the shape upstream's option wants: frequency → OnCalendar.
  fugaziTickFrequencies = kind:
    lib.listToAttrs
      (map (c: lib.nameValuePair c.freq c.onCalendar) (fugaziTickCadences kind));

  # fugazi-web's policy surface, as ONE table with a column per deployment KIND.
  # Both columns are written here even though only `testing` is instantiated
  # below, and that is the point of the shape: the alternative is a prod column
  # invented in a hurry on launch day, beside a testing column whose reasoning
  # nobody remembers. `kind` is the deployment's character, not the instance's
  # name — what separates the two is who is let in, how much of this box they may
  # spend, and how much is on show.
  #
  # Only POLICY lives here. Everything modules/fugazi-web already derives per
  # instance — ENVIRONMENT, MAILER, SMTP_*, MAIL_FROM, REQUIRE_VERIFIED_EMAIL,
  # VERIFY_URL, RESET_URL, DATABASE_URL, TRUSTED_PROXIES — is set there and must
  # not be repeated: `environment` is an attrsOf, so a duplicate key would
  # silently outrank the module's derivation rather than conflict with it.
  #
  # Secrets are not here either, for the obvious reason. FUGAZI_SERVICE_JWT_SECRET
  # and FUGAZI_SERVICE_SECRET_KEY arrive through the instance's EnvironmentFile
  # (the sops template at fugazi-web/<instance>/env), which systemd reads without
  # the values ever reaching the store.
  #
  # Deliberately UNSET, each with its reason — an absent knob is a decision too,
  # and the ones below are the knobs somebody will otherwise re-litigate:
  #   HSTS               Caddy already sends Strict-Transport-Security on this
  #                      vhost (max-age=63072000; includeSubDomains). Two sources
  #                      for one header is one too many.
  #   MAX_BODY_BYTES     upstream's 2 MiB covers every non-upload body; the upload
  #                      path has its own ceiling below.
  #   MAINTENANCE_MODE   a RUNTIME lever (/admin). A value here is the thing an
  #                      operator ends up fighting during the incident it was
  #                      meant to help with.
  #   MAINTENANCE_WINDOWS  no recurring downtime: pg_dump is transactionally
  #                      consistent, so the nightly backup needs no read-only
  #                      window to be correct. Format if one is ever wanted, and
  #                      it is UTC because a window in a local zone moves twice a
  #                      year: "sun 03:00-04:00, wed 01:00-01:30".
  #   DISABLED_FEATURES  same reason as MAINTENANCE_MODE — /admin owns it.
  #   INVITE_CODES       the bootstrap hatch for an instance with no accounts and
  #                      no administrator. Neither column needs it today; add one
  #                      (with SIGNUP_MODE = "invite") the afternoon open signup
  #                      starts getting abused.
  #   SENTRY_DSN         no Sentry project. Worth knowing before wiring one: the
  #                      module pins ENVIRONMENT to "production" for BOTH kinds
  #                      because it is upstream's preflight switch rather than a
  #                      label, and Sentry reads that same variable — so staging
  #                      events would arrive tagged "production".
  #   LOG_FORMAT         text, not json. This lands in journald and is read with
  #                      journalctl.
  fugaziEnvironment = kind:
    let
      isProd = kind == "prod";
      mib = n: toString (n * 1024 * 1024);
    in
    {
      # --- who may create an account -------------------------------------
      # Both kinds run upstream's "open" mode; what differs is the gate behind
      # it (the domain allow-list, below, which prod does not set). An
      # administrator can move this from /admin at runtime — it is one of the
      # five controls that must not wait for a rebuild — so if signup stops
      # behaving like this line says, look at /admin before looking at git.
      FUGAZI_SERVICE_SIGNUP_MODE = "open";

      # --- who administers it --------------------------------------------
      # Keyed on the USERNAME, comma-separated, lowercased with a leading `@`
      # stripped — the handle `fugazi`, not an address.
      #
      # It GRANTS AND NEVER REVOKES, which is where it differs from the tier
      # assignment below. It names a set rather than an authority: treating it
      # as authoritative would silently demote, on the next restart, everyone
      # promoted through the panel. Nothing is written to the database by
      # setting it — the role appears on the next start, disappears if this line
      # goes, and the panel refuses to demote a name listed here on the grounds
      # that clearing the column would change nothing. This is how the first
      # administrator exists on a database that has none; after that the panel
      # is how the role moves.
      #
      # It does NOT create the account. On a fresh database the handle has to be
      # registered like anybody's, through the same signup gate and the same
      # mail verification, and it becomes an administrator on the next start.
      #
      # An API key is refused at /v1/admin even with write scope — the account's
      # own key would otherwise be a way to do at one remove what the key is not
      # allowed to do directly. Administration is a session, in a browser.
      FUGAZI_SERVICE_ADMINS = "fugazi";

      # --- what an account may spend ---------------------------------------
      # Spelled even though it is upstream's default, because it is the one that
      # decides what a STRANGER gets and reading it out of the source is not the
      # same as having decided it.
      FUGAZI_SERVICE_DEFAULT_TIER = "free";

      # The instance's own account on the `testing` TIER — upstream's name for a
      # non-public plan, and nothing to do with the instance also called testing.
      # Non-public means exactly one thing: the tier is never *named* to a user,
      # so an entitlement refusal cannot invite a stranger onto a plan nobody can
      # buy. Its ceilings are `unlimited`'s (none); what it adds is the venue
      # gates, and `connect_okx` is held by it and by nothing on sale, because
      # how far a venue's live path has been exercised here is a different claim
      # from what a plan costs and only the second is `unlimited`'s to make.
      #
      # Deliberately the OVERRIDE channel rather than the `users.tier` column:
      # upstream deleted the revision that wrote that column precisely because
      # who is on an internal tier is a property of this instance, not of the
      # service — the same handle belongs to a stranger on somebody else's
      # deployment. Configuration outranks the column, so this line is the whole
      # of the assignment and no migration is involved. Matched
      # case-insensitively on the username.
      FUGAZI_SERVICE_TIER_ASSIGNMENTS = "fugazi:testing";

      # --- ceilings on the process, shared by everybody ---------------------
      # A backtest is an OS process holding a multi-megabyte bar array, and the
      # pool defaults to one worker per core — 16 here, on a box also running
      # bitcoind, Jellyfin, Nextcloud, Postgres and the agents. The split is the
      # reason the two columns exist at all: a sweep someone is trying out on a
      # branch must not take the pool away from the deployment with users on it.
      #
      # These were 4/2, and 2 was the wrong instrument for the goal. A hard cap
      # surrenders the box PERMANENTLY — including at 03:00 when bitcoind is
      # idle and nothing else wants a core — whereas a cgroup weight is
      # work-conserving: it binds only under contention. The slice now carries
      # that weight (`services.fugazi-web.resources`, below), so the cap can go
      # back to being about the pool rather than about the neighbours. 6 is one
      # worker per PHYSICAL core less two (8C/16T here, and BLAS is pinned to a
      # single thread per worker, so SMT siblings buy little on native FP code).
      FUGAZI_SERVICE_MAX_WORKERS = if isProd then "8" else "6";
      # Admission control in front of that pool. Unset (0) means an unbounded
      # queue, which does not degrade gracefully — it swaps, and every in-flight
      # run gets slower together. Twice the pool leaves a little queue depth;
      # past it callers get a 503 + Retry-After, which is the honest answer.
      #
      # It tracks MAX_WORKERS above and has to be raised WITH it: left at the
      # old 8/4 against the new 8/6 pool this would have been the tighter of the
      # two on the staging column, so admission would have capped at 4 and two
      # workers could never have been reached — the raise above silently buying
      # nothing. A sweep is ONE pool job for its whole grid, so the depth is
      # what absorbs several of them arriving together.
      FUGAZI_SERVICE_MAX_CONCURRENT_EVALUATIONS = if isProd then "16" else "12";

      # The largest archive either kind accepts, and the two knobs that have to
      # agree about it. Both are pinned rather than left at upstream's defaults
      # so that modules/fugazi-web's edge cap (maxRequestBodySize, 65 MiB = this
      # plus a megabyte of multipart headroom) has something stable to track.
      # `pro` is named for the same reason and not because anyone is on it: the
      # backend derives its transport ceiling from the HIGHEST finite tier cap,
      # and pro ships at 256 MiB — a size no request could reach through Caddy,
      # and one that would have the ASGI middleware read a quarter-gigabyte
      # before the parser refused it.
      FUGAZI_SERVICE_MAX_UPLOAD_BYTES = mib 64;
      FUGAZI_SERVICE_TIER_PRO_MAX_UPLOAD_BYTES = mib 64;

      # --- the `free` tier, which is what a stranger gets -------------------
      # Everything not named here stays at upstream's `free` value, which is
      # deliberately the constant the service shipped with — the sweep-shape
      # limits (200 grid points, 10 grids, 10 axes, 100 values) are already sized
      # for the smallest plausible account and need no help from us.
      #
      # This first one is not a tightening but a gap: upstream leaves free's
      # concurrency deliberately absent rather than inventing a number that would
      # break existing instances on upgrade. Absent is fine single-tenant and
      # wrong the moment signup is open — without it one account can hold every
      # slot above and everyone else gets 503s.
      FUGAZI_SERVICE_TIER_FREE_MAX_CONCURRENT_EVALUATIONS = if isProd then "2" else "1";
      # Uploaded datasets are the only thing a stranger leaves on the disk that
      # outlives their request, and there is no per-account storage quota
      # anywhere in the knob surface — the archive caps ARE the disk policy.
      # Quartered from free's 64 MiB/512 MiB/128 MiB accordingly. Rows come down
      # with them to stay proportionate; series stays at free's 500, being a
      # count rather than a volume.
      #
      # NB none of these may be "0" — in the tier namespace 0 means *no ceiling*
      # (it means "off" only for an entitlement), so a zero here would quietly do
      # the opposite of what it reads like.
      FUGAZI_SERVICE_TIER_FREE_MAX_UPLOAD_BYTES = mib 16;
      FUGAZI_SERVICE_TIER_FREE_MAX_UNCOMPRESSED_BYTES = mib 128;
      FUGAZI_SERVICE_TIER_FREE_MAX_MEMBER_BYTES = mib 32;
      FUGAZI_SERVICE_TIER_FREE_MAX_ROWS_TOTAL = "2000000";

      # --- the database pool -------------------------------------------------
      # One Postgres serves both kinds alongside Nextcloud, Immich, Prefect and
      # the rest, so these are a share of a shared server rather than a service
      # sizing its own. `pool_timeout` is deliberately short upstream (5s): it is
      # time spent inside connect(), and a 502 after five seconds is a better
      # answer than a request that might come back in half a minute.
      FUGAZI_SERVICE_DB_POOL_SIZE = if isProd then "10" else "5";
      FUGAZI_SERVICE_DB_MAX_OVERFLOW = if isProd then "20" else "10";
      # The bar store's own pool. Every call into it is asyncio.to_thread, so it
      # is bounded by the threadpool rather than by request concurrency — more
      # connections than there are threads is capacity nothing can use.
      FUGAZI_SERVICE_DB_BAR_POOL_SIZE = if isProd then "5" else "3";

      # --- what is on show ---------------------------------------------------
      # /docs, /redoc and /openapi.json. NEITHER column sets it, and the absence
      # is the setting rather than an omission. Unset, ENVIRONMENT="production"
      # (which the module pins on both kinds, to keep the startup preflight
      # armed) already turns the two HTML viewers off while /openapi.json stays
      # served everywhere — and that split is the one that matters, since the
      # schema is what a client generator or an agent reads and it describes the
      # RUNNING build, unlike the committed docs/openapi.json.
      #
      # Staging used to set "1" so the API surface could be tried interactively.
      # Measured, that bought nothing: FastAPI renders both viewers from
      # cdn.jsdelivr.net (ReDoc also pulls Google Fonts) while
      # SecurityHeadersMiddleware serves `default-src 'none'` on every response,
      # so the browser blocks every stylesheet and script and /docs comes up
      # BLANK — verified against this instance, HTTP 200 with 1013 bytes whose
      # every asset is cross-origin. Enabling it bought a blank page.
      #
      # An explicit "0" is NOT the way to say this, which is the trap worth
      # recording: upstream forces all THREE off on a literal zero, schema
      # included, so it would take /openapi.json down with the viewers. Leaving
      # the variable unset is the only spelling that gets viewers-off with
      # schema-on. Serving them for real means vendoring the assets and scoping
      # the CSP to those two paths.

      # Never on a deployment that mails real people: the dev outbox swallows
      # verification mail into a table instead of sending it, which reads as a
      # silently broken signup rather than a disabled one.
      FUGAZI_SERVICE_DEV_OUTBOX = "0";

      # INFO on both. DEBUG is the knob when something needs watching — worth
      # remembering that journald here is capped by SystemMaxUse (settings.nix),
      # so leaving it on trades away the older logs.
      FUGAZI_SERVICE_LOG_LEVEL = "INFO";

      # --- which cadences a deployment may run on ----------------------------
      # Derived from the timer table above rather than written beside it: this is
      # the same fact said to the API, and the failure mode of the two drifting is
      # a deployment that saves, shows as RUNNING and is never advanced.
      #
      # Read by the app the `testing` instance runs; a build that predates the
      # setting simply never opens the variable, so it can be unread but never
      # wrong. Note this decides which cadences EXIST here, for every account
      # including the operator's own — no plan buys a timer nobody scheduled.
      FUGAZI_SERVICE_DEPLOYMENT_FREQUENCIES =
        lib.concatMapStringsSep "," (c: c.freq) (fugaziTickCadences kind);

      # --- what advances a live deployment -----------------------------------
      # The runtime the tick composes. Upstream defaults it to `null` — a runtime
      # that steps nothing and hands back the state it was given — on the grounds
      # that turning a process into one that can place orders should be a
      # deliberate act of configuration rather than what happens when a new build
      # ships. That is the right default for a package and the wrong one for an
      # instance: every tick unit below fires on schedule, finds its deployments,
      # advances none of them and reports success, which is the same silent no-op
      # the cadence table above exists to prevent — only harder to notice, because
      # there is no missing timer to point at. `live` and `real` are accepted
      # spellings of the same choice; anything else, including a typo, is Null.
      #
      # Set on BOTH columns, because it is the answer TRADING_HALTED already gives
      # below: an instance that cannot trade is not exercising the path the tiers,
      # the entitlements and the vault exist to guard. Note there is no breaker
      # underneath it: upstream removed the instance-wide drawdown and daily-loss
      # ceilings, so what bounds a deployment is its own RiskTolerance and the
      # account default behind it (see the block further down). A column that
      # trades is a column where that default wants setting FIRST, not on the
      # morning it is instantiated.
      #
      # This does not by itself put money at risk. What a deployment trades against
      # is its WALLET, and a wallet is paper unless linked to a connected broker
      # account — which needs the `connect_brokers` entitlement (`free` holds none)
      # plus the per-venue one, and a vault key to decrypt the stored API secret.
      # This switch decides whether the tick steps a strategy at all; those decide
      # whose money it steps against.
      #
      # One thing changes on the REQUEST path too, and it is the reason to know
      # this line is here: leaving RUNNING flattens, so pause and retire now place
      # a real closing order where the Null runtime accepted the flag and ignored
      # it. That is the intended behaviour — a paused deployment's equity is meant
      # to be frozen, and a flat book marks to nothing — but it does mean pausing a
      # broker-linked deployment is a trade, at the price of the moment it is
      # clicked.
      FUGAZI_SERVICE_DEPLOYMENT_RUNTIME = "fugazi";

      # --- the trading circuit breaker ---------------------------------------
      # The service-wide kill switch, and it stays OFF because a deployment that
      # cannot trade is not exercising the path that these gates exist for. It is
      # one variable and a restart — the control an operator wants at 3am, which
      # is exactly when nobody wants to reason about per-deployment state — and
      # it is also one of the five levers /admin can move without a rebuild.
      FUGAZI_SERVICE_TRADING_HALTED = "0";
    }
    // lib.optionalAttrs (!isProd) {
      # --- staging only ------------------------------------------------------
      # Registration limited to @fugazitrade.com. The app is perfectly usable by
      # anyone holding such an address; what this withholds is an account to a
      # passer-by, and it costs no codes to distribute or rotate. Checked in POST
      # /v1/auth/register after the per-address rate limit and before the argon2
      # hash, so a non-matching address gets a 403 with no account row and no
      # verification mail — the SPA surfaces it as a failed registration rather
      # than an inbox that never fills. Comma-separated, compared lowercased
      # against the part after the LAST `@`, exact match only: a subdomain is a
      # different domain.
      #
      # UNSET on prod, which is what open signup to the internet means, and the
      # reason this key is in the staging-only block rather than set to "" — an
      # empty allow-list and an absent one both mean "anybody", and saying it by
      # omission is harder to misread.
      #
      # It gates REGISTRATION and nothing else. Existing accounts on any domain
      # log in, reset passwords and run backtests exactly as before; the gate is
      # not retroactive and evicts nobody. An administrator can move
      # `signup_mode` from /admin at runtime but NOT this list — upstream treats
      # an allow-list as configuration rather than an operational lever, so both
      # widening and narrowing it are a rebuild.
      #
      # Worth knowing before handing anyone the link: fugazitrade.com's MX is a
      # registrar forwarder, not this host's Postfix, so an address only receives
      # its verification mail if a forwarder exists for it — and
      # requireVerifiedEmail is on (the module default), so a token is refused at
      # login until it is redeemed.
      FUGAZI_SERVICE_SIGNUP_ALLOWED_EMAIL_DOMAINS = "fugazitrade.com";

      # --- risk breakers: deliberately ABSENT, and not an oversight ---------
      # This block used to set MAX_DRAWDOWN_FRACTION = "0.10" and
      # MAX_DAILY_LOSS_FRACTION = "0.05". Upstream DELETED both knobs; an
      # instance that still sets them is simply ignored, because `RiskSettings`
      # is now the kill switch and nothing else. So those two lines read as a
      # 10%/5% net over every deployment here and did nothing whatsoever —
      # which is worse than having no breaker, because it is configuration
      # shaped like a safety net.
      #
      # The reasoning that put them here was sound and the mechanism moved out
      # from under it. An instance-wide ceiling was never the operator's number
      # to set: a drawdown fraction is a claim about how a PARTICULAR strategy
      # ought to behave, made by somebody who has never seen it, about money
      # that is not theirs. A trend book that draws 40% and recovers is doing
      # its job; a mean-reversion book that draws 15% is broken. No single
      # value is right for both, which is why upstream removed the rung rather
      # than retuning it.
      #
      # What replaces it is per-deployment `RiskTolerance`, resolved
      # request > account default > nothing — and there is deliberately NO
      # instance rung, so there is nothing to put back in this file. The
      # account-level default is PUT /v1/deployments/risk-defaults; a
      # deployment created with neither an explicit `risk` object nor a default
      # behind it has no limits at all. Set it per account, there.

      # --- who may reach the sub-hourly cadences ----------------------------
      # The other half of scheduling a sub-hourly timer, and the half that decides
      # WHO. The floor above makes 5m, 15m and 30m EXIST on this instance;
      # `sub_hourly_cadence` says which tier may create a deployment on one (a 403
      # at POST /v1/deployments, and deliberately a different answer from the
      # refusal for a cadence nobody scheduled — no plan lifts that one).
      #
      # THE TESTING TIER AND NOTHING ELSE, which takes three lines because upstream
      # prices the gate rather than reserving it: `pro`, `desk` and `firm` all hold
      # it, on the argument that for somebody paying, a tick every five minutes is a
      # recurring cost with a price attached. Here nobody is paying, the box is also
      # running bitcoind, Nextcloud, Postgres and the agents, and 288 venue round
      # trips a day per deployment is the operator's own bill — so all three public
      # rungs are closed and the only account left holding the gate is this
      # instance's: FUGAZI_SERVICE_TIER_ASSIGNMENTS puts `fugazi` on the non-public
      # `testing` tier, which holds every gate and has no ticks/day ceiling. `free`
      # and `starter` never held it, so they need no line.
      #
      # It is the only per-cadence gate upstream has, and it draws its line at one
      # hour — so the coarse end of the table (2h and up) is open to every tier by
      # design, bounded by each one's max_deployment_ticks_per_day rather than by a
      # gate. Nothing reaches those here either, since signup is domain-gated and no
      # account but `fugazi` exists, but that is a fact about who is registered and
      # not something this line says.
      #
      # `0` is OFF here. In the tier namespace 0 means "no ceiling" for a LIMIT and
      # "off" for a GATE — the two are only safe apart because their field names
      # are, and these three are gates.
      #
      # Staging-only, and not merely because prod's floor is hourly: this says what
      # a PLAN may reach, so it is a pricing decision the day there are customers,
      # and inheriting it from what staging found convenient is exactly how that
      # decision gets made by nobody.
      FUGAZI_SERVICE_TIER_PRO_SUB_HOURLY_CADENCE = "0";
      FUGAZI_SERVICE_TIER_DESK_SUB_HOURLY_CADENCE = "0";
      FUGAZI_SERVICE_TIER_FIRM_SUB_HOURLY_CADENCE = "0";
    };
in
{
  imports = [
    ../../modules/fugazi-web

    # The fugazi-web service itself (`services.fugazi-web`): the uvicorn unit,
    # the maintenance timer and the per-frequency deployment-tick timers all
    # live upstream. ../../modules/fugazi-web is only the host topology around
    # it (Caddy, Postgres, SMTP loopback, sops env) and drives this module.
    fugazi-web.nixosModules.default
  ];

  # The backend + frontend packages come from the fugazi-web flake's overlay
  # (pkgs.fugazi-service, pkgs.fugazi-web-frontend), built against our nixpkgs.
  # Its NixOS module (imported above) derives the units from the same pkgs.
  nixpkgs.overlays = [ fugazi-web.overlays.default ];

  # ONE instance for now, and it is `testing` — a name for what this is rather
  # than a `prod` that is not ready to be called that. It is also EMPTY: the
  # accounts, the uploaded datasets and the running deployments built up to
  # here were left behind rather than carried over, so this starts from a
  # schema and nothing else (see databaseName below for why that was the
  # cheaper end of the trade). The public name is deliberately dark until
  # launch; see the note under my.web-server for what fugazitrade.com serves
  # meanwhile.
  #
  # `prod` will be a sibling entry when it launches: its own hostName, its own
  # port (8765 is left free for exactly that), its own database and its own JWT
  # secret at `fugazi-web/prod/jwt-secret`. Adding it is now only additive —
  # this instance no longer holds any name `prod` would want, which was the
  # point of finishing the rename below. Its intended shape is in git — commit
  # 3224eb7, which had both instances defined — rather than sitting here
  # commented out.
  my.fugazi-web.instances.testing = {
    hostName = "testing.fugazitrade.com";
    port = 8766;

    # Everything this instance owns is named after it, and the rename is
    # finished: `fugazi_testing` is the database, the Postgres role and the OS
    # user in one (the module derives all three from this name so peer auth
    # over the socket works), and the JWT secret beside it is its own.
    #
    # It did not start that way. The instance was the running deployment
    # renamed, so it kept the `fugazi` database and the `fugazi/env` key it
    # already had — which carried every account across, at the cost of an
    # instance whose name matched none of its resources and a key sitting
    # under a prefix `prod` will want.
    #
    # Finishing the rename STARTS THIS INSTANCE EMPTY, deliberately, and that
    # is the part worth being unambiguous about: nothing was dumped and
    # nothing was restored. The accounts, the uploaded datasets and the
    # deployments that were running are not here. What the old database held
    # was the record of a service being built rather than a service with users
    # to keep faith with, and a dump/restore to preserve it would have bought
    # continuity nobody needed while making the first thing in a fresh
    # deployment a set of rows nobody chose. Alembic builds the schema at head
    # on first start. The app-level `fugazi` account has to be REGISTERED
    # AGAIN — FUGAZI_SERVICE_ADMINS below grants it the role on the next start
    # once it exists, and TIER_ASSIGNMENTS puts it back on the testing tier,
    # but neither creates the account, and signup still has to pass the domain
    # gate and the mail verification the same as anyone's.
    #
    # The old `fugazi` database is still on the box regardless — NixOS never
    # drops a database or a role, and nothing here asked it to. It is not a
    # rollback anyone plans to take, just the previous state left where it
    # fell. Drop it by hand once this instance has been exercised, since until
    # then it is also being backed up.
    databaseName = "fugazi_testing";
    environmentFile = config.sops.templates."fugazi-web/testing/env".path;

    # The whole `packages` output of the second input, in one go, so a backend
    # and a frontend cannot end up from different branches. This single line is
    # the entire branch-tracking mechanism; see the fugazi-web-testing input in
    # flake.nix for why it is packages rather than a second imported module.
    packages = fugazi-web-testing.packages.${pkgs.stdenv.hostPlatform.system};

    # Reachable from the internet, and no allowedNetworks: this is not a
    # LAN-only service, it is an unlaunched public one. What stands between a
    # stranger and this box is the signup domain gate and the tier table
    # below, plus upstream's per-caller budgets on /v1/auth — and those
    # budgets are only as good as trustedProxies, hence the next line.
    #
    # Requests arrive Cloudflare -> Caddy -> uvicorn, so the hop Caddy appends
    # to X-Forwarded-For is a Cloudflare edge, not the visitor. Trusting only
    # loopback would make that edge the rate-limit bucket and every visitor
    # routed through it would share one register/login budget.
    trustedProxies = [ "127.0.0.1/32" "::1/128" ] ++ cloudflareNetworks;

    # Not launched, so not indexed. Signup is gated to @fugazitrade.com (see
    # below) and the app is perfectly usable by anyone holding such an address
    # — what this withholds is being *found*, which is the part that would be
    # hard to undo. A search result for a half-finished service outlives the
    # half-finished service.
    noIndex = true;

    # mailFrom stays the module default (noreply@acpuchades.com): this is the
    # only deployment sending mail, so there is no second sender to tell it
    # apart from. It gains a -testing suffix when prod launches beside it.
  };

  # Knobs modules/fugazi-web deliberately doesn't re-expose go straight on the
  # upstream option; `environment` is an attrsOf, so these merge with the keys
  # the module sets rather than replacing them. The policy itself is the
  # `fugaziEnvironment` table at the top of this file, which carries a column
  # for `prod` beside this one — see its header for what is set, what is
  # deliberately unset, and why the two kinds differ where they do.
  services.fugazi-web.instances.testing.environment = fugaziEnvironment "testing";

  # The tick schedule, from the same table the environment above derives its
  # FUGAZI_SERVICE_DEPLOYMENT_FREQUENCIES from — every published cadence from
  # this kind's floor (1m) up, which is all fifteen rather than upstream's four.
  # Setting this replaces upstream's default wholesale rather than adding to it,
  # which is why the table carries the coarse ones too. Three of the fifteen are
  # resident rather than timed (see below), so this is twelve timers and three
  # long-running units — but it is one option either way: a resident cadence has
  # to be named HERE as well, or upstream fails the build rather than quietly
  # scheduling nothing.
  #
  # A timer for a cadence nobody is deployed on is a oneshot that wakes, finds
  # no deployment due and exits — cheap, and the reason offering the whole
  # published range costs nothing until somebody uses it.
  #
  # The sub-hourly units need sizing a flat timer does not give them — a
  # deadline inside their own period and a self-imposed budget under it — and
  # the imported module derives both itself: `tickTimeout` is 90% of the
  # cadence capped at 15m, and the budget is 85% of that, set only below an
  # hour. It also scales `AccuracySec` to 2% of the period and jitters the
  # start by up to a tenth of it, where systemd's defaults are a flat 60s and
  # nothing. modules/fugazi-web carried a shim for the first two until
  # 2026-08-28 and no longer does — upstream's arithmetic was byte-identical.
  # It applies to the timed cadences only — a resident unit is not started per
  # bar, so it has no start deadline to size.
  services.fugazi-web.instances.testing.deploymentTickFrequencies =
    fugaziTickFrequencies "testing";

  # The three finest cadences advanced by a long-running unit each instead of a
  # timer plus a fresh process per bar. Both drivers tick on the same grid and
  # at the same moments, so this changes WHEN nothing; what it buys is the
  # ~0.53s of interpreter and fugazi import, a connection pool built cold, and
  # an in-process memory of finished steps that a process dying each bar cannot
  # have at all. At 1m that start is a real share of the period, and at 1440
  # fires a day it is most of the work; by `1h` it is amortised and by `1d` a
  # resident process would sleep through a day to save one start, which is why
  # this is per cadence rather than per instance and why it stops at 5m.
  #
  # Named cadences are taken OFF the timers automatically — necessarily, or each
  # bar would be advanced twice. Harmless (the tick claims each deployment with
  # `FOR UPDATE SKIP LOCKED`, so the loser finds nothing) but wasted work and a
  # `skipped` count nobody could explain. Flat cadences only: a
  # deploymentTickMarkets pair is daily by construction, which is exactly where
  # a resident process is worst.
  #
  # The failure mode differs from a timer's, and it is why these three units are
  # in my.ntfy-alert.failureUnits below while the twelve timed ones are not. A
  # oneshot that dies misses one bar and the next firing is a fresh process; a
  # resident unit that dies stops advancing its cadence until something restarts
  # it, with no timer behind it to paper over the gap. Restart=always covers the
  # ordinary crash, so what the alert catches is the case that outlasts it —
  # systemd giving up after the start-limit burst, which is silent and
  # indefinite.
  services.fugazi-web.instances.testing.deploymentTickResident = [ "1m" "3m" "5m" ];

  # How many deployments one tick advances at once, and it stays at upstream's
  # serial default DELIBERATELY — this is not a knob left unread.
  #
  # The arithmetic it has to satisfy, because the service refuses a width the
  # pool cannot serve: a step holds its connection for its whole length (the
  # claim is a row lock), so this is a demand for that many connections at once.
  # Above FUGAZI_SERVICE_DB_POOL_SIZE + _DB_MAX_OVERFLOW the surplus blocks and
  # is counted as FAILED ticks, so upstream raises SystemExit instead. This
  # column sets 5 + 10 = 15, NOT the 10 + 20 = 30 the prod column and upstream's
  # own default assume — so the hard ceiling here is 15, and a broker-funded
  # deployment takes a SECOND connection while its step marker commits, which
  # halves the real one to 7 and is what upstream warns about above width 8.
  #
  # What keeps it at 1 is not the pool. It is that above 1 a tick places orders
  # for SEVERAL deployments concurrently, and this instance can trade real
  # money: DEPLOYMENT_RUNTIME is `fugazi`, TRADING_HALTED is off, the vault
  # Fernet key is provisioned (fugazi-web/testing/secret-key), and the
  # non-public `testing` tier holds connect_brokers and connect_okx. It would
  # also buy nothing today — `due` has never exceeded 1 on any cadence, so a
  # wider fan-out would advance the same single deployment in the same second.
  # Raise it when there is a fleet to advance, not before, and read the two
  # bounds above before picking the number.
  services.fugazi-web.instances.testing.tickConcurrency = 1;

  # --- what the slice is allowed to take from the rest of the box -------
  # The slice TREE was already right and empty: every unit lands in
  # fugazi_web-<name>.slice inside fugazi_web.slice, so the deployment is
  # one peer of postgresql/bitcoind rather than five, and adding a cadence
  # does not widen its share. What was missing is that no ceiling or weight
  # was ever set on it — CPUWeight and IOWeight read [not set], MemoryHigh
  # and MemoryMax infinity — so the grouping bounded precisely nothing and
  # MAX_WORKERS above was doing all the work alone.
  #
  # A HIGH cpu weight is affordable here BECAUSE the steady-state demand is
  # negligible: measured over three days of uptime the whole slice spent
  # 29m47s of CPU, which is 0.65% of one core and 0.04% of the box. A weight
  # only binds under saturation, so 200 costs the default-100 neighbours
  # essentially nothing in the steady state and buys the thing that actually
  # matters — a deployment tick that is not stuck behind a btrfs scrub or
  # bitcoind's IBD when its bar closes. A missed bar is not retried by any
  # later tick.
  #
  # The memory pair is the half that protects the neighbours, and it is the
  # real reason to set anything at all: MAX_WORKERS backtests each hold a
  # bar array, so a wide sweep is the one workload here that can grow fast
  # enough to push bitcoind and Postgres into swap. High throttles reclaim,
  # Max is the hard stop — both far above the 566 MB peak this slice has
  # ever reached, and both leaving >40G of the 61G untouched.
  #
  # Deliberately NO cpuQuota: it would not shrink the pool (the worker count
  # is read off CPU affinity, which knows nothing about a cgroup quota), so
  # it makes all 6 workers slower for the same throughput and the module
  # warns when one arrives without a matching MAX_WORKERS. If a sweep ever
  # does hurt the neighbours, the instrument is a quota PAIRED with a lower
  # cap, not a lower cap alone.
  services.fugazi-web.resources = {
    cpuWeight = 200;
    ioWeight = 200;
    memoryHigh = "8G";
    memoryMax = "16G";
  };

  # Nothing instantiates the prod column yet, and an unforced `let` binding is
  # never evaluated — so a typo in it would sit undisturbed until launch day,
  # which is the worst possible morning to find one. This forces it, and
  # asserts the invariant that actually spans both columns: the transport
  # ceiling has to agree with the edge cap in modules/fugazi-web
  # (maxRequestBodySize, 65 MiB), and a column that quietly raised its upload
  # limit would turn Caddy into the real limit and hand callers a cut
  # connection instead of the parser's 413.
  assertions = [
    {
      assertion =
        (fugaziEnvironment "prod").FUGAZI_SERVICE_MAX_UPLOAD_BYTES
          == (fugaziEnvironment "testing").FUGAZI_SERVICE_MAX_UPLOAD_BYTES;
      message = ''
        fugaziEnvironment: the prod and testing columns disagree about
        FUGAZI_SERVICE_MAX_UPLOAD_BYTES. Both are tracked by one edge cap
        (my.fugazi-web.instances.<name>.maxRequestBodySize, 65MiB), so either
        keep them equal or give each instance its own cap.
      '';
    }
    {
      # The scheduled timers and the cadences the API offers are one fact said
      # twice, and they are only equal by construction while both come from
      # fugaziTickCadences. This catches the afternoon somebody sets one of them
      # by hand — the direction that hurts is offering a cadence with no timer,
      # which is a deployment that saves, reads as RUNNING and is never advanced
      # (no error, ever), so it is worth failing a rebuild over.
      #
      # Sorted on both sides: `attrNames` is alphabetical while the environment
      # keeps the table's own order, and this asserts they are the same SET.
      assertion =
        let
          sorted = lib.sort (a: b: a < b);
          scheduled = lib.attrNames
            config.services.fugazi-web.instances.testing.deploymentTickFrequencies;
          offered = lib.splitString ","
            (fugaziEnvironment "testing").FUGAZI_SERVICE_DEPLOYMENT_FREQUENCIES;
        in
        sorted scheduled == sorted offered;
      message = ''
        fugazi-web testing: the scheduled deployment ticks and
        FUGAZI_SERVICE_DEPLOYMENT_FREQUENCIES disagree. A cadence offered
        without a timer is a deployment that saves, shows as RUNNING and is
        never advanced; a timer without the cadence offered is a unit that
        wakes to find nothing. Both come from fugaziTickCadences — set one
        from the other rather than writing it out.
      '';
    }
  ];

  # fugazi-web is a PRIVATE GitHub repo, pulled in as the `fugazi-web` flake
  # input — a tarball URL, so Nix's ordinary downloader fetches it and
  # authenticates via netrc (a `github:` input would go through
  # api.github.com + access-tokens and ignore netrc; see the module header).
  # Point nix at a sops-rendered netrc carrying a GitHub PAT (github/token →
  # nix/netrc template in sops.nix).
  # Your shell's $GITHUB_TOKEN can't help — the fetch has no login environment.
  # Flake-input fetching is CLIENT-side, so the template is root:wheel 0440 and
  # `nix flake update fugazi-web` / `nix eval .#nixosConfigurations.homeserver`
  # work as alex. With a root-only 0400 both 404 — the tarball URL tracks
  # refs/heads/main, so it is unpinned by flake.lock and refetches on eval.
  # BOOTSTRAP: this template only exists after the first switch activates, so
  # seed /etc/nix/netrc by hand once before that switch.
  # A single github.com entry is enough — GitHub 302-redirects the archive to
  # codeload.github.com with a signed `?token=` in the URL, so that leg needs
  # no netrc of its own:
  #   printf 'machine github.com\n  login x-access-token\n  password ghp_…\n' \
  #     | sudo tee /etc/nix/netrc >/dev/null && sudo chmod 0400 /etc/nix/netrc
  # (the running daemon still reads the default /etc/nix/netrc at that point).
  # After the switch, netrc-file points here and every later rebuild is unattended.
  nix.settings.netrc-file = config.sops.templates."nix/netrc".path;
}
