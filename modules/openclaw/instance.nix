# One OpenClaw agent instance -> its NixOS config fragment (users, units,
# config seeding, egress rules, wrappers). Called once per
# my.openclaw.instances.<name> by ./default.nix, which merges the fragments.
#
# Per-instance NixOS config fragment. Each agent is its own OS user, home,
# memory/state dir, Telegram bot and loopback gateway service — see the
# module header. Everything that was a module-wide singleton is derived
# here from the instance name + its config (icfg).
{
  config,
  lib,
  pkgs,
  cfg,
  settingsFormat,
  defaultSafeBins,
}:

name: icfg:
let
  # Provider half of `provider/model` (e.g. "anthropic" from
  # "anthropic/claude-sonnet-4-6"). openclaw 2026.6.x scopes the agent runtime to
  # a provider/model rather than the whole agent, so the runtime backend is pinned
  # on this provider (see defaultConfig).
  runtimeProvider = builtins.head (lib.splitString "/" icfg.model);

  # The agent is a person on this host, not just a daemon: it runs as a real
  # account (`user`, named after the bot) with a real home under /home, where
  # its workspace and its Claude CLI login live. Service-owned state — the
  # config file and session data — stays in /var/lib/openclaw, named after the
  # software that owns it.
  #
  # Groups work in both directions, as they would for any other user:
  #   * to let the agent touch something on this box, add it to that thing's
  #     group (users.users.<user>.extraGroups = [ "share" ]; merges with the
  #     account defined here);
  #   * to let a human read the agent's state without becoming the agent, add
  #     them to the `openclaw` group, which owns the state tree below.
  # Its home is not covered by either — that stays 0700 and private to it.
  homeDir = "/home/${icfg.user}";
  stateDir = "/var/lib/openclaw/${name}";
  configFile = "${stateDir}/openclaw.json";
  credDir = "/run/credentials/openclaw-${name}.service";

  # Action wrappers, GPG and outbox (./instance-actions.nix).
  inherit
    (import ./instance-actions.nix {
      inherit
        config
        lib
        pkgs
        cfg
        name
        icfg
        stateDir
        ;
    })
    actionWrapperBins
    gpgCfg
    gpgEnabled
    gpgSeed
    mailAllowlist
    mailFromDisplay
    mailManageBins
    mailReadBins
    mailSendBin
    netIsolateAllowlist
    outboxBin
    outboxDir
    submitUser
    trustedMailBin
    ;

  # Skill generators live in ./skills/*.nix — one file per skill. They are
  # config-templated (they interpolate icfg/homeDir/mailFromDisplay), so unlike
  # the static scripts in ./actions/ they are FUNCTIONS returning a writeTextDir,
  # imported with the shared skillArgs below. (Distinct from any repo-root
  # ./skills of static, agent-shared SKILL.md content — a different layer.)
  skillArgs = {
    inherit
      pkgs
      lib
      icfg
      homeDir
      mailFromDisplay
      ;
  };
  mailSkillsDir = import ./skills/mail.nix skillArgs;
  captchaSkillsDir = import ./skills/captcha.nix skillArgs;
  policySkillsDir = import ./skills/policy.nix skillArgs;
  toolkitSkillsDir = import ./skills/toolkit.nix skillArgs;
  toolkitHasContent =
    icfg.toolkit.python != [ ]
    || icfg.toolkit.r != [ ]
    || icfg.toolkit.cli != [ ]
    || icfg.toolkit.notes != "";

  # OpenClaw's bundled-plugin loader opens each plugin "public surface" through a
  # boundary check that REJECTS any file with st_nlink > 1 (openBoundaryFileSync
  # { rejectHardlinks: true }, enforced once in dist/safe-open-sync-*.js). That is
  # a hardening against a surface file being hardlinked in from outside the
  # package boundary — but on NixOS with nix.settings.auto-optimise-store = true
  # the store hardlink-dedupes identical files, so EVERY bundled surface lands at
  # nlink >= 2 and the loader throws "Unable to open bundled plugin public surface
  # <plugin>/<file>".
  #
  # It bites selectively: the Claude path never trips it, because the claude-cli
  # agentRuntime shells out to the `claude` binary and never loads an internal
  # provider surface. Any NATIVE provider does load one — so a google/gemini
  # failover (or the duckduckgo web-search plugin) fails on EVERY dispatch, not
  # just when the failover fires, because the model-routing setup loads the
  # provider's surface up front. That is what silently broke all of eva's traffic
  # the moment a gemini fallback was configured.
  #
  # Neutralize BOTH nlink>1 enforcement sites so hardlinked store files are
  # accepted. openBoundaryFileSync (in safe-open-sync-*.js) rejects hardlinks
  # TWICE: once on the pre-open lstat (preOpenStat) and again on the post-open
  # fstat (openedStat) — an open-then-verify pair guarding against a TOCTOU swap.
  # The store dedups identical files to nlink>=2, so both fire. The original
  # patch disabled only the preOpenStat check, so google/gemini (and any native
  # provider) surfaces STILL failed to load on every dispatch via the openedStat
  # check — silently breaking all of eva's traffic once a gemini fallback was set.
  # The realpath / allowed-type / symlink / max-bytes checks are left intact;
  # only the two nlink>1 rejections are disabled. Safe here: the files are our own
  # read-only /nix/store on a single-tenant host — the guard buys nothing against
  # a hardlink attack and only fights the store's own dedup. Each --replace-fail
  # makes a version bump that moves/renames either expression fail the build
  # loudly rather than silently shipping the broken (unpatched) loader.
  # HARDLINK-GUARD WORKAROUND REMOVED 2026-07-27 — testing the upstream fix
  # directly. 2026.5.x shipped a bundled-plugin loader that rejected any surface
  # file with st_nlink > 1 (openBoundaryFileSync { rejectHardlinks:true } in
  # safe-open-sync-*.js); with NixOS `auto-optimise-store` dedup (nlink>=2) that
  # broke every bundled surface, so we used to `overrideAttrs` the two rejection
  # sites to `false`. openclaw 2026.6.x FIXED it upstream — the loaders now pass
  # `rejectHardlinks: false` (facade-loader / security-runtime in the 2026.6.33
  # source) — so we now run the package UNMODIFIED to confirm the fix holds under
  # our store settings. If bundled surfaces / native providers fail to load on
  # dispatch again ("Unable to open bundled plugin public surface …"), restore the
  # overrideAttrs patch from git history. Name kept (referenced throughout); it is
  # now simply the unmodified package.
  openclawPatched = cfg.package;

  # The config file is re-seeded from Nix on every start, so it is assembled
  # here in three layers with a clear precedence:
  #
  #   defaultConfig  <  icfg.settings  <  enforcedConfig
  #
  # i.e. the module's defaults can be overridden by the user's declarative
  # settings, but the security-critical keys are forced on top and cannot be
  # overridden by settings (or by anything the agent writes at runtime, since
  # the whole file is rebuilt from this each start).

  # Sensible defaults the user may override via my.openclaw.settings.
  defaultConfig = {
    gateway.port = icfg.port;
    agents.defaults = {
      model = {
        primary = icfg.model;
      }
      // lib.optionalAttrs (icfg.fallbackModels != [ ]) {
        # Ordered failover: OpenClaw tries these in turn when the primary model
        # errors. This is failover, not on-demand escalation — a stronger model
        # here only runs when the primary call fails.
        fallbacks = icfg.fallbackModels;
      };
      workspace = "${homeDir}/workspace";
    }
    // lib.optionalAttrs icfg.heartbeat.enable {
      # Periodic autonomous turns, assembled from my.openclaw.heartbeat. A
      # default (overridable via icfg.settings), not an enforced key.
      heartbeat = {
        every = icfg.heartbeat.every;
        activeHours = {
          start = icfg.heartbeat.activeHours.start;
          end = icfg.heartbeat.activeHours.end;
        }
        // lib.optionalAttrs (icfg.heartbeat.activeHours.timezone != null) {
          timezone = icfg.heartbeat.activeHours.timezone;
        };
      }
      // lib.optionalAttrs (icfg.heartbeat.prompt != null) {
        prompt = icfg.heartbeat.prompt;
      };
    };
    channels.telegram = {
      enabled = true;
      tokenFile = "${credDir}/telegram-token"; # real file (symlinks rejected)
    };
  }
  // lib.optionalAttrs (icfg.agentRuntime != null) {
    # Agent runtime backend, PROVIDER-scoped (openclaw 2026.6.x). 2026.5.x set
    # agents.defaults.agentRuntime.id; that key is now REJECTED ("agents.defaults:
    # Invalid input") — the runtime is pinned per provider/model instead. We pin it
    # on the provider of the primary model (runtimeProvider), so e.g. "claude-cli"
    # makes that provider's models run via the Claude Code subscription login;
    # "openclaw" selects the built-in native runtime.
    models.providers.${runtimeProvider}.agentRuntime.id = icfg.agentRuntime;
  }
  // lib.optionalAttrs icfg.tts.enable {
    # Reply text-to-speech, assembled from the my.openclaw.tts options. Lives in
    # defaultConfig (a preference, not a security invariant), so icfg.settings can
    # still fine-tune it. The provider's voice/model go under the persona's
    # open-additionalProps providers.<provider> slot; the provider API key is
    # NOT put here — it is read from the environment (e.g. ELEVENLABS_API_KEY),
    # so no secret enters the store.
    # Top-level `tts` since openclaw 2026.10.x; `messages.tts` is now rejected
    # ("messages: Unrecognized key: tts").
    tts = {
      # NB: no `enabled` key. OpenClaw 2026.5.x treats messages.tts.enabled as a
      # LEGACY key and rejects the config at load ("messages.tts.enabled is
      # legacy; use messages.tts.auto") — emitting it alongside `auto` fails the
      # ExecStartPre `config patch` validation and crash-loops the seed. `auto`
      # is now the sole on/off + when-to-speak control ("off" = capability
      # present but never auto-speaks).
      auto = icfg.tts.auto;
      mode = icfg.tts.mode;
      provider = icfg.tts.provider;
      maxTextLength = icfg.tts.maxTextLength;
      timeoutMs = icfg.tts.timeoutMs;
      persona = "default";
      personas.default = {
        label = icfg.tts.label;
        provider = icfg.tts.provider;
        providers.${icfg.tts.provider} = {
          # NB: `speakerVoiceId`, not `voiceId`. OpenClaw 2026.6.x treats the
          # provider speaker-selection fields voice/voiceName/voiceId as LEGACY
          # and rejects the config at load ("use speakerVoice or speakerVoiceId")
          # — emitting `voiceId` fails the ExecStartPre `config patch` validation
          # and crash-loops the seed. The `tts.voiceId` module option keeps its
          # name; only the rendered JSON key changed.
          speakerVoiceId = icfg.tts.voiceId;
        }
        // lib.optionalAttrs (icfg.tts.modelId != null) {
          modelId = icfg.tts.modelId;
        }
        // lib.optionalAttrs (icfg.tts.speed != null) {
          voiceSettings.speed = icfg.tts.speed;
        };
      };
    };
  }
  // lib.optionalAttrs icfg.stt.enable {
    # Inbound speech-to-text: transcribe voice notes so eva can act on them.
    # A whisper.cpp CLI entry in the media-audio model list. OpenClaw special-
    # cases `whisper-cli`: it transcodes the inbound Telegram OGG/Opus to
    # 16 kHz mono WAV via ffmpeg and reads whisper's `.txt` sidecar, so no
    # wrapper is needed; the transcript is then fed to the agent like a typed
    # message. Lives in defaultConfig (a preference), so icfg.settings can tune it.
    #
    # Since openclaw 2026.10.x the model list is shared across media kinds
    # (tools.media.models, each entry tagged with its `capabilities`);
    # tools.media.audio.models is rejected.
    tools.media = {
      audio.enabled = true;
      models = [
        {
          type = "cli";
          capabilities = [ "audio" ];
          command = "whisper-cli";
          args = [
            "-m"
            "${icfg.stt.model}"
            "-l"
            icfg.stt.language
            "-otxt"
            "-of"
            "{{OutputBase}}"
            "-np"
            "-nt"
            "{{MediaPath}}"
          ];
          timeoutSeconds = icfg.stt.timeoutSeconds;
        }
      ];
    };
  };

  # Embedding-backed recall over the agent's memory files (top-level
  # `memory.search` since openclaw 2026.10.x; agents.defaults.memorySearch is
  # rejected). Provider is the host's choice (local keyless GGUF by default);
  # the local model path and an optional remote model name are folded in only
  # when set, so the emitted config matches whichever backend was picked.
  #
  # "local" no longer embeds in-process (node-llama-cpp was removed in
  # 2026.10.x): it needs a managed llama.cpp provider with a `localService`,
  # which openclaw spawns on demand and stops when idle. We declare it here
  # with a direct `--model` command instead of letting `openclaw configure`
  # download its own llama-server and model — a configured command without a
  # `--models-preset` is run as given, so the server binary and the GGUF both
  # stay Nix-provided. `models = [ ]`: embeddings only, no chat models.
  memoryConfig = lib.optionalAttrs icfg.memorySearch.enable (
    {
      memory.search = {
        enabled = true;
        provider = icfg.memorySearch.provider;
      }
      // lib.optionalAttrs (icfg.memorySearch.localModelPath != null) {
        local.modelPath = "${icfg.memorySearch.localModelPath}";
      }
      // lib.optionalAttrs (icfg.memorySearch.model != null) {
        model = icfg.memorySearch.model;
      };
    }
    // lib.optionalAttrs (icfg.memorySearch.provider == "local") {
      models.providers.llama-cpp =
        let
          port = toString icfg.memorySearch.llamaServerPort;
        in
        {
          baseUrl = "http://127.0.0.1:${port}/v1";
          apiKey = "llama-cpp-local"; # openclaw's keyless-local marker
          api = "openai-completions";
          localService = {
            command = lib.getExe' icfg.memorySearch.llamaCppPackage "llama-server";
            args = [
              "--embeddings"
              "--model"
              "${icfg.memorySearch.localModelPath}"
              "--host"
              "127.0.0.1"
              "--port"
              port
            ];
            healthUrl = "http://127.0.0.1:${port}/health";
          };
          models = [ ];
        };
    }
  );

  # Non-negotiable security invariants. Access is locked to an explicit
  # numeric-ID allowlist and groups are disabled; the gateway stays loopback.
  # Merged LAST so a stray value in icfg.settings can never open access.
  enforcedConfig = {
    gateway = {
      # This build of OpenClaw takes a bind *mode* keyword, not an IP, and
      # refuses to start unless gateway.mode is set. "local" + "loopback" is
      # the 127.0.0.1-only posture we want; an IP string here is rejected.
      mode = "local";
      bind = "loopback";
    };
    channels.telegram = {
      dmPolicy = "allowlist";
      # The allowlisted ID is a runtime secret from icfg.telegram.allowedIdFile,
      # not known at eval time — so the store config is written FAIL-CLOSED
      # (nobody allowed) and the seed script patches the real ID(s) over these
      # two keys on every start (see ExecStartPre). If the file is missing/empty,
      # these stay [] and the bot answers no one, rather than opening up.
      allowFrom = [ ];
      groupPolicy = "disabled";
    };
    commands.ownerAllowFrom = [ ];

    # Exec policy is operator-authoritative, not agent-writable: it is forced on
    # here from the my.openclaw.exec options and re-patched every start, so a
    # prompt-injected agent cannot flip itself to security="full", turn off the
    # approval prompt, or slip extra binaries into the safe list at runtime. The
    # per-agent approvals allowlist (path globs) is separate mutable state and is
    # deliberately NOT pinned here — that is the human-gated approve-and-remember
    # surface. Other tools.exec.* keys (timeouts, backgroundMs, …) stay settable
    # via icfg.settings; only these safety keys are pinned.
    #
    # openclaw 2026.10.x folds security/ask into a single `mode` and rejects an
    # exec object carrying both, so the pair is emitted as the `mode` that
    # `doctor --fix` would migrate it to — otherwise the doctor-migrated live
    # file and this template conflict, the start-time patch is declined and the
    # config is reseeded from scratch. Only the pairs with no exact equivalent
    # (ask="always", full+on-miss) stay in the legacy form, which is accepted.
    tools.exec =
      (
        let
          inherit (icfg.exec) security ask;
          mode =
            if ask == "always" || (security == "full" && ask == "on-miss") then
              null
            else if security == "deny" then
              "deny"
            else if security == "allowlist" && ask == "off" then
              "allowlist"
            else if security == "full" then
              "full"
            else
              "ask";
        in
        if mode != null then { inherit mode; } else { inherit security ask; }
      )
      // {
        strictInlineEval = icfg.exec.strictInlineEval;
        safeBins =
          icfg.exec.safeBins
          ++ lib.optionals icfg.mail.enable mailReadBins
          ++ lib.optionals (icfg.mail.enable && icfg.mail.manageMaildir) mailManageBins
          # The trusted-* action wrappers SELF-GATE their destination (refusing
          # anything off the trusted list), so they are safe to bless whole-binary:
          # any invocation either targets a trusted destination or exits non-zero.
          ++ lib.optionals icfg.actions.requestUrl.enable [ "request-trusted-url" ]
          ++ lib.optionals icfg.actions.trustedMail.enable [ "send-trusted-mail" ]
          # send-encrypted-mail refuses any recipient without a pinned key and has
          # no cleartext path at all; decrypt-mail is read-only and reaches no
          # network. Both are therefore safe whole-binary. Raw `gpg` is NOT here
          # and NOT on the agent's PATH — these wrappers are its entire OpenPGP
          # surface (see mail.gpg).
          ++ lib.optionals gpgEnabled [
            "send-encrypted-mail"
            "decrypt-mail"
          ]
          # generate-image is likewise destination-pinned (fixed model/endpoint), so
          # blessing the whole binary only ever hits the configured image endpoint.
          ++ lib.optionals icfg.actions.generateImage.enable [ "generate-image" ]
          # check-weather is destination-pinned to the configured weather endpoint.
          ++ lib.optionals icfg.actions.checkWeather.enable [ "check-weather" ]
          # solve-captcha is destination-pinned to the configured solving endpoint
          # AND self-gates the page host against allowedSites, so blessing the whole
          # binary opens no destination the operator has not already blessed.
          ++ lib.optionals icfg.actions.solveCaptcha.enable [ "solve-captcha" ]
          # check-calendar only ever does local .ics parsing plus a fetch that
          # DELEGATES to the host-gated request-trusted-url binary, so blessing it
          # whole-binary opens no exfil channel beyond what request-trusted-url
          # already allows.
          ++ lib.optionals icfg.actions.checkCalendar.enable [ "check-calendar" ]
          # make-invite only writes a message to stdout — no network, no send, no
          # destination of any kind — so the whole binary is safe. What it composes
          # still has to pass a SENDER's recipient gate to go anywhere.
          ++ lib.optionals icfg.actions.makeInvite.enable [ "make-invite" ]
          # check-zotero is GET-only against a fixed endpoint; zotero-add is a WRITE
          # but a doubly-pinned one — the endpoint is fixed (the agent supplies item
          # data, never a URL), the library is the one its key owns, and it is
          # create-only (items carrying key/version are refused), so nothing already
          # in the library can be changed or destroyed. Blessing either whole-binary
          # therefore opens no destination and no deletion path.
          ++ lib.optionals icfg.actions.zotero.enable [
            "check-zotero"
            "zotero-add"
          ];
      }
      // lib.optionalAttrs (icfg.exec.safeBinProfiles != { }) {
        safeBinProfiles = icfg.exec.safeBinProfiles;
      };
  };

  # Skill directories loaded for this instance, between the module defaults and
  # the host's icfg.settings (so the host can still override but need not wire
  # them). The GENERATED ones come first: check-email (when mail is on),
  # solve-captcha (when that action is on), toolkit (when an inventory was
  # given) and the always-on policy skill that tells the agent what it
  # may/must-not do and to prefer the sanctioned action wrappers over raw tools.
  # Each exists because it is DERIVED from this instance's config — recipients,
  # trusted hosts, installed packages — and a hand-written copy would go stale.
  # Static, prose-only skills (a working method, a convention) are the host's to
  # supply as markdown via icfg.extraSkillDirs; the module has no opinion on them.
  moduleSkillDirs =
    lib.optional icfg.mail.enable "${mailSkillsDir}"
    ++ lib.optional icfg.actions.solveCaptcha.enable "${captchaSkillsDir}"
    ++ lib.optional toolkitHasContent "${toolkitSkillsDir}"
    ++ [ "${policySkillsDir}" ]
    # Static SKILL.md trees supplied by the host (icfg.extraSkillDirs). They go
    # through the SAME staging copy as the generated ones — a skill tree handed
    # in as a plain directory still lands in the store, so it would hit the
    # hardlink guard described below exactly like the generated dirs do.
    ++ map (d: "${d}") icfg.extraSkillDirs;

  # WHY WE STAGE SKILLS INTO A WRITABLE DIR INSTEAD OF POINTING extraDirs AT THE
  # STORE:
  #
  # OpenClaw's skill loader silently drops any SKILL.md whose inode is hardlinked
  # (nlink>=2 — its `rejectHardlinks` guard), and `auto-optimise-store = true`
  # dedups every store file into `.links/` (nlink>=2). So extraDirs pointing at
  # the /nix/store skill dirs loads ZERO skills — proven with `openclaw skills
  # check` → Total 0, including the always-on `policy` (security) skill, which
  # meant the agent ran with none of its module skills in effect. This is the
  # skills-loader analogue of the plugin hardlink guard tracked in CLAUDE.md;
  # 2026.6.x fixed only the *plugin* loader (`rejectHardlinks:false`), not this.
  #
  # Fix: at start, `cp` each skill tree into a per-agent dir under /var/lib (not
  # auto-optimised), giving every file a fresh inode (nlink=1) the loader
  # accepts. The dir is DEDICATED (`nix-skills`, not `skills`): the seed wipes and
  # rebuilds it on every start, and OpenClaw's own `skills install`/workshop write
  # into the agent WORKSPACE (its own `skills` dir), so a dedicated name keeps our
  # rm -rf from ever clobbering a skill the agent installed or authored itself.
  skillsStageDir = "${stateDir}/nix-skills";
  skillsStageSeed = lib.optionalString (moduleSkillDirs != [ ]) ''
    # Rebuild the skill staging tree from scratch on EVERY start, so a
    # `nixos-rebuild switch` (which restarts the unit when this script's store
    # path changes) always overwrites it with the current skills — and stale
    # skills from a prior generation never linger.
    rm -rf ${skillsStageDir}
    # 00750, not 0750: the leading 00 makes install CLEAR the setgid bit the
    # dir inherits from the 2750 state dir. Left set, every subdir cp creates
    # inherits it too, and cp's (and the chmod's) mode change then carries
    # S_ISGID — which RestrictSUIDSGID=yes rejects with EPERM, failing the
    # seed and crash-looping the gateway (2026-10-18).
    install -d -m 00750 ${skillsStageDir}
    for d in ${lib.escapeShellArgs moduleSkillDirs}; do
      # `cp` (no --preserve=links) copies content into new inodes, breaking the
      # store's hardlinks; each store dir holds exactly one `<name>/SKILL.md`.
      cp -rL --no-preserve=mode,ownership "$d"/. ${skillsStageDir}/
    done
    chmod -R u+w ${skillsStageDir}
  '';
  mailConfig = lib.optionalAttrs (moduleSkillDirs != [ ]) {
    skills.load.extraDirs = [ skillsStageDir ];
  };

  fullConfig = lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate defaultConfig memoryConfig) mailConfig) icfg.settings) enforcedConfig;

  # The config blueprint, rendered to the store as plain JSON. It holds NO
  # secrets — the bot token is a systemd credential and the allowlisted ID is
  # patched in at start from icfg.telegram.allowedIdFile — so the store is a safe
  # home for it, and the module needs no knowledge of sops/agenix/etc.
  #
  # BUILD-TIME VALIDATION: the rendered blueprint is run through
  # `openclaw config validate` as a derivation step, so a config the schema
  # REJECTS fails `nixos-rebuild` right here — loudly, with the exact error —
  # instead of switching to a generation whose ExecStartPre then crash-loops
  # on the live box (a restart can't fix a deterministic bad config, so eva
  # just stays down until someone edits + rebuilds). Two real breakages — a
  # legacy `voiceId` key and a mis-nested top-level `tts` — reached the
  # running service before this guard existed.
  #
  # `config validate` prints "… is invalid" / "Invalid input" but STILL
  # exits 0, so the check asserts on the OUTPUT TEXT, not $?: fail if it
  # flags invalidity, and also fail if it does not positively confirm
  # "Config valid" (catches a CLI crash or a future output change). It only
  # WARNS about the empty telegram allowFrom (that ID is patched in at
  # runtime), which is fine — warnings don't contain "invalid". HOME/state
  # point at $TMPDIR because validate wants a writable home; no network.
  configTemplate =
    let
      raw = settingsFormat.generate "openclaw-unchecked.json" fullConfig;
    in
    pkgs.runCommandLocal "openclaw.json" { nativeBuildInputs = [ cfg.package ]; } ''
      export HOME="$TMPDIR" OPENCLAW_STATE_DIR="$TMPDIR/state"
      mkdir -p "$OPENCLAW_STATE_DIR"
      OPENCLAW_CONFIG_PATH=${raw} openclaw config validate > validate.log 2>&1 || true
      cat validate.log
      if grep -qE 'is invalid|Invalid input' validate.log || ! grep -q 'Config valid' validate.log; then
        echo "=== openclaw config INVALID for instance '${name}' — refusing to build (see errors above) ===" >&2
        exit 1
      fi
      cp ${raw} "$out"
    '';

  # The operator-declared exec-approval globs, rendered as ONE JSON document in
  # the openclaw exec-approvals schema (pattern-only entries — `approvals set`
  # assigns each a fresh id). Deterministic and secret-free, so the nix store is
  # a fine home for it.
  execApprovalsSeed = settingsFormat.generate "openclaw-exec-approvals.json" {
    version = 1;
    socket = { };
    defaults = { };
    agents."*".allowlist = map (pattern: { inherit pattern; }) (
      icfg.exec.allowlist ++ lib.optionals icfg.mail.enable mailAllowlist ++ netIsolateAllowlist
    );
  };

  # Union the declared globs into the agent's live approvals, by pattern string,
  # so her own approve-and-remember entries survive across restarts.
  #
  # STORAGE (openclaw 2026.10.x): approvals live in SQLite
  # (`state/openclaw.sqlite#exec_approvals_config`), read and written offline
  # through `openclaw approvals get/set`. The old `${stateDir}/exec-approvals.json`
  # is now LEGACY, and its mere existence blocks every exec-approvals reader —
  # including the Telegram channel, which exits at startup. Earlier versions of
  # this seed wrote that file on every start, so a leftover one is moved aside
  # (to `.imported`) and folded into the union rather than left to block her.
  # Two Node cold starts (~1.5s each), well inside the start-pre timeout. Any
  # failure warns and leaves the stored approvals untouched.
  allowlistSeedMerge = ''
    approvalsLegacy=${stateDir}/exec-approvals.json
    approvalsTmp="$(mktemp -d)"
    echo '{}' > "$approvalsTmp/legacy.json"
    if [ -f "$approvalsLegacy" ]; then
      ${lib.getExe pkgs.jq} -e . "$approvalsLegacy" > /dev/null 2>&1 \
        && cp "$approvalsLegacy" "$approvalsTmp/legacy.json"
      mv -f "$approvalsLegacy" "$approvalsLegacy.imported"
    fi
    if ${lib.getExe openclawPatched} approvals get --json > "$approvalsTmp/live.json" \
      && ${lib.getExe pkgs.jq} -e '.file | objects' "$approvalsTmp/live.json" > /dev/null \
      && ${lib.getExe pkgs.jq} -n \
        --slurpfile seed ${execApprovalsSeed} \
        --slurpfile live "$approvalsTmp/live.json" \
        --slurpfile legacy "$approvalsTmp/legacy.json" '
          $live[0].file                                   as $file
          | ($file.agents["*"].allowlist // [])           as $cur
          | ($cur | map(.pattern))                        as $have
          | ($legacy[0].agents["*"].allowlist // []
             | map(if type == "string" then { pattern: . }
                   else { pattern } + (if .argPattern then { argPattern } else {} end) end)) as $old
          | ($old + $seed[0].agents["*"].allowlist
             | unique_by(.pattern)
             | map(select((.pattern) as $p | ($have | index($p)) | not))) as $add
          | $file
          | .version     //= 1
          | .agents      //= {}
          | .agents["*"] //= {}
          | .agents["*"].allowlist = ($cur + $add)
        ' > "$approvalsTmp/merged.json" \
      && ${lib.getExe openclawPatched} approvals set --file "$approvalsTmp/merged.json" > /dev/null; then
      :
    else
      echo "[openclaw] WARN: exec-approvals seed failed; leaving stored approvals untouched" >&2
    fi
    rm -rf "$approvalsTmp"
  '';

  # --- network egress (egress.enable) --------------------------------------
  # Every connection the agent's uid opens must go through the module's
  # filtering proxy (my.openclaw.egressProxy); the firewall rejects anything
  # else it sends, so a tool that ignores the proxy variables fails closed.
  # The allowlist is DERIVED from what the instance is configured to reach, so
  # it cannot drift from the wrappers: their hosts, the channel, the model
  # provider and TTS, plus egress.allowedDomains.
  urlHost =
    url: lib.head (lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" url)));
  egressDomains = lib.unique (
    [ "api.telegram.org" ]
    ++ lib.optionals (runtimeProvider == "anthropic") [
      "anthropic.com"
      "*.anthropic.com"
      "claude.ai"
      "*.claude.ai"
      "claude.com"
      "*.claude.com"
    ]
    ++ lib.optional (icfg.tts.enable && icfg.tts.provider == "elevenlabs") "api.elevenlabs.io"
    ++ lib.optionals icfg.actions.requestUrl.enable icfg.actions.requestUrl.trustedSites
    ++ lib.optionals icfg.actions.solveCaptcha.enable icfg.actions.solveCaptcha.allowedSites
    ++ map urlHost (
      lib.filter (u: u != "") [
        (lib.optionalString icfg.actions.generateImage.enable (
          if icfg.actions.generateImage.apiBase != null then
            icfg.actions.generateImage.apiBase
          else
            "https://generativelanguage.googleapis.com"
        ))
        (lib.optionalString icfg.actions.checkWeather.enable (
          if icfg.actions.checkWeather.apiBase != null then
            icfg.actions.checkWeather.apiBase
          else
            "https://api.openweathermap.org"
        ))
        (lib.optionalString icfg.actions.solveCaptcha.enable (
          if icfg.actions.solveCaptcha.apiBase != null then
            icfg.actions.solveCaptcha.apiBase
          else
            "https://api.2captcha.com"
        ))
        (lib.optionalString icfg.actions.zotero.enable (
          if icfg.actions.zotero.apiBase != null then
            icfg.actions.zotero.apiBase
          else
            "https://api.zotero.org"
        ))
      ]
    )
    ++ icfg.egress.allowedDomains
  );
  egressChain = "openclaw-egress-${name}";
  proxyUrl = "http://127.0.0.1:${toString cfg.egressProxy.port}";
  # The gateway, its browser-control port and the CDP range openclaw derives
  # from it (gateway+2, then 18800-18899 for the default 18789).
  gatewayPorts = "${toString icfg.port}:${toString (icfg.port + 110)}";
  egressRules = ipt: lo: ''
    ${ipt} -N ${egressChain} 2>/dev/null || ${ipt} -F ${egressChain}
    ${ipt} -A ${egressChain} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    ${ipt} -A ${egressChain} -o lo -d ${lo} -p tcp --dport ${toString cfg.egressProxy.port} -j RETURN
    ${ipt} -A ${egressChain} -o lo -d ${lo} -p tcp --dport ${gatewayPorts} -j RETURN
    # The gateway's MCP loopback server, which the Claude CLI reaches for
    # every tool: 2026.10.x binds it to a random port (always port 0, not
    # configurable), so allow the ephemeral range. Fixed-port local
    # services all sit below it.
    ${ipt} -A ${egressChain} -o lo -d ${lo} -p tcp --dport 32768:60999 -j RETURN
    ${
      lib.optionalString (icfg.memorySearch.enable && icfg.memorySearch.provider == "local") ''
        # The llama-server openclaw spawns (as the agent) for local embeddings.
        ${ipt} -A ${egressChain} -o lo -d ${lo} -p tcp --dport ${toString icfg.memorySearch.llamaServerPort} -j RETURN
      ''
    }        ${ipt} -A ${egressChain} -o lo -p udp --dport 53 -j RETURN
    ${ipt} -A ${egressChain} -o lo -p tcp --dport 53 -j RETURN
    ${ipt} -A ${egressChain} -j REJECT
    ${ipt} -D OUTPUT -m owner --uid-owner ${icfg.user} -j ${egressChain} 2>/dev/null || true
    ${ipt} -I OUTPUT -m owner --uid-owner ${icfg.user} -j ${egressChain}
  '';
  egressStop = ipt: ''
    ${ipt} -D OUTPUT -m owner --uid-owner ${icfg.user} -j ${egressChain} 2>/dev/null || true
    ${ipt} -F ${egressChain} 2>/dev/null || true
    ${ipt} -X ${egressChain} 2>/dev/null || true
  '';

in
{
  # Not a config key: read by the module-level proxy (see `services` below).
  egress = { inherit egressDomains; };

  # Fail at eval (not runtime) on a memory-search misconfig: the local embedder
  # can't run without a GGUF model, and a remote provider can't run without its
  # key — so at least require the model file for the local backend here.
  assertions = [
    {
      # The keyring lives in the agent's state dir, which the submit user
      # cannot read; encrypted mail would need its own path through sudo.
      assertion = submitUser != null -> !gpgEnabled;
      message = "my.openclaw.instances.${name}.mail.submitUser: not supported together with mail.gpg yet.";
    }
    {
      assertion = submitUser != null -> icfg.mail.enable;
      message = "my.openclaw.instances.${name}.mail.submitUser: requires mail.enable.";
    }
    {
      assertion =
        icfg.memorySearch.enable && icfg.memorySearch.provider == "local"
        -> icfg.memorySearch.localModelPath != null;
      message = "my.openclaw.memorySearch: provider = \"local\" requires memorySearch.localModelPath (a GGUF embedding model, e.g. via pkgs.fetchurl).";
    }
    {
      # An invitation with no ORGANIZER is not an invitation — clients drop it,
      # or show it as a plain event with nobody to RSVP to. The script refuses at
      # runtime too, but a misconfigured instance should not get that far.
      assertion = icfg.actions.makeInvite.enable -> icfg.mail.fromAddress != null;
      message = "my.openclaw.instances.${name}.actions.makeInvite: needs mail.fromAddress — it becomes the invitation's ORGANIZER, which clients require to match the sender.";
    }
    {
      # A malformed library would only fail at the API, after the agent had
      # already composed a batch — and the error there ("404") does not point at
      # the config. Catch the shape at eval instead.
      assertion =
        icfg.actions.zotero.enable && icfg.actions.zotero.library != null
        -> builtins.match "(users|groups)/[0-9]+" icfg.actions.zotero.library != null;
      message = "my.openclaw.instances.${name}.actions.zotero.library: must be \"users/<id>\" or \"groups/<id>\" (or null, to resolve it from the API key).";
    }
    {
      assertion = icfg.mail.gpg.enable -> icfg.mail.enable;
      message = "my.openclaw.instances.${name}.mail.gpg: requires mail.enable — confidential mail is the mail capability, encrypted.";
    }
    {
      # Without a key there is nothing to encrypt to and no signature to
      # verify, so the feature would only ever refuse — catch it at eval.
      assertion = icfg.mail.gpg.enable -> icfg.mail.gpg.keys != [ ];
      message = "my.openclaw.instances.${name}.mail.gpg: needs at least one entry in `keys` (an owner address + pinned fingerprint + public key file).";
    }
    {
      assertion = lib.all (k: builtins.match "[0-9A-Fa-f]{40}" k.fingerprint != null) icfg.mail.gpg.keys;
      message = "my.openclaw.instances.${name}.mail.gpg.keys: each `fingerprint` must be a full 40-character hex OpenPGP fingerprint with no spaces.";
    }
    {
      assertion =
        icfg.mail.gpg.fingerprint == null
        || builtins.match "[0-9A-Fa-f]{40}" icfg.mail.gpg.fingerprint != null;
      message = "my.openclaw.instances.${name}.mail.gpg.fingerprint: must be a full 40-character hex OpenPGP fingerprint with no spaces.";
    }
  ];

  # Upstream flags this package insecure on purpose. Acknowledge explicitly;
  # bump the version suffix when the packaged OpenClaw is updated.
  nixpkgs.config.permittedInsecurePackages = [ "openclaw-${cfg.package.version}" ];

  # ffmpeg must be a *system* package (not just on the service PATH): the STT
  # pipeline resolves it via requireSystemBin, which only trusts fixed dirs
  # like /run/current-system/sw/bin — the system profile, i.e. this list. The
  # SAME is true for any tool the agent runs unprompted: OpenClaw's safe-bin
  # check trusts resolved binaries by directory, and PATH entries are never
  # auto-trusted — so a safeBin present only on the service `path` gets found
  # but NOT honored as safe. jq and rg are in the module's DEFAULT safeBins yet
  # were shipped by neither list (dead references); ship them here. icfg.extra
  # Packages likewise go here (trusted + resolvable) AND on the service `path`
  # below (so bash -c can also resolve them) — belt-and-braces across both
  # resolution paths.
  #
  # The action wrappers (and mblaze) come in via actionWrapperBins, which is
  # ALSO spliced onto the service `path` below — see its definition for why
  # both. The gnupg wrappers deliberately ship WITHOUT pkgs.gnupg, so the agent
  # has no raw `gpg` to reach for (it carries its own network and key-import
  # surface).
  environment.systemPackages = [
    openclawPatched
    pkgs.claude-code
    pkgs.jq
    pkgs.ripgrep
  ]
  ++ lib.optionals icfg.stt.enable [ pkgs.ffmpeg-headless ]
  ++ actionWrapperBins
  ++ icfg.extraPackages
  ++ lib.optional (submitUser != null) outboxBin;

  users.users =
    lib.optionalAttrs (submitUser != null) {
      ${submitUser} = {
        isSystemUser = true;
        group = submitUser;
        description = "Mail submission for OpenClaw agent ${name}";
      };
    }
    // {
      ${icfg.user} = {
        isNormalUser = true;
        group = icfg.user;
        home = homeDir;
        createHome = true;
        shell = pkgs.bashInteractive;
        # GECOS. Postfix's sendmail(1) reads the full name from here when no -F is
        # given, so keeping it in sync with icfg.fullName means anything the agent
        # sends outside the wrappers still carries the same name.
        description = if icfg.fullName == "" then "OpenClaw agent" else icfg.fullName;
        # Every agent is a member of `agents`, the group that reads the SHARED
        # service API keys (the image/weather/captcha/TTS tokens). Those are
        # per-SERVICE, not per-agent — a second agent uses the same 2Captcha
        # account — so the secret is group-readable rather than chowned to whichever
        # agent happened to be configured first. Deliberately NOT the `openclaw`
        # group below: that one reads the state TREE, and putting agents in it would
        # let each agent read every other agent's memory and sessions.
        # The submit user's group reads the address lists both sides use.
        extraGroups = [ "agents" ] ++ lib.optional (submitUser != null) submitUser;
        # Local-only identity: no password, no keys, and sshd refuses it outright
        # (below), so the account can be inhabited from a root session on this box
        # and nowhere else. `!` is an invalid hash — it matches nothing.
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [ ];
      };
    };
  users.groups = lib.optionalAttrs (submitUser != null) { ${submitUser} = { }; } // {
    ${icfg.user} = { };
    # Read access to the agent's service state for principals who should be
    # able to inspect it without becoming the agent. Deliberately NOT the
    # agent's primary group — it owns its files as itself, and this is only an
    # ACL over the state tree. Join it with users.users.<name>.extraGroups.
    openclaw = { };
    # Read access to the SHARED service secrets — API keys that belong to a
    # SERVICE, not to an agent (2Captcha, OpenWeatherMap, Gemini, ElevenLabs …).
    # Every agent user joins it (see extraGroups above), so such a secret is
    # granted once with `group = "agents"; mode = "0440";` and every agent —
    # present and future — can read it, with no agent name anywhere in the secret
    # declaration. Agent-IDENTITY secrets (a Telegram bot token and its
    # allowlisted ID) are the opposite case: they stay owned by the one agent they
    # belong to. Named generically because the membership is "is an agent on this
    # host", not "is an OpenClaw instance" — a future non-OpenClaw agent joins the
    # same group and inherits the same key access.
    agents = { };
  };

  # Belt and braces on top of the empty password/key set: an authorized_keys
  # file or password added later cannot silently open remote access. Covers
  # mosh too, which authenticates over ssh. Act as the agent with
  # `sudo -u <user> -H ...`.
  services.openssh.settings.DenyUsers = [ icfg.user ];

  # Passwordless sudo for exactly the commands listed in icfg.sudoCommands and
  # nothing else. NOPASSWD is required because the account has no password (`!`
  # above), so it could not answer a prompt even if asked.
  security.sudo.extraRules =
    lib.optional (icfg.sudoCommands != [ ]) {
      users = [ icfg.user ];
      commands = map (command: {
        inherit command;
        options = [ "NOPASSWD" ];
      }) icfg.sudoCommands;
    }
    # The real send wrappers, as the submit user, with any arguments: each
    # one checks its own recipients.
    ++ lib.optional (submitUser != null) {
      users = [ icfg.user ];
      runAs = submitUser;
      commands =
        map
          (command: {
            inherit command;
            options = [ "NOPASSWD" ];
          })
          (
            [ "${mailSendBin}/bin/send-email" ]
            ++ lib.optional icfg.actions.trustedMail.enable "${trustedMailBin}/bin/send-trusted-mail"
          );
    };

  # The state dir is the agent's, group-readable by openclaw. setgid so
  # everything written below it inherits that group without the agent having
  # to be a member — with UMask=0027 below, that is what makes the state
  # actually readable to the group rather than just nominally owned by it.
  #
  # The Z line recursively enforces ownership across the whole tree on every
  # activation. The service has changed its running user over its life, which
  # left subdirs (agents/, logs/, devices/) owned by the previous user and
  # unreadable to the current one — the agent then hit EACCES creating session
  # dirs and every Telegram request failed. Mode "-" leaves file modes alone
  # (OpenClaw manages its own 0700 dirs); only uid/gid are re-applied, so this
  # self-heals a user change without fighting the app over permissions.
  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw 0755 root root -"
    "d ${stateDir} 2750 ${icfg.user} openclaw -"
    "Z ${stateDir} - ${icfg.user} openclaw -"
  ]
  ++ lib.optionals (submitUser != null) [
    "d /var/spool/openclaw-outbox 0755 root root -"
    "d ${outboxDir} 0700 ${submitUser} ${submitUser} -"
  ];

  networking.firewall = lib.mkIf icfg.egress.enable {
    extraCommands = egressRules "iptables" "127.0.0.1" + egressRules "ip6tables" "::1";
    extraStopCommands = egressStop "iptables" + egressStop "ip6tables";
  };

  # Grant the agent ACL access to icfg.access paths. This is an ACTIVATION
  # SCRIPT, not a oneshot service, and it matters: activation scripts run on
  # EVERY `nixos-rebuild switch` and boot, whereas NixOS only re-runs an
  # unchanged oneshot on reboot — so with a service, a switch would leave a
  # broken grant unrepaired. `deps = [ "users" ]` orders it AFTER the users
  # activation, which chmods home dirs to their homeMode (e.g. /home/alex to
  # 0700) and in doing so recomputes any POSIX ACL mask to `---`, silently
  # neutering a `u:<agent>:X` traversal grant (the entry stays, effective
  # becomes ---). Re-running setfacl here restores both the entry and the
  # mask on every switch. A bad path just logs and does not abort activation.
  system.activationScripts."openclaw-grant-access-${name}" = lib.mkIf (icfg.access != { }) {
    deps = [ "users" ];
    text = lib.concatStrings (
      lib.mapAttrsToList (
        path: opts:
        let
          rec' = lib.optionalString opts.recursive "-R ";
        in
        ''
          ${pkgs.acl}/bin/setfacl ${rec'}-m u:${icfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
            || echo "[openclaw] WARN: setfacl grant failed for ${path}" >&2
        ''
        + lib.optionalString opts.defaultAcl ''
          ${pkgs.acl}/bin/setfacl ${rec'}-d -m u:${icfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
            || echo "[openclaw] WARN: default-ACL grant failed for ${path}" >&2
        ''
      ) icfg.access
    );
  };

  systemd.services."openclaw-${name}" = {
    description = "OpenClaw agent gateway (Telegram-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # `claude` is only on PATH for the claude-cli runtime (subscription auth) —
    # the native runtime (agentRuntime = null) never shells out to it, so it is
    # gated on the backend actually being claude-cli. The rest is what the
    # agent's own shell tooling generally expects. When STT is on, whisper-cli
    # joins the PATH so OpenClaw can exec the configured transcription command
    # by name. (ffmpeg is NOT enough on PATH — OpenClaw resolves it via
    # requireSystemBin/trusted dirs, so it goes in environment.systemPackages
    # below instead.)
    path = [
      pkgs.git
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      pkgs.ripgrep
    ]
    ++ lib.optionals (icfg.agentRuntime == "claude-cli") [ pkgs.claude-code ]
    ++ lib.optionals icfg.stt.enable [ icfg.stt.package ]
    # The self-gating action wrappers (generate-image, check-weather,
    # send-email, …) and mblaze — the agent invokes these by name from its own
    # shell, so they must resolve on the service PATH, not only in the system
    # profile that OpenClaw's safe-bin trust check reads. See actionWrapperBins.
    ++ actionWrapperBins
    # Host-supplied tools the agent may invoke by name (still gated by the
    # exec allowlist for whether a run needs approval — see icfg.exec). Also in
    # environment.systemPackages above so the safe-bin trust check honors them.
    ++ icfg.extraPackages
    # The setuid `sudo` lives in /run/wrappers/bin, which a unit's PATH does
    # NOT include — without this, every icfg.sudoCommands grant is dead
    # ("sudo: command not found"; eva never ran one from 2026-08 until
    # this fix). Grants no new privilege: the absolute wrapper paths were
    # always reachable, and sudoers still decides what runs.
    ++ lib.optional (icfg.sudoCommands != [ ] || submitUser != null) "/run/wrappers";

    environment = {
      HOME = homeDir;
      OPENCLAW_STATE_DIR = stateDir;
      OPENCLAW_CONFIG_PATH = configFile;
      # Nix pins the version, so the update check (which doubles as the
      # telemetry ping to telemetry.openclaw.ai) is pointless; DO_NOT_TRACK
      # also keeps the feature stats off.
      OPENCLAW_NO_AUTO_UPDATE = "1";
      DO_NOT_TRACK = "1";
    }
    # Every HTTP client the agent runs (the gateway's undici, Claude Code,
    # chromium, curl, git, gh, python) reads these; the firewall rejects
    # whatever does not.
    // lib.optionalAttrs icfg.egress.enable {
      HTTP_PROXY = proxyUrl;
      HTTPS_PROXY = proxyUrl;
      http_proxy = proxyUrl;
      https_proxy = proxyUrl;
      NO_PROXY = "localhost,127.0.0.1,::1";
      no_proxy = "localhost,127.0.0.1,::1";
      # Telemetry and update checks would only fail at the proxy.
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    };

    serviceConfig = {
      User = icfg.user;
      Group = icfg.user;

      # Config seeding is a BLUEPRINT merge, not a hard overwrite, in three
      # steps: (1) apply the config blueprint, (2) patch in the Telegram
      # allowlist from the secret file, (3) union the exec-approval globs into
      # the agent's live allowlist with a single jq merge. Step 3 was formerly
      # ~34 sequential `openclaw approvals allowlist add` calls (~1.4s of Node
      # cold-start each) that overran the 90s start-pre timeout and crash-
      # looped the gateway; it is now one Node-free jq call (regression fixed
      # 2026-07-26).
      #
      # (1) First boot (file absent) lays down the full Nix-rendered config,
      # created fresh inside the setgid state dir so it lands in the openclaw
      # group. Every subsequent start recursively patches the Nix-declared keys
      # back on top of whatever the agent has written — so declared keys (incl.
      # the enforced security keys) are re-asserted, while keys Nix does NOT
      # declare survive as the agent's own. A corrupt existing file / failed
      # merge falls back to a clean reseed so the gateway always starts valid.
      #
      # (2) Patch the allowlisted Telegram ID(s) in from the runtime secret
      # file (one ID per line; blanks and #comments ignored). The blueprint
      # wrote the allowlist FAIL-CLOSED (empty), so THIS is what opens access —
      # and only to these IDs, re-asserted every start. A missing/empty/
      # unreadable file leaves the allowlist empty, so the bot answers no one.
      ExecStartPre = pkgs.writeShellScript "openclaw-seed-config" ''
        set -euo pipefail

        # (0) Materialise the module skills into a writable, hardlink-free tree
        # (see skillsStageSeed) BEFORE the gateway starts, so the loader accepts
        # them. No-op when the instance ships no skills.
        ${skillsStageSeed}

        # (0b) Rebuild the OpenPGP keyring from nix (see gpgSeed), so the agent
        # starts from exactly the keys this module declares and nothing it may
        # have imported since. No-op unless mail.gpg is on.
        ${gpgSeed}
        tmpl=${configTemplate}
        if [ -f ${configFile} ]; then
          ${lib.getExe openclawPatched} config patch --file "$tmpl" || {
            rm -f ${configFile}
            install -m 0640 "$tmpl" ${configFile}
          }
        else
          install -m 0640 "$tmpl" ${configFile}
        fi

        ids=""
        if [ -r ${lib.escapeShellArg icfg.telegram.allowedIdFile} ]; then
          while IFS= read -r line || [ -n "$line" ]; do
            line=''${line//[[:space:]]/}
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            ids="$ids''${ids:+,}\"$line\""
          done < ${lib.escapeShellArg icfg.telegram.allowedIdFile}
        fi
        if [ -z "$ids" ]; then
          echo "[openclaw] WARN: no Telegram ID in ${icfg.telegram.allowedIdFile}; allowlist stays empty (bot answers no one)" >&2
        fi
        printf '{"channels":{"telegram":{"allowFrom":[%s]}},"commands":{"ownerAllowFrom":[%s]}}' "$ids" "$ids" \
          | ${lib.getExe openclawPatched} config patch --stdin

        # (3) Seed the operator-declared exec-approval globs (single jq merge).
        ${allowlistSeedMerge}
      '';
      ExecStart = "${lib.getExe openclawPatched} gateway";
      # `always`, NOT `on-failure`: openclaw's own restart paths (the
      # gateway-restart tool, a config-reload restart) do a "full process
      # restart (supervisor restart)" — the gateway EXITS 0 expecting a
      # supervisor to re-exec it. Under `on-failure` systemd treats that
      # clean exit as success and leaves the unit dead, so any self-initiated
      # restart silently takes the agent down until someone runs `systemctl
      # start` (bit eva on 2026-08-06). `always` honours the exit-0 restart.
      # Crash-loops on a genuinely bad config are still bounded by the
      # StartLimit below, and a schema-invalid config can't even reach the
      # box (the configTemplate `config validate` derivation fails the build).
      Restart = "always";
      RestartSec = 5;
      # The seed above is now two fast config patches plus one jq merge, but
      # keep a margin over systemd's 90s default so a momentarily loaded box
      # never times the gateway out before it binds.
      TimeoutStartSec = 180;

      LoadCredential = [
        "telegram-token:${icfg.telegram.tokenFile}"
      ]
      # systemd reads the key as root and exposes it 0400 to the service user,
      # so the secret never depends on the sops/agenix file's own ownership
      # being right — same handling the bot token already gets.
      ++ lib.optional (gpgEnabled && gpgCfg.secretKeyFile != null) "mail-gpg-key:${gpgCfg.secretKeyFile}";

      # Extra env for provider API keys (Gemini fallback, ElevenLabs TTS, …),
      # supplied as files from outside the module. Empty by default.
      EnvironmentFile = icfg.environmentFiles;

      # No StateDirectory=: systemd would chown the tree to User:Group, i.e.
      # the agent's own group, and there is no way to ask it for a different
      # group. tmpfiles owns the directory instead (see above).
      WorkingDirectory = stateDir;
      # 0640 files / 0750 dirs, so the openclaw group can read what the agent
      # writes below the state dir. Its home stays 0700 regardless.
      UMask = "0027";

      # Confinement. The filesystem is read-only apart from the agent's own
      # trees; other homes are hidden. Not NoNewPrivileges, nor a capability
      # bound or syscall filter: sudo (sudoCommands, the submit user) needs
      # setuid, and the `offline` launcher needs namespaces.
      ProtectSystem = "strict";
      ProtectHome = "tmpfs";
      BindPaths = [ homeDir ];
      ReadWritePaths = [
        stateDir
        # sudo's timestamp dir; may not exist yet.
        "-/run/sudo"
      ]
      # sendmail(1) drops the message here (setgid postdrop).
      ++ lib.optional icfg.mail.enable "/var/lib/postfix/queue/maildrop"
      # Held mail; written by the submit user, which sudo starts inside this
      # same mount namespace (the directory is 0700 to it, not the agent).
      ++ lib.optional (submitUser != null) outboxDir;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
    };
  };
}
