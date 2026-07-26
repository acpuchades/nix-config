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
#     disabled, and the bot token never touches the store or the repo. OpenClaw
#     rewrites its own config file at runtime, so it is re-seeded (overwritten)
#     on every start to keep this authoritative.
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

  # Opsec: the allowed Telegram ID is treated as a secret even though it isn't a
  # credential — it's rendered from SOPS at activation, so it never appears in
  # the repo or the world-readable /nix/store. This placeholder is substituted
  # with openclaw/telegram-userid when the config template is rendered.
  telegramIdPlaceholder = config.sops.placeholder."openclaw/telegram-userid";

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
      allowFrom = [ telegramIdPlaceholder ];
      groupPolicy = "disabled";
    };
    commands.ownerAllowFrom = [ telegramIdPlaceholder ];
  };

  fullConfig =
    lib.recursiveUpdate (lib.recursiveUpdate defaultConfig cfg.settings) enforcedConfig;

  # Rendered by sops-nix (real ID substituted) to a /run path owned by openclaw.
  configTemplateName = "openclaw/config.json";
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
        Authoritative, declarative OpenClaw configuration, deep-merged into
        openclaw.json. Because the config file is re-seeded from Nix on every
        start, THIS is where persistent configuration goes — `openclaw
        configure` / `config set` and any config the agent writes at runtime are
        overwritten on the next restart. Run `openclaw config schema` to see the
        full key set.

        Precedence: module defaults < this < enforced security keys. The
        security-critical keys (gateway.bind/mode, the Telegram allowlist,
        dmPolicy/groupPolicy, ownerAllowFrom) are forced on top and cannot be
        overridden here, so a mistaken value cannot open access.

        Note: agent *skills* live in the workspace (and any skills.load.extraDirs
        above) and persist independently of this file — the agent can still add
        its own skills; only openclaw.json is Nix-authoritative.
      '';
    };

    # The allowed Telegram user ID is NOT a Nix option — public repo, so it is
    # sourced from SOPS (openclaw/telegram-userid) and rendered into the config
    # at activation. Get your ID from @userinfobot.
  };

  config = lib.mkIf cfg.enable {
    # Upstream flags this package insecure on purpose. Acknowledge explicitly;
    # bump the version suffix when the packaged OpenClaw is updated.
    nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.5.7" ];

    environment.systemPackages = [ cfg.package pkgs.claude-code ];

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

    # Populate before switching:  sops machines/homeserver/secrets/default.yml
    #   openclaw/telegram-token  -> BotFather token
    #   openclaw/telegram-userid -> your numeric Telegram user ID (allowlist)
    sops.secrets = {
      "openclaw/telegram-token" = { mode = "0400"; };
      "openclaw/telegram-userid" = { mode = "0400"; };
    };

    # openclaw.json rendered with the real Telegram ID substituted in, to a
    # /run path readable only by the agent — never the store, never the repo.
    sops.templates.${configTemplateName} = {
      owner = cfg.user;
      mode = "0400";
      content = builtins.toJSON fullConfig;
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

        # Removed first so the file is always created fresh inside the setgid
        # state dir, and therefore lands in the openclaw group — `install` would
        # otherwise preserve an existing file's ownership.
        ExecStartPre = pkgs.writeShellScript "openclaw-seed-config" ''
          set -euo pipefail
          rm -f ${configFile}
          install -m 0640 ${config.sops.templates.${configTemplateName}.path} ${configFile}
        '';
        ExecStart = "${lib.getExe cfg.package} gateway";
        Restart = "on-failure";
        RestartSec = 5;

        LoadCredential = [
          "telegram-token:${config.sops.secrets."openclaw/telegram-token".path}"
        ];

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
