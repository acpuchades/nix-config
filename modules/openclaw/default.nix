{
  config,
  lib,
  pkgs,
  ...
}:

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
#   * WHAT IT CAN DO TO THE HOST — bounded per instance. Upstream marks this
#     package `knownVulnerabilities` (an LLM parses untrusted content →
#     prompt-injectable), acknowledged in ./instance.nix via permittedInsecurePackages, so
#     the module confines what an injected agent can reach: a systemd sandbox
#     (writes only to its own trees), optional egress filtering through an
#     allowlisting proxy (`egress`), credential-using wrappers (mail) run
#     through a shared broker account (`openclaw-secrets`) that holds the
#     secrets the agent never sees, and sudo limited to `sudoCommands`.
#
# Auth uses a Claude subscription rather than an Anthropic API key: OpenClaw
# reuses a Claude Code CLI login on this host (`claude -p`), selected by the
# `agentRuntime` option (./instance-options.nix). Log in once as the agent's own user:
#
#   sudo -u <user> -H claude            # /login, then quit
#   systemctl restart openclaw
#
# That writes ~/.claude/.credentials.json, which OpenClaw picks up. On a box
# where the browser flow is awkward, `claude setup-token` yields a long-lived
# token instead — put it in the state dir's .env as CLAUDE_CODE_OAUTH_TOKEN.
#
# Layout: this file holds the module-wide options and merges one fragment per
# instance. ./instance-options.nix is the per-instance option schema,
# ./instance.nix builds an instance's fragment (config seeding, skills staging,
# egress, the gateway unit), ./instance-actions.nix its action wrappers, and
# ./actions + ./skills the scripts and SKILL.md generators those use.
#

let
  cfg = config.my.openclaw;

  # Freeform JSON so my.openclaw.settings can express any key in openclaw.json
  # (see `openclaw config schema`) without the module having to model each one.
  settingsFormat = pkgs.formats.json { };

  # Default read-only safeBins set (exposed via
  # options.my.openclaw.defaultSafeBins so a host can do `defaultSafeBins ++
  # [ ... ]` when overriding a per-instance exec.safeBins).
  defaultSafeBins = [
    # Read-only inspection commands: no filesystem mutation, no exec of
    # other programs, no network. These run unprompted under "allowlist".
    # Anything that writes, deletes, forks a shell, evaluates code, or hits
    # the network is DELIBERATELY absent (sed -i / awk system() / find
    # -exec / xargs / tee / cp / mv / rm / env / curl / git / interpreters
    # …) — those stay gated by `ask`. Append project-specific safe commands
    # in the host config rather than editing this default.
    "cat"
    "head"
    "tail"
    "nl"
    "wc"
    "ls"
    "pwd"
    "stat"
    "file"
    "tree"
    "du"
    "df"
    "free"
    "uptime"
    "date"
    "uname"
    "hostname"
    "whoami"
    "id"
    "groups"
    "which"
    "printenv"
    "echo"
    "grep"
    "egrep"
    "fgrep"
    "rg"
    "jq"
    "cut"
    "sort"
    "uniq"
    "column"
    "basename"
    "dirname"
    "realpath"
    "readlink"
    "diff"
    "comm"
    "sha256sum"
    "md5sum"
    "cksum"
  ];

  # Per-instance NixOS config fragment (./instance.nix).
  mkInstance = import ./instance.nix {
    inherit
      config
      lib
      pkgs
      cfg
      settingsFormat
      defaultSafeBins
      ;
  };

  enabledInstances = lib.filterAttrs (_: i: i.enable) cfg.instances;

  # Per-instance option schema (./instance-options.nix).
  instanceModule = import ./instance-options.nix {
    inherit
      config
      lib
      pkgs
      settingsFormat
      defaultSafeBins
      ;
  };
in
{
  options.my.openclaw = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw;
      defaultText = lib.literalExpression "pkgs.openclaw";
      description = "OpenClaw package to run.";
    };

    egressProxy.port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Loopback port of the egress-filtering proxy (instances with egress.enable).";
    };

    defaultSafeBins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = defaultSafeBins;
      description = ''
        The module's default read-only safeBins set, exposed so host configs
        can write `exec.safeBins = config.my.openclaw.defaultSafeBins ++ [ ... ]`
        when extending a per-instance allowlist.
      '';
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = ''
        OpenClaw agent instances, keyed by name. Each entry is an independent
        agent with its OWN OS user, home, memory/state dir, Telegram bot and
        loopback gateway service: openclaw-<name>.service, state under
        /var/lib/openclaw/<name>, home at /home/<user>. Agents share only the
        `package` build; their memory, exec policy, sudo grants, ACLs and mail
        identity are fully separate. See the module header for the security
        model, which applies per instance.
      '';
    };
  };

  # The module's `config` MUST expose a STATIC set of top-level attribute names
  # ({ users, systemd, environment, security, system, nixpkgs, services,
  # assertions }) that does NOT depend on evaluating `cfg.instances`. If the
  # top-level shape were derived from the instances (e.g. `mkMerge (mapAttrsToList
  # mkInstance cfg.instances)`), the module system's unmatched-definition check —
  # which needs this module's contributed attr NAMES — would force
  # `cfg.instances`, which builds the submodules, whose own `_module` check forces
  # `config.my.openclaw` again: an infinite recursion (`config → cfg.instances →
  # submodule → config`). Fixing the top-level keys and pulling the per-instance
  # fragments into each key's VALUE only (via `onKey`) keeps the name-level check
  # from forcing the instances; the values are forced later, after options settle.
  # Each fragment is still gated by `lib.mkIf icfg.enable` so a disabled instance
  # contributes nothing.
  config =
    let
      frags = lib.mapAttrsToList (name: icfg: {
        inherit icfg;
        frag = mkInstance name icfg;
      }) cfg.instances;
      egressInstances = lib.mapAttrs (name: icfg: (mkInstance name icfg).egress) (
        lib.filterAttrs (_: i: i.enable && i.egress.enable) cfg.instances
      );
      onKey = key: lib.mkMerge (map (e: lib.mkIf e.icfg.enable e.frag.${key}) frags);
    in
    {
      users = onKey "users";
      systemd = onKey "systemd";
      environment = onKey "environment";
      security = onKey "security";
      system = onKey "system";
      nixpkgs = onKey "nixpkgs";
      services = lib.mkMerge [
        (onKey "services")
        {
          # One filtering proxy for every instance with egress.enable; its
          # allowlist is the union of theirs.
          tinyproxy = lib.mkIf (egressInstances != { }) {
            enable = true;
            settings = {
              Listen = "127.0.0.1";
              Port = cfg.egressProxy.port;
              Allow = [ "127.0.0.1" ];
              ConnectPort = [ 443 ];
              DisableViaHeader = true;
              FilterType = "fnmatch";
              FilterDefaultDeny = true;
              FilterURLs = false;
              Filter = pkgs.writeText "openclaw-egress-allowlist" (
                lib.concatMapStrings (d: d + "\n") (
                  lib.unique (lib.concatMap (i: i.egressDomains) (lib.attrValues egressInstances))
                )
              );
            };
          };
        }
      ];
      networking = onKey "networking";

      assertions = lib.mkMerge (
        (map (e: lib.mkIf e.icfg.enable e.frag.assertions) frags)
        ++ [
          [
            {
              assertion =
                let
                  ports = map (i: i.port) (lib.attrValues enabledInstances);
                in
                lib.length ports == lib.length (lib.unique ports);
              message = "my.openclaw.instances: each enabled instance needs a UNIQUE loopback `port` — two gateways cannot bind the same port.";
            }
            {
              assertion =
                let
                  users = map (i: i.user) (lib.attrValues enabledInstances);
                in
                lib.length users == lib.length (lib.unique users);
              message = "my.openclaw.instances: each enabled instance needs a UNIQUE `user` — agents must not share a home/state dir.";
            }
          ]
        ]
      );
    };
}
