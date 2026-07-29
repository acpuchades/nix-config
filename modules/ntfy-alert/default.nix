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
#   - systemTopic (default alerts-system) — systemd unit failures
#   - powerTopic  (default alerts-power)  — UPS/power events
# These are distinct from backup's own `backups` topic/token: one publisher
# identity per concern, matching the existing ntfy convention.
#
let
  cfg = config.my.ntfy-alert;

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

    # Exposed for other modules to consume (e.g. my.ups-monitor.notify.command).
    powerNotifyCommand = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "Path to a NUT NOTIFYCMD-compatible script that alerts to powerTopic.";
    };
  };

  config = lib.mkMerge [
    # Always expose the consumable script path (cheap; harmless when unused).
    { my.ntfy-alert.powerNotifyCommand = lib.getExe powerNotify; }

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
