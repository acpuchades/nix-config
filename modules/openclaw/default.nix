{ config, lib, pkgs, ... }:

#
# openclaw — self-hosted LLM agent (OpenClaw), run confined on the homeserver
# and reachable ONLY through Telegram (long-polling; no inbound port). The
# gateway/control UI is bound to loopback so it is reachable locally but never
# from the LAN.
#
# Posture (chosen deliberately): a "contained sysadmin" agent.
#   * It may NOT author or activate this host's nix-config. Letting an LLM write
#     config AND switch is arbitrary-root; that capability is intentionally
#     absent.
#   * It MAY do bounded sysadmin: read the full journal + Prometheus stats,
#     manage systemd units, reboot, garbage-collect, trigger backups/snapshots,
#     and trigger a SEALED system update. None of these let the agent run
#     agent-authored code as root.
#
# Hard boundary = the OS sandbox, not OpenClaw's own settings. Upstream marks
# this package `knownVulnerabilities` (LLM parses untrusted content with full
# system access by default → prompt-injectable), so it is treated as hostile:
# a dedicated unprivileged user, aggressive systemd sandbox, loopback + Telegram
# egress only. Privileged actions run in SEPARATE units the sandboxed agent may
# only *trigger* over D-Bus (polkit) — the agent itself never gains privileges,
# so the base sandbox stays fully intact regardless of which grants are on.
#
# Residual risk to accept: the agent needs internet egress (Anthropic API +
# Telegram), and with broad read grants a fully prompt-injected agent could
# exfiltrate what it can read. Blast radius is read + bounded-ops, NOT arbitrary
# root — recoverable without rebuilding the host or rotating every secret.
#
# The "update" grant: the agent may trigger `openclaw-update.service`, which as
# root runs a FIXED `nix flake update && nixos-rebuild switch` against a
# root-owned flake checkout the agent cannot write. The agent chooses *when* to
# update, never *what* — it cannot inject config. Trust shifts to upstream
# nixpkgs (already trusted); the agent's power is limited to "force an upgrade".
#

let
  cfg = config.my.openclaw;
  g = cfg.grants;

  stateDir = "/var/lib/openclaw";
  configFile = "${stateDir}/openclaw.json";
  credDir = "/run/credentials/openclaw.service";

  hostName = config.networking.hostName;

  # A JS array literal from a Nix list of strings, for the polkit rule.
  jsArray = xs: "[" + lib.concatMapStringsSep ", " (x: "\"${x}\"") xs + "]";

  # Opsec: the allowed Telegram ID is treated as a secret even though it isn't a
  # credential — it's rendered from SOPS at activation, so it never appears in
  # the repo or the world-readable /nix/store. This placeholder is substituted
  # with openclaw/telegram-userid when the config template is rendered.
  telegramIdPlaceholder = config.sops.placeholder."openclaw/telegram-userid";

  # Declarative base config. OpenClaw rewrites its own config file at runtime,
  # so we re-seed it (overwrite) on every start to keep this authoritative.
  # Access is locked to an explicit numeric-ID allowlist; groups disabled.
  baseConfig = {
    gateway = {
      bind = "127.0.0.1";
      port = cfg.port;
    };
    agents.defaults = {
      model.primary = cfg.model;
      workspace = "${stateDir}/workspace";
    };
    channels.telegram = {
      enabled = true;
      tokenFile = "${credDir}/telegram-token"; # real file (symlinks rejected)
      dmPolicy = "allowlist";
      allowFrom = [ telegramIdPlaceholder ];
      groupPolicy = "disabled";
    };
    commands.ownerAllowFrom = [ telegramIdPlaceholder ];
  };

  # Rendered by sops-nix (real ID substituted) to a /run path owned by openclaw.
  configTemplateName = "openclaw/config.json";

  startScript = pkgs.writeShellScript "openclaw-start" ''
    set -euo pipefail
    export ANTHROPIC_API_KEY="$(< "$CREDENTIALS_DIRECTORY/anthropic-key")"
    exec ${lib.getExe pkgs.openclaw} gateway
  '';

  # Units the sandboxed agent is allowed to manage via polkit: the grant
  # trigger-units it may start, plus any explicit service/backup allowlists.
  triggerUnits =
    (lib.optional g.gcCollect.enable "openclaw-gc.service")
    ++ (lib.optional g.btrfsSnapshot.enable "openclaw-btrfs-snapshot.service")
    ++ (lib.optional g.update.enable "openclaw-update.service");

  manageableUnits =
    triggerUnits
    ++ (lib.optionals (g.serviceControl.enable && g.serviceControl.units != [ ]) g.serviceControl.units)
    ++ (lib.optionals g.backupTrigger.enable g.backupTrigger.units);

  # serviceControl with an empty allowlist == manage ANY unit (broad sysadmin).
  serviceControlAll = g.serviceControl.enable && g.serviceControl.units == [ ];
  usePolkit = manageableUnits != [ ] || serviceControlAll || g.rebootHost;
in
{
  options.my.openclaw = {
    enable = lib.mkEnableOption "Confined OpenClaw agent (Telegram-only, loopback gateway)";

    model = lib.mkOption {
      type = lib.types.str;
      default = "anthropic/claude-sonnet-4-6";
      description = "Primary model, as provider/model. Uses the Anthropic key from SOPS.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = ''
        Loopback port for the gateway / control UI. Bound to 127.0.0.1 only —
        never opened in the firewall. Reach it locally (e.g. via SSH tunnel).
      '';
    };

    # The allowed Telegram user ID is NOT a Nix option — public repo, so it is
    # sourced from SOPS (openclaw/telegram-userid) and rendered into the config
    # at activation. Get your ID from @userinfobot.

    observability = {
      enable = lib.mkEnableOption ''
        read-only observability: full systemd journal (all units) + Prometheus
        metrics, so the agent can track logs and system stats. This is a READ
        widening, not escalation — the agent still cannot change the system
      '';
      prometheusUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9090";
        description = "Prometheus base URL, exposed to the agent as $OPENCLAW_PROMETHEUS_URL.";
      };
      grafana = {
        enable = lib.mkEnableOption "Grafana API access (needs a read-only token in SOPS: openclaw/grafana-token)";
        url = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:3001";
          description = "Grafana base URL, exposed to the agent as $OPENCLAW_GRAFANA_URL.";
        };
      };
    };

    # Bounded sysadmin capabilities, each OFF by default. None grant
    # agent-authored code execution as root.
    grants = {
      serviceControl = {
        enable = lib.mkEnableOption "start/stop/restart systemd units (real sysadmin)";
        units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "jellyfin.service" "transmission.service" ];
          description = ''
            Units the agent may start/stop/restart. EMPTY means ANY unit (broad
            sysadmin — it can also stop security services, so treat as powerful);
            a non-empty list restricts to exactly those units.
          '';
        };
      };

      rebootHost = lib.mkEnableOption "reboot / power off the machine on demand";

      gcCollect = {
        enable = lib.mkEnableOption "run `nix-collect-garbage` on demand";
        olderThan = lib.mkOption {
          type = lib.types.str;
          default = "30d";
          description = "Passed to `nix-collect-garbage --delete-older-than`.";
        };
      };

      backupTrigger = {
        enable = lib.mkEnableOption "trigger an allowlist of backup/job units on demand";
        units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "restic-backups-main.service" ];
          description = "Backup/oneshot units the agent may start (start only).";
        };
      };

      btrfsSnapshot = {
        enable = lib.mkEnableOption "take a read-only btrfs snapshot on demand";
        subvolume = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/srv/encrypted";
          description = "Subvolume to snapshot (read-only). Required when enabled.";
        };
        snapshotDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/snapshots/openclaw";
          description = "Directory to place timestamped snapshots in.";
        };
      };

      update = {
        enable = lib.mkEnableOption ''
          trigger a SEALED system update: as root, `nix flake update` +
          `nixos-rebuild switch` on a ROOT-OWNED flake the agent cannot write.
          The agent picks when, never what — it cannot inject config
        '';
        flakePath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/etc/nixos";
          description = ''
            Root-owned checkout of your nix-config that the sealed updater runs
            in. MUST NOT be writable by the openclaw user (or update collapses
            back into arbitrary-root). Required when this grant is enabled.
          '';
        };
      };

      mediaLibrary = {
        enable = lib.mkEnableOption "read/write access to specific media directories";
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/srv/media/library" "/srv/downloads" ];
          description = "Directories added to the agent's writable sandbox. Nothing else.";
        };
      };

      adguardRules = {
        enable = lib.mkEnableOption "manage AdGuard Home filtering rules via its API";
        apiBaseUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:3000";
          description = ''
            AdGuard control API base URL, exposed as $OPENCLAW_ADGUARD_URL. NOTE:
            hands the agent AdGuard admin creds (SOPS: openclaw/adguard-auth);
            API auth is not per-endpoint, so this is broad AdGuard control.
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !g.update.enable || g.update.flakePath != null;
        message = "my.openclaw.grants.update requires grants.update.flakePath (a root-owned nix-config checkout).";
      }
      {
        assertion = !g.update.enable || !(lib.hasPrefix stateDir (toString g.update.flakePath));
        message = "my.openclaw.grants.update.flakePath must be root-owned and outside the agent's state dir, or update becomes arbitrary-root.";
      }
      {
        assertion = !g.btrfsSnapshot.enable || g.btrfsSnapshot.subvolume != null;
        message = "my.openclaw.grants.btrfsSnapshot requires grants.btrfsSnapshot.subvolume.";
      }
    ];

    # Upstream flags this package insecure on purpose. Acknowledge explicitly;
    # bump the version suffix when the packaged OpenClaw is updated.
    nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.5.7" ];

    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      home = stateDir;
      description = "OpenClaw agent";
      # Full journal read for observability is a group membership, not a write.
      extraGroups = lib.optional cfg.observability.enable "systemd-journal";
    };
    users.groups.openclaw = { };

    # Secrets live in this module so they only exist when the agent is enabled.
    # Populate before switching:  sops machines/homeserver/secrets/default.yml
    #   openclaw/anthropic-key   -> Anthropic API key
    #   openclaw/telegram-token  -> BotFather token
    #   openclaw/telegram-userid -> your numeric Telegram user ID (allowlist)
    #   openclaw/grafana-token   -> (only if observability.grafana) read-only token
    #   openclaw/adguard-auth    -> (only if grants.adguardRules) AdGuard creds
    sops.secrets =
      {
        "openclaw/anthropic-key" = { mode = "0400"; };
        "openclaw/telegram-token" = { mode = "0400"; };
        "openclaw/telegram-userid" = { mode = "0400"; };
      }
      // lib.optionalAttrs (cfg.observability.enable && cfg.observability.grafana.enable) {
        "openclaw/grafana-token" = { mode = "0400"; };
      }
      // lib.optionalAttrs g.adguardRules.enable {
        "openclaw/adguard-auth" = { mode = "0400"; };
      };

    # openclaw.json rendered with the real Telegram ID substituted in, to a
    # /run path readable only by the agent — never the store, never the repo.
    sops.templates.${configTemplateName} = {
      owner = "openclaw";
      mode = "0400";
      content = builtins.toJSON baseConfig;
    };

    systemd.services.openclaw = {
      description = "OpenClaw agent (confined, Telegram-only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        User = "openclaw";
        Group = "openclaw";

        ExecStartPre = pkgs.writeShellScript "openclaw-seed-config" ''
          set -euo pipefail
          install -m 0600 ${config.sops.templates.${configTemplateName}.path} ${configFile}
        '';
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 5;

        StateDirectory = "openclaw";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;

        Environment =
          [ "OPENCLAW_CONFIG_PATH=${configFile}" ]
          ++ lib.optional cfg.observability.enable "OPENCLAW_PROMETHEUS_URL=${cfg.observability.prometheusUrl}"
          ++ lib.optional (cfg.observability.enable && cfg.observability.grafana.enable) "OPENCLAW_GRAFANA_URL=${cfg.observability.grafana.url}"
          ++ lib.optional g.adguardRules.enable "OPENCLAW_ADGUARD_URL=${g.adguardRules.apiBaseUrl}";

        LoadCredential =
          [
            "anthropic-key:${config.sops.secrets."openclaw/anthropic-key".path}"
            "telegram-token:${config.sops.secrets."openclaw/telegram-token".path}"
          ]
          ++ lib.optional (cfg.observability.enable && cfg.observability.grafana.enable)
            "grafana-token:${config.sops.secrets."openclaw/grafana-token".path}"
          ++ lib.optional g.adguardRules.enable
            "adguard-auth:${config.sops.secrets."openclaw/adguard-auth".path}";

        # --- Sandbox. Intact regardless of grants: privileged work happens in
        # separate units triggered over D-Bus, needing neither setuid nor new
        # privileges here. ---
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        # Observability wants system-wide process visibility: /proc/<pid> for
        # ALL processes (cmdlines, per-process cpu/mem). Reading another user's
        # /proc/<pid>/environ still needs CAP_SYS_PTRACE we don't have, so
        # env-borne secrets stay protected. Tight (own-procs-only) when off.
        ProtectProc = if cfg.observability.enable then "default" else "invisible";
        # Keep the non-pid /proc files (meminfo, stat, ...) readable regardless.
        ProcSubset = "all";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # V8 JIT needs W+X pages
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallFilter = [ "@system-service" ];
        SystemCallArchitectures = "native";
        ReadWritePaths = [ stateDir ] ++ lib.optionals g.mediaLibrary.enable g.mediaLibrary.paths;
        UMask = "0077";
      };
    };

    # ---- Privileged trigger units (root, unsandboxed; agent may only start) ----
    systemd.services.openclaw-gc = lib.mkIf g.gcCollect.enable {
      description = "nix garbage collection (agent-triggered)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.nix.package}/bin/nix-collect-garbage --delete-older-than ${g.gcCollect.olderThan}";
      };
    };

    systemd.services.openclaw-btrfs-snapshot = lib.mkIf g.btrfsSnapshot.enable {
      description = "read-only btrfs snapshot (agent-triggered)";
      path = [ pkgs.btrfs-progs pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-btrfs-snap" ''
          set -euo pipefail
          ts="$(date +%Y%m%d-%H%M%S)"
          mkdir -p "${g.btrfsSnapshot.snapshotDir}"
          exec btrfs subvolume snapshot -r "${toString g.btrfsSnapshot.subvolume}" \
            "${g.btrfsSnapshot.snapshotDir}/openclaw-$ts"
        '';
      };
    };

    # Sealed updater: fixed command on a ROOT-OWNED flake the agent cannot write.
    systemd.services.openclaw-update = lib.mkIf g.update.enable {
      description = "Sealed system update: flake update + switch (agent-triggered)";
      path = [ pkgs.nixos-rebuild pkgs.git config.nix.package ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-update" ''
          set -euo pipefail
          cd "${toString g.update.flakePath}"
          echo "openclaw-triggered update of ${toString g.update.flakePath}#${hostName}"
          nix flake update
          exec nixos-rebuild switch --flake "${toString g.update.flakePath}#${hostName}"
        '';
      };
    };

    # Let ONLY the openclaw user manage the allowed units / reboot — via polkit,
    # so the agent keeps NoNewPrivileges (no sudo, no setuid).
    security.polkit.extraConfig = lib.mkIf usePolkit ''
      polkit.addRule(function(action, subject) {
        if (subject.user != "openclaw") { return polkit.Result.NOT_HANDLED; }
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          ${lib.optionalString serviceControlAll "return polkit.Result.YES;"}
          var allowed = ${jsArray manageableUnits};
          if (allowed.indexOf(action.lookup("unit")) >= 0) { return polkit.Result.YES; }
        }
        ${lib.optionalString g.rebootHost ''
          if (action.id == "org.freedesktop.login1.reboot" ||
              action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
              action.id == "org.freedesktop.login1.power-off" ||
              action.id == "org.freedesktop.login1.power-off-multiple-sessions") {
            return polkit.Result.YES;
          }
        ''}
        return polkit.Result.NOT_HANDLED;
      });
    '';
  };
}
