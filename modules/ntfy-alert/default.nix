{ config, lib, pkgs, ... }:

#
# ntfy-alert — opt-in push alerts to the self-hosted ntfy server.
#
# This module ONLY provides mechanism; it forces alerting on nothing. Nothing
# is wired unless you opt a unit in via `failureUnits`, or hand a consumer the
# exposed `powerNotifyCommand` (see my.ups-monitor). Enabling the module alone
# just makes the helpers available.
#
# The auth token is delivered as an environment variable (NTFY_TOKEN) via a
# systemd EnvironmentFile rendered from sops — NOT as a file the notifier reads
# itself. systemd loads the EnvironmentFile as root before any User= drop, so
# consumers that run under a service account (e.g. NUT's upsmon, which forks its
# NOTIFYCMD) still see the token without any secret-file permission juggling.
#
# Topics (create ACLs for the `homeserver` ntfy user accordingly):
#   - systemTopic (default alerts-system) — systemd unit failures, the
#     healthCheck (disk space, btrfs errors, SMART), bootNotice, and anything a
#     consumer sends through `notifyCommand` (e.g. the protonvpn watchdog)
#   - powerTopic  (default alerts-power)  — UPS/power events
# Backup failures also flow through here (my.backup delegates its alerting to
# this module; restic-backups-* is just another failureUnits entry).
#
let
  cfg = config.my.ntfy-alert;

  # Host part of baseUrl, for curl's --resolve pin.
  baseHost = lib.head (lib.splitString "/" (lib.removePrefix "https://" cfg.baseUrl));

  # Low-level sender. Reads NTFY_TOKEN from the environment (see module header).
  #   ntfy-notify <topic> <title> <priority> <tags> <message>
  ntfyNotify = pkgs.writeShellApplication {
    name = "ntfy-notify";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      topic="''${1:?topic required}"; title="''${2:-Alert}"
      priority="''${3:-default}"; tags="''${4:-}"; message="''${5:-}"
      auth=()
      if [ -n "''${NTFY_TOKEN:-}" ]; then
        auth=(-H "Authorization: Bearer $NTFY_TOKEN")
      fi
      # Best-effort and time-bounded: an alert must never hang a shutdown path
      # or wedge the triggering context.
      curl -fsS --max-time 20 "''${auth[@]}" \
        ${lib.optionalString (cfg.resolveTo != null)
          "--resolve ${baseHost}:443:${cfg.resolveTo}"} \
        -H "Title: $title" \
        -H "Priority: $priority" \
        ''${tags:+-H "Tags: $tags"} \
        -d "$message" \
        "${cfg.baseUrl}/$topic"
    '';
  };

  # OnFailure handler body. Invoked as: failure-notify <failed-unit-name>
  failureNotify = pkgs.writeShellApplication {
    name = "ntfy-failure-notify";
    runtimeInputs = [ ntfyNotify pkgs.coreutils pkgs.nettools ];
    text = ''
      unit="''${1:-unknown unit}"
      host="$(hostname)"
      ntfy-notify "${cfg.systemTopic}" \
        "❌ $unit failed on $host" \
        high "rotating_light,x" \
        "Unit $unit entered failed state at $(date -Is). Inspect with: journalctl -u $unit -n 50" \
        || true
    '';
  };

  # Periodic host health check. Every check alerts on TRANSITIONS only: a
  # problem is reported once when it appears and once when it clears, tracked
  # by a marker per check under the state directory. The marker is written only
  # after the alert was actually delivered, so an undelivered alert is retried
  # on the next run instead of being silently marked as sent.
  healthCheck = pkgs.writeShellApplication {
    name = "ntfy-health-check";
    runtimeInputs = [ ntfyNotify pkgs.coreutils pkgs.nettools
      pkgs.smartmontools pkgs.btrfs-progs pkgs.util-linux ];
    text = ''
      state=/var/lib/ntfy-alert
      host=$(hostname)

      # transition <key> <bad:0|1> <problem title> <problem message> <ok message>
      transition() {
        local marker="$state/$1.bad"
        if [ "$2" = 1 ] && [ ! -e "$marker" ]; then
          ntfy-notify "${cfg.systemTopic}" "⚠️ $3 on $host" high "warning" "$4" \
            && touch "$marker"
        elif [ "$2" = 0 ] && [ -e "$marker" ]; then
          ntfy-notify "${cfg.systemTopic}" "✅ Resolved: $3 on $host" default \
            "white_check_mark" "$5" && rm -f "$marker"
        fi
        return 0
      }

      # Disk space.
      for path in ${lib.escapeShellArgs cfg.healthCheck.diskPaths}; do
        # A path that is not mounted right now (e.g. a nofail disk that
        # did not come up) would report the filesystem underneath instead.
        mountpoint -q "$path" || continue
        pct=$(df --output=pcent "$path" | tail -1 | tr -dc '0-9')
        bad=0; [ "$pct" -ge ${toString cfg.healthCheck.diskThreshold} ] && bad=1
        key="disk-''${path//\//_}"
        transition "$key" "$bad" "$path nearly full" \
          "$path is at $pct% (threshold ${toString cfg.healthCheck.diskThreshold}%)." \
          "$path is back to $pct%."

        # btrfs per-device error counters (read/write/flush/corruption/
        # generation). They are cumulative, so this stays raised until the
        # counters are reset with `btrfs device stats -z <path>`.
        if [ "$(stat -f -c %T "$path")" = btrfs ]; then
          bad=0; btrfs device stats --check "$path" >/dev/null 2>&1 || bad=1
          transition "btrfs-''${path//\//_}" "$bad" "btrfs device errors on $path" \
            "Non-zero error counters: btrfs device stats $path" \
            "Error counters on $path are clean again."
        fi
      done

      ${lib.optionalString cfg.healthCheck.smart ''
        # SMART overall health. smartctl's exit status is a bitmask: bit 3
        # (8) = the drive's self-assessment says FAILING, bit 4 (16) = a
        # pre-failure attribute is at or below its threshold.
        smartctl --scan | while read -r dev _ type _; do
          rc=0; smartctl -H -d "$type" "$dev" >/dev/null 2>&1 || rc=$?
          bad=0; [ $(( rc & 24 )) -ne 0 ] && bad=1
          transition "smart-''${dev##*/}" "$bad" "SMART failure on $dev" \
            "smartctl -H reports $dev failing (exit $rc). Check: smartctl -a -d $type $dev" \
            "$dev passes its SMART health check again."
        done
      ''}
    '';
  };

  # One-shot notice at boot: an unannounced reboot is a crash or a power loss.
  bootNotice = pkgs.writeShellApplication {
    name = "ntfy-boot-notice";
    runtimeInputs = [ ntfyNotify pkgs.coreutils pkgs.nettools pkgs.systemd pkgs.procps ];
    text = ''
      last=$(journalctl -b -1 -n 1 -o short-iso --no-pager -q 2>/dev/null \
        | cut -d' ' -f1)
      ntfy-notify "${cfg.systemTopic}" "🔄 $(hostname) booted" default "arrows_counterclockwise" \
        "Up since $(uptime -s). Previous boot's last log entry: ''${last:-unknown}." \
        || true
    '';
  };

  # Ready-made NUT NOTIFYCMD. upsmon calls it with the message as $1 and the
  # event class in $NOTIFYTYPE. After alerting we chain the stock upssched so
  # any timer-driven NUT behaviour is preserved untouched.
  powerNotify = pkgs.writeShellApplication {
    name = "ntfy-power-notify";
    runtimeInputs = [ ntfyNotify pkgs.coreutils pkgs.nettools ];
    text = ''
      type="''${NOTIFYTYPE:-UNKNOWN}"
      msg="''${1:-UPS event}"
      case "$type" in
        ONBATT|LOWBATT|FSD|SHUTDOWN|COMMBAD|NOCOMM|REPLBATT|NOPARENT)
          prio=urgent; tags="rotating_light,battery" ;;
        ONLINE|COMMOK)
          prio=default; tags="white_check_mark,electric_plug" ;;
        *)
          prio=high; tags="battery" ;;
      esac
      ntfy-notify "${cfg.powerTopic}" "UPS: $type on $(hostname)" "$prio" "$tags" \
        "$msg ($(date -Is))" || true
      # Preserve stock NUT notification handling (dormant by default, but chain
      # it so nothing that later relies on upssched silently breaks).
      exec ${pkgs.nut}/bin/upssched "$@"
    '';
  };
in
{
  options.my.ntfy-alert = {
    enable = lib.mkEnableOption "ntfy alerting helpers (opt-in per unit; forces nothing)";

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.acpuchades.com";
      description = "Base URL of the ntfy server (topic is appended).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        systemd EnvironmentFile providing NTFY_TOKEN=<token> (a sops template).
        Used by the failure notifier; pass the same file to consumers like
        my.ups-monitor.notify.environmentFile.
      '';
    };

    systemTopic = lib.mkOption {
      type = lib.types.str;
      default = "alerts-system";
      description = "ntfy topic for systemd unit-failure alerts.";
    };

    powerTopic = lib.mkOption {
      type = lib.types.str;
      default = "alerts-power";
      description = "ntfy topic for UPS/power alerts (used by powerNotifyCommand).";
    };

    failureUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "postgresql" "caddy" "vaultwarden" ];
      description = ''
        Bare systemd service names (no .service) to alert on when they enter a
        failed state. This is the ONLY thing that opts a unit into alerting —
        nothing is wired implicitly.
      '';
    };

    resolveTo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "127.0.0.1";
      description = ''
        Connect to this address instead of resolving baseUrl's host (curl
        --resolve, port 443). For a server that hosts ntfy itself: alerts then
        go out even when DNS is what broke.
      '';
    };

    healthCheck = {
      enable = lib.mkEnableOption "hourly disk-space / btrfs / SMART alerts";
      diskPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/" ];
        description = "Mountpoints checked for free space (and btrfs error counters).";
      };
      diskThreshold = lib.mkOption {
        type = lib.types.ints.between 1 100;
        default = 90;
        description = "Usage percentage at or above which a mountpoint alerts.";
      };
      smart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Also alert when a drive fails its SMART health check.";
      };
    };

    bootNotice.enable = lib.mkEnableOption "an alert on every boot (crash / power-loss detector)";

    # Exposed for other modules to consume.
    notifyCommand = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = ''
        Path to the low-level sender: `<cmd> <topic> <title> <priority> <tags>
        <message>`. Needs NTFY_TOKEN in its environment (environmentFile).
      '';
    };

    powerNotifyCommand = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "Path to a NUT NOTIFYCMD-compatible script that alerts to powerTopic.";
    };
  };

  config = lib.mkMerge [
    # Always expose the consumable script path (cheap; harmless when unused).
    {
      my.ntfy-alert.powerNotifyCommand = lib.getExe powerNotify;
      my.ntfy-alert.notifyCommand = lib.getExe ntfyNotify;
    }

    (lib.mkIf (cfg.enable && cfg.healthCheck.enable) {
      systemd.services.ntfy-health-check = {
        description = "Disk space / btrfs / SMART check with ntfy alerts";
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = cfg.environmentFile;
          StateDirectory = "ntfy-alert";
          ExecStart = lib.getExe healthCheck;
        };
      };
      systemd.timers.ntfy-health-check = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "1h";
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.bootNotice.enable) {
      systemd.services.ntfy-boot-notice = {
        description = "ntfy alert that the host booted";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "caddy.service" "ntfy-sh.service" ];
        # Boot-only: a rebuild must not re-announce a boot.
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = cfg.environmentFile;
          ExecStart = lib.getExe bootNotice;
        };
      };
    })

    (lib.mkIf cfg.enable {
      systemd.services = lib.mkMerge [
        # Templated OnFailure target: notify-failure@<unit>.service, instantiated
        # per failing unit via `OnFailure=notify-failure@%n.service`.
        {
          "notify-failure@" = {
            description = "ntfy alert that %i entered a failed state";
            serviceConfig = {
              Type = "oneshot";
              EnvironmentFile = cfg.environmentFile;
              ExecStart = "${lib.getExe failureNotify} %i";
            };
          };
        }
        # Opt each requested unit in. Merges into the units' existing definitions.
        (lib.genAttrs cfg.failureUnits (_: {
          onFailure = [ "notify-failure@%n.service" ];
        }))
      ];
    })
  ];
}
