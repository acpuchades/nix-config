{ config, lib, pkgs, ... }:

#
# openclaw — self-hosted LLM agent (OpenClaw), reachable ONLY through Telegram
# (long-polling; no inbound port). The gateway/control UI is bound to loopback
# so it is reachable locally but never from the LAN.
#
# Two layers, and only one of them is here:
#
#   * WHO CAN TALK TO IT — kept and declarative. The gateway binds 127.0.0.1,
#     Telegram DMs are locked to an explicit numeric-ID allowlist, groups are
#     disabled, and neither the bot token nor the allowed ID ever touches the
#     store or the repo — both arrive as runtime files (telegram.tokenFile /
#     telegram.allowedIdFile), so the module stays agnostic about the secret
#     system behind them (sops-nix, agenix, plain files, …). OpenClaw rewrites
#     its own config at runtime, so it is re-seeded on every start — including
#     re-patching the allowlist from the ID file — to keep this authoritative.
#
#   * WHAT IT CAN DO TO THE HOST — deliberately absent. No systemd sandbox, no
#     polkit rules, no capability grants. Upstream marks this package
#     `knownVulnerabilities` (an LLM parses untrusted content with full system
#     access by default → prompt-injectable), acknowledged below via
#     permittedInsecurePackages. Confinement is to be configured separately.
#
# Auth uses a Claude subscription rather than an Anthropic API key: OpenClaw
# reuses a Claude Code CLI login on this host (`claude -p`), selected by the
# `agentRuntime` option below. Log in once as the agent's own user:
#
#   sudo -u <user> -H claude            # /login, then quit
#   systemctl restart openclaw
#
# That writes ~/.claude/.credentials.json, which OpenClaw picks up. On a box
# where the browser flow is awkward, `claude setup-token` yields a long-lived
# token instead — put it in the state dir's .env as CLAUDE_CODE_OAUTH_TOKEN.
#

let
  cfg = config.my.openclaw;

  # Freeform JSON so my.openclaw.settings can express any key in openclaw.json
  # (see `openclaw config schema`) without the module having to model each one.
  settingsFormat = pkgs.formats.json { };

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
  homeDir = "/home/${cfg.user}";
  stateDir = "/var/lib/openclaw";
  configFile = "${stateDir}/openclaw.json";
  credDir = "/run/credentials/openclaw.service";

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
  # Neutralize the single enforcement site so hardlinked store files are accepted.
  # The realpath / allowed-type / symlink / max-bytes checks around it are left
  # intact; only the nlink>1 rejection is disabled. This is safe here: the files
  # are our own read-only /nix/store, and this is a single-tenant host — the guard
  # buys nothing against a hardlink attack and only fights the store's own dedup.
  # --replace-fail makes a version bump that moves/renames this expression fail
  # the build loudly rather than silently shipping the broken (unpatched) loader.
  openclawPatched = cfg.package.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      patched=0
      for f in "$out"/lib/openclaw/dist/safe-open-sync-*.js; do
        [ -e "$f" ] || continue
        substituteInPlace "$f" \
          --replace-fail \
            'params.rejectHardlinks && preOpenStat.isFile() && preOpenStat.nlink > 1' \
            'false && preOpenStat.isFile() && preOpenStat.nlink > 1'
        patched=1
      done
      if [ "$patched" != 1 ]; then
        echo "openclaw: hardlink-guard patch matched no safe-open-sync-*.js" >&2
        exit 1
      fi
    '';
  });

  # The config file is re-seeded from Nix on every start, so it is assembled
  # here in three layers with a clear precedence:
  #
  #   defaultConfig  <  cfg.settings  <  enforcedConfig
  #
  # i.e. the module's defaults can be overridden by the user's declarative
  # settings, but the security-critical keys are forced on top and cannot be
  # overridden by settings (or by anything the agent writes at runtime, since
  # the whole file is rebuilt from this each start).

  # Sensible defaults the user may override via my.openclaw.settings.
  defaultConfig = {
    gateway.port = cfg.port;
    agents.defaults = {
      model = {
        primary = cfg.model;
      } // lib.optionalAttrs (cfg.fallbackModels != [ ]) {
        # Ordered failover: OpenClaw tries these in turn when the primary model
        # errors. This is failover, not on-demand escalation — a stronger model
        # here only runs when the primary call fails.
        fallbacks = cfg.fallbackModels;
      };
      workspace = "${homeDir}/workspace";
    } // lib.optionalAttrs (cfg.agentRuntime != null) {
      agentRuntime.id = cfg.agentRuntime;
    };
    channels.telegram = {
      enabled = true;
      tokenFile = "${credDir}/telegram-token"; # real file (symlinks rejected)
    };
  } // lib.optionalAttrs cfg.tts.enable {
    # Reply text-to-speech, assembled from the my.openclaw.tts options. Lives in
    # defaultConfig (a preference, not a security invariant), so cfg.settings can
    # still fine-tune it. The provider's voice/model go under the persona's
    # open-additionalProps providers.<provider> slot; the provider API key is
    # NOT put here — it is read from the environment (e.g. ELEVENLABS_API_KEY),
    # so no secret enters the store.
    messages.tts = {
      enabled = true;
      auto = cfg.tts.auto;
      mode = cfg.tts.mode;
      provider = cfg.tts.provider;
      maxTextLength = cfg.tts.maxTextLength;
      timeoutMs = cfg.tts.timeoutMs;
      persona = "default";
      personas.default = {
        label = cfg.tts.label;
        provider = cfg.tts.provider;
        providers.${cfg.tts.provider} = {
          voiceId = cfg.tts.voiceId;
        } // lib.optionalAttrs (cfg.tts.modelId != null) {
          modelId = cfg.tts.modelId;
        };
      };
    };
  };

  # Non-negotiable security invariants. Access is locked to an explicit
  # numeric-ID allowlist and groups are disabled; the gateway stays loopback.
  # Merged LAST so a stray value in cfg.settings can never open access.
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
      # The allowlisted ID is a runtime secret from cfg.telegram.allowedIdFile,
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
    # via cfg.settings; only these safety keys are pinned.
    tools.exec = {
      security = cfg.exec.security;
      ask = cfg.exec.ask;
      strictInlineEval = cfg.exec.strictInlineEval;
      safeBins = cfg.exec.safeBins;
    } // lib.optionalAttrs (cfg.exec.safeBinProfiles != { }) {
      safeBinProfiles = cfg.exec.safeBinProfiles;
    };
  };

  fullConfig =
    lib.recursiveUpdate (lib.recursiveUpdate defaultConfig cfg.settings) enforcedConfig;

  # The config blueprint, rendered to the store as plain JSON. It holds NO
  # secrets — the bot token is a systemd credential and the allowlisted ID is
  # patched in at start from cfg.telegram.allowedIdFile — so the store is a safe
  # home for it, and the module needs no knowledge of sops/agenix/etc.
  configTemplate = settingsFormat.generate "openclaw.json" fullConfig;

  # The operator-declared exec-approval globs, rendered as ONE JSON file in the
  # openclaw exec-approvals schema (pattern-only entries — OpenClaw backfills the
  # id/lastUsedAt fields itself the first time it reads the file). Deterministic
  # and secret-free, so the nix store is a fine home for it.
  execApprovalsSeed = settingsFormat.generate "openclaw-exec-approvals.json" {
    version = 1;
    socket = { };
    defaults = { };
    agents."*".allowlist = map (pattern: { inherit pattern; }) cfg.exec.allowlist;
  };

  # Fast, Node-free seed: union the declared globs into the agent's live
  # exec-approvals.json with a SINGLE jq call, replacing the old loop that ran
  # one ~1.4s `openclaw approvals allowlist add` process per glob (~34 of them,
  # which overran the gateway's 90s start-pre timeout and crash-looped it). The
  # union is by pattern string, so the agent's own approve-and-remember entries
  # survive across restarts; a failed merge warns and leaves the file untouched.
  allowlistSeedMerge = ''
    approvalsFile=${homeDir}/.openclaw/exec-approvals.json
    mkdir -p "$(dirname "$approvalsFile")"
    if [ -f "$approvalsFile" ]; then liveSrc="$approvalsFile"; else liveSrc=${execApprovalsSeed}; fi
    tmp="$(mktemp)"
    if ${lib.getExe pkgs.jq} -s '
          .[0] as $seed | .[1] as $live
          | ($live.agents["*"].allowlist // [])            as $cur
          | ($cur | map(.pattern))                          as $have
          | ($seed.agents["*"].allowlist
             | map(select((.pattern) as $p | ($have | index($p)) | not))) as $add
          | $live
          | .version     //= 1
          | .socket      //= {}
          | .defaults    //= {}
          | .agents      //= {}
          | .agents["*"] //= {}
          | .agents["*"].allowlist = ($cur + $add)
        ' ${execApprovalsSeed} "$liveSrc" > "$tmp"; then
      install -m 0600 "$tmp" "$approvalsFile"
    else
      echo "[openclaw] WARN: exec-approvals seed merge failed; leaving existing file untouched" >&2
    fi
    rm -f "$tmp"
  '';
in
{
  options.my.openclaw = {
    enable = lib.mkEnableOption "OpenClaw agent (Telegram-only, loopback gateway)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw;
      defaultText = lib.literalExpression "pkgs.openclaw";
      description = "OpenClaw package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = ''
        Account the agent lives as — a normal user with a home at /home/<user>,
        holding its workspace and its Claude CLI login. Override it with the
        bot's own name, so the identity it acts under on this host matches the
        one people talk to. It gets no password and no SSH keys, so it is not
        reachable from outside; use `sudo -u <user> -H ...` to act as it.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "anthropic/claude-sonnet-4-6";
      description = "Primary model, as provider/model.";
    };

    fallbackModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "anthropic/claude-opus-4-8" ];
      description = ''
        Ordered failover models (each as provider/model) tried in turn when the
        primary model errors. This is failover, NOT on-demand escalation: a more
        powerful model here runs only when the primary call fails, not because a
        task looks hard. Defaults to Opus 4.8 behind the Sonnet 4.6 primary — the
        strong model catches outages/rate-limits on the everyday one. Set to [ ]
        to disable fallbacks.
      '';
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        [
          "-/run/secrets/openclaw-gemini-env"   # GEMINI_API_KEY for a google/* fallback
          "/run/secrets/openclaw-elevenlabs-env" # ELEVENLABS_API_KEY for TTS
        ]
      '';
      description = ''
        Extra systemd EnvironmentFile paths for the service — the place to supply
        provider API keys the agent needs, so a token comes in from OUTSIDE the
        module just like the model it belongs to: a google/* fallbackModel needs
        GEMINI_API_KEY, an elevenlabs TTS voice needs ELEVENLABS_API_KEY, etc.
        Kept as plain paths so the module stays agnostic about the secret system;
        prefix a path with "-" to make it optional (a missing file won't fail
        start). These are read only at runtime, never as Nix values, so no key
        enters the store or the config.
      '';
    };

    agentRuntime = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "claude-cli";
      example = null;
      description = ''
        Execution backend for the agent. "claude-cli" reuses this host's Claude
        Code CLI login, so the Claude subscription pays rather than an Anthropic
        API key. Set to null to use the provider's own API auth instead (which
        then needs an API key configured out of band).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = ''
        Loopback port for the gateway / control UI. Bound to 127.0.0.1 only —
        never opened in the firewall. Reach it locally (e.g. via SSH tunnel).
      '';
    };

    telegram = {
      # Both inputs are secrets and this repo is public, so the module takes
      # runtime FILE PATHS rather than the values — and it is agnostic about what
      # produces those files. Point them at sops-nix (config.sops.secrets.<x>.path),
      # agenix, or any out-of-band file; the module only ever reads them at run
      # time, never at eval, so the secrets never enter the store or the repo.
      # NB: use str, not path — a `path` value would copy the secret INTO the
      # store, which is exactly what we are avoiding.
      tokenFile = lib.mkOption {
        type = lib.types.str;
        example = "/run/secrets/openclaw-telegram-token";
        description = ''
          Path to a file containing the BotFather bot token (single line). Loaded
          as a systemd credential and referenced by channels.telegram.tokenFile;
          it is never read at eval time, so it never lands in the store or repo.
        '';
      };
      allowedIdFile = lib.mkOption {
        type = lib.types.str;
        example = "/run/secrets/openclaw-telegram-userid";
        description = ''
          Path to a file containing the numeric Telegram user ID(s) allowlisted
          for DMs and command ownership — one ID per line (blank lines and lines
          starting with `#` are ignored). Read at service START and patched into
          the config's allowlist; if the file is missing or empty the allowlist
          stays empty and the bot answers no one (fail-closed). Get your ID from
          @userinfobot.
        '';
      };
    };

    tts = {
      # Reply text-to-speech, modelled as options rather than a raw settings blob
      # so voice/provider/etc. are configured from outside the module. Assembled
      # into messages.tts (see defaultConfig). The provider API key is never a
      # Nix value — it is read from the service environment (e.g. wire an
      # EnvironmentFile setting ELEVENLABS_API_KEY on the host).
      enable = lib.mkEnableOption "reply text-to-speech";
      provider = lib.mkOption {
        type = lib.types.str;
        default = "elevenlabs";
        description = ''
          TTS provider id (e.g. "elevenlabs", "microsoft"). The voiceId/modelId
          below are placed under this provider in the reply persona.
        '';
      };
      voiceId = lib.mkOption {
        type = lib.types.str;
        example = "dNjJKg63Fr5AXwIdkATa";
        description = ''
          Provider voice identifier for replies (for ElevenLabs, the voice ID).
        '';
      };
      modelId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "eleven_multilingual_v2";
        description = ''
          Provider TTS model id, or null to leave it to the provider default.
          ElevenLabs "eleven_multilingual_v2" handles non-English (e.g. Spanish);
          "eleven_turbo_v2_5" trades some quality for latency.
        '';
      };
      auto = lib.mkOption {
        type = lib.types.enum [ "off" "always" "inbound" "tagged" ];
        default = "inbound";
        description = ''
          When to speak. "inbound" = only reply with voice when the user sent a
          voice message (talk→talk); "always" speaks every reply; "tagged" only
          when explicitly requested; "off" disables auto-speech.
        '';
      };
      mode = lib.mkOption {
        type = lib.types.enum [ "final" "all" ];
        default = "final";
        description = "Synthesize only the final reply (\"final\") or every streamed chunk (\"all\").";
      };
      label = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Human label for the reply TTS persona.";
      };
      maxTextLength = lib.mkOption {
        type = lib.types.ints.positive;
        default = 800;
        description = "Cap on characters synthesized per reply, so a huge message can't spawn a giant/slow render.";
      };
      timeoutMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 15000;
        description = "Synthesis timeout in milliseconds.";
      };
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          agents.defaults.model.primary = "anthropic/claude-opus-4-8";
          # extra skill directories loaded alongside the workspace
          skills.load.extraDirs = [ "/etc/openclaw/skills" ];
          # register an MCP tool server
          mcp.servers.fetch.command = "''${pkgs.mcp-fetch}/bin/mcp-fetch";
          # widen/narrow the agent's tool + exec policy
          tools.alsoAllow = [ "web.search" ];
        }
      '';
      description = ''
        Declarative OpenClaw configuration, deep-merged into openclaw.json. This
        is a BLUEPRINT, not a hard overwrite: first boot writes the full config,
        and every start thereafter recursively patches the keys declared here
        back on top of whatever the agent has written. So anything set here
        always wins (it is re-asserted each start), while keys NOT declared here
        are the agent's own and persist across restarts — `openclaw config set`
        / runtime writes to undeclared keys stick. Run `openclaw config schema`
        to see the full key set.

        Precedence within the blueprint: module defaults < this < enforced
        security keys. The security-critical keys (gateway.bind/mode, the
        Telegram allowlist, dmPolicy/groupPolicy, ownerAllowFrom) are forced on
        top and re-patched every start, so a mistaken value here — or anything
        the agent writes at runtime — cannot durably open access.

        Note: agent *skills* live in the workspace (and any skills.load.extraDirs
        above) and persist independently of this file.
      '';
    };

    # WHAT IT CAN DO TO THE HOST. The options below are the deliberate, narrow
    # exceptions to the "no host access" posture described in the header: the
    # shell-exec policy, plus ways to hand the agent specific files and specific
    # root commands, and nothing more. All are prompt-injectable surface — grant
    # the minimum.

    exec = {
      # Shell-exec policy. These map to tools.exec.* and are pinned in the
      # enforced config layer (re-asserted every start), so the agent cannot
      # relax them at runtime; the host tunes them here. Everyday chat is
      # unaffected — this only gates the exec (shell) tool.
      security = lib.mkOption {
        type = lib.types.enum [ "deny" "allowlist" "full" ];
        default = "allowlist";
        description = ''
          Exec security posture. "deny" blocks the shell tool entirely,
          "allowlist" runs only allowlisted commands unprompted (everything else
          is a miss, gated by `ask`), and "full" runs anything without gating.
          Keep "allowlist" for a prompt-injectable agent.
        '';
      };
      ask = lib.mkOption {
        type = lib.types.enum [ "off" "on-miss" "always" ];
        default = "on-miss";
        description = ''
          When to ask for human confirmation before running an exec command.
          "on-miss" prompts for anything not on the allowlist (`safeBins` plus
          the per-agent runtime allowlist), "always" prompts for everything, and
          "off" never prompts. The prompt surfaces in the originating channel
          (e.g. the Telegram DM) and is answered inline.
        '';
      };
      strictInlineEval = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Require explicit approval for interpreter inline-eval forms (`python
          -c`, `node -e`, `ruby -e`, `osascript -e`), even if the interpreter is
          otherwise allowlisted — so an allowed interpreter cannot smuggle
          arbitrary code past the gate. Leave on unless it is too much friction.
        '';
      };
      safeBins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          # Read-only inspection commands: no filesystem mutation, no exec of
          # other programs, no network. These run unprompted under "allowlist".
          # Anything that writes, deletes, forks a shell, evaluates code, or hits
          # the network is DELIBERATELY absent (sed -i / awk system() / find
          # -exec / xargs / tee / cp / mv / rm / env / curl / git / interpreters
          # …) — those stay gated by `ask`. Append project-specific safe commands
          # in the host config rather than editing this default.
          "cat" "head" "tail" "nl" "wc" "ls" "pwd" "stat" "file" "tree"
          "du" "df" "free" "uptime" "date" "uname" "hostname" "whoami" "id"
          "groups" "which" "printenv" "echo" "grep" "egrep" "fgrep" "rg" "jq"
          "cut" "sort" "uniq" "column" "basename" "dirname" "realpath"
          "readlink" "diff" "comm" "sha256sum" "md5sum" "cksum"
        ];
        description = ''
          Binaries allowed to run WITHOUT an explicit per-agent allowlist entry
          under `security = "allowlist"` — the declarative "what's safe to run"
          list. Defaults to a conservative read-only set; the host replaces or
          extends it (e.g. `safeBins = options.my.openclaw.exec.safeBins.default
          ++ [ "Rscript" ];`). Pinned authoritatively, so the agent cannot add to
          it at runtime. For arg/flag-level constraints on a binary, use
          `safeBinProfiles`.
        '';
      };
      safeBinProfiles = lib.mkOption {
        type = settingsFormat.type;
        default = { };
        example = lib.literalExpression ''
          {
            # allow `git` only with read-only subcommands, no flags that write
            git = { maxPositional = 3; allowedValueFlags = [ ]; deniedFlags = [ "--exec" ]; };
          }
        '';
        description = ''
          Optional per-binary safe-bin profiles (positional-argument limits plus
          allowed/denied flags), mapped straight to tools.exec.safeBinProfiles.
          Use this to admit a binary to `safeBins` only in a constrained form.
          Freeform to track the upstream schema; run `openclaw config schema`.
        '';
      };
      allowlist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "git status*" "git diff*" "systemctl status*" ];
        description = ''
          Glob patterns pre-seeded into the agent's exec-approval allowlist at
          service start (via `openclaw approvals allowlist add`, for all agents).
          Unlike safeBins (whole-binary), these match the FULL command line, so
          you can bless a read-only SUBCOMMAND — e.g. "git status*" without
          blessing every git invocation. Seeding MERGES (the agent's own
          approve-and-remember additions are preserved) and is idempotent, so it
          is safely re-applied every start. Prefer forms that cannot mutate:
          "git branch*" would also match `git branch -D`, so bless specific
          read-only subcommands, not whole verbs with mutating flags.
        '';
      };
    };

    access = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          permissions = lib.mkOption {
            type = lib.types.str;
            default = "rwX";
            example = "rX";
            description = ''
              ACL permission bits to grant the agent on this path, in setfacl(1)
              syntax. "rwX" is read/write plus execute/search only where it
              already applies (directories and already-executable files) — the
              capital X is what stops it from marking every data file
              executable. Use "rX" for read-only access.
            '';
          };
          recursive = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Apply the ACL to everything already under this path (setfacl -R),
              not just the path itself. Set this for a directory whose existing
              contents the agent should reach.
            '';
          };
          defaultAcl = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Also set a default ACL on this directory (setfacl -d), so entries
              created under it later inherit the same grant. Without it, only
              what exists at activation time is covered; new files created by
              other users would not be readable to the agent.
            '';
          };
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          "/srv/share" = { permissions = "rwX"; recursive = true; defaultAcl = true; };
          "/etc/some-config.toml" = { permissions = "rX"; };
        }
      '';
      description = ''
        Filesystem paths the agent is granted access to via POSIX ACLs, keyed by
        path. This adds a `user:<agent>:<perms>` ACL entry with setfacl on each
        activation (a oneshot ordered before the service), leaving the path's
        owner and group untouched — it is additive access, not a chown. Use it to
        hand the agent a shared directory or a specific file without making it a
        member of that resource's group.

        The grant is only ever added, never removed: dropping a path here leaves
        the ACL it set in place (clear it by hand with `setfacl -x`). Every path
        here is reachable by anything that reaches the agent, which is
        prompt-injectable — grant the narrowest path and permissions that work.
      '';
    };

    sudoCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        [
          "/run/current-system/sw/bin/systemctl restart some.service"
          "/run/current-system/sw/bin/systemctl start another.service"
        ]
      '';
      description = ''
        Commands the agent may run through sudo (as root) without a password.
        Each entry is a sudoers command spec: an absolute path, optionally
        followed by the exact arguments it is allowed. A path with no arguments
        permits ANY arguments; append `""` to forbid arguments entirely; a bare
        directory (trailing slash) permits anything inside it.

        PREFER exact paths with fixed arguments over open command names or
        wildcards. This account is prompt-injectable (see the header), so every
        entry here is something an attacker who reaches the agent can run as
        root — grant the single narrowest command that does the job.
      '';
    };

    # The bot token and the allowed ID are never Nix VALUES (public repo) — they
    # come in as runtime files via my.openclaw.telegram.{tokenFile,allowedIdFile}
    # above, sourced from whatever secret system the host uses.
  };

  config = lib.mkIf cfg.enable {
    # Upstream flags this package insecure on purpose. Acknowledge explicitly;
    # bump the version suffix when the packaged OpenClaw is updated.
    nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.5.7" ];

    environment.systemPackages = [ openclawPatched pkgs.claude-code ];

    users.users.${cfg.user} = {
      isNormalUser = true;
      group = cfg.user;
      home = homeDir;
      createHome = true;
      shell = pkgs.bashInteractive;
      description = "OpenClaw agent";
      # Local-only identity: no password, no keys, and sshd refuses it outright
      # (below), so the account can be inhabited from a root session on this box
      # and nowhere else. `!` is an invalid hash — it matches nothing.
      hashedPassword = "!";
      openssh.authorizedKeys.keys = [ ];
    };
    users.groups.${cfg.user} = { };

    # Read access to the agent's service state for principals who should be
    # able to inspect it without becoming the agent. Deliberately NOT the
    # agent's primary group — it owns its files as itself, and this is only an
    # ACL over the state tree. Join it with users.users.<name>.extraGroups.
    users.groups.openclaw = { };

    # Belt and braces on top of the empty password/key set: an authorized_keys
    # file or password added later cannot silently open remote access. Covers
    # mosh too, which authenticates over ssh. Act as the agent with
    # `sudo -u <user> -H ...`.
    services.openssh.settings.DenyUsers = [ cfg.user ];

    # Passwordless sudo for exactly the commands listed in cfg.sudoCommands and
    # nothing else. NOPASSWD is required because the account has no password (`!`
    # above), so it could not answer a prompt even if asked.
    security.sudo.extraRules = lib.mkIf (cfg.sudoCommands != [ ]) [
      {
        users = [ cfg.user ];
        commands = map (command: { inherit command; options = [ "NOPASSWD" ]; }) cfg.sudoCommands;
      }
    ];

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
      "d ${stateDir} 2750 ${cfg.user} openclaw -"
      "Z ${stateDir} - ${cfg.user} openclaw -"
    ];

    # Grant the agent ACL access to cfg.access paths. This is an ACTIVATION
    # SCRIPT, not a oneshot service, and it matters: activation scripts run on
    # EVERY `nixos-rebuild switch` and boot, whereas NixOS only re-runs an
    # unchanged oneshot on reboot — so with a service, a switch would leave a
    # broken grant unrepaired. `deps = [ "users" ]` orders it AFTER the users
    # activation, which chmods home dirs to their homeMode (e.g. /home/alex to
    # 0700) and in doing so recomputes any POSIX ACL mask to `---`, silently
    # neutering a `u:<agent>:X` traversal grant (the entry stays, effective
    # becomes ---). Re-running setfacl here restores both the entry and the
    # mask on every switch. A bad path just logs and does not abort activation.
    system.activationScripts.openclaw-grant-access = lib.mkIf (cfg.access != { }) {
      deps = [ "users" ];
      text = lib.concatStrings (lib.mapAttrsToList (path: opts:
        let rec' = lib.optionalString opts.recursive "-R "; in
        ''
          ${pkgs.acl}/bin/setfacl ${rec'}-m u:${cfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
            || echo "[openclaw] WARN: setfacl grant failed for ${path}" >&2
        '' + lib.optionalString opts.defaultAcl ''
          ${pkgs.acl}/bin/setfacl ${rec'}-d -m u:${cfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
            || echo "[openclaw] WARN: default-ACL grant failed for ${path}" >&2
        '') cfg.access);
    };

    systemd.services.openclaw = {
      description = "OpenClaw agent gateway (Telegram-only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # `claude` must be on PATH for the claude-cli runtime (subscription auth);
      # the rest is what the agent's own shell tooling generally expects.
      path = [ pkgs.claude-code pkgs.git pkgs.bash pkgs.coreutils ];

      environment = {
        HOME = homeDir;
        OPENCLAW_STATE_DIR = stateDir;
        OPENCLAW_CONFIG_PATH = configFile;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.user;

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
          if [ -r ${lib.escapeShellArg cfg.telegram.allowedIdFile} ]; then
            while IFS= read -r line || [ -n "$line" ]; do
              line=''${line//[[:space:]]/}
              [ -z "$line" ] && continue
              case "$line" in \#*) continue ;; esac
              ids="$ids''${ids:+,}\"$line\""
            done < ${lib.escapeShellArg cfg.telegram.allowedIdFile}
          fi
          if [ -z "$ids" ]; then
            echo "[openclaw] WARN: no Telegram ID in ${cfg.telegram.allowedIdFile}; allowlist stays empty (bot answers no one)" >&2
          fi
          printf '{"channels":{"telegram":{"allowFrom":[%s]}},"commands":{"ownerAllowFrom":[%s]}}' "$ids" "$ids" \
            | ${lib.getExe openclawPatched} config patch --stdin

          # (3) Seed the operator-declared exec-approval globs (single jq merge).
          ${allowlistSeedMerge}
        '';
        ExecStart = "${lib.getExe openclawPatched} gateway";
        Restart = "on-failure";
        RestartSec = 5;
        # The seed above is now two fast config patches plus one jq merge, but
        # keep a margin over systemd's 90s default so a momentarily loaded box
        # never times the gateway out before it binds.
        TimeoutStartSec = 180;

        LoadCredential = [
          "telegram-token:${cfg.telegram.tokenFile}"
        ];

        # Extra env for provider API keys (Gemini fallback, ElevenLabs TTS, …),
        # supplied as files from outside the module. Empty by default.
        EnvironmentFile = cfg.environmentFiles;

        # No StateDirectory=: systemd would chown the tree to User:Group, i.e.
        # the agent's own group, and there is no way to ask it for a different
        # group. tmpfiles owns the directory instead (see above).
        WorkingDirectory = stateDir;
        # 0640 files / 0750 dirs, so the openclaw group can read what the agent
        # writes below the state dir. Its home stays 0700 regardless.
        UMask = "0027";
      };
    };
  };
}
