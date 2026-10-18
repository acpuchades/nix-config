# One watchdog timer per tunnel. The probe, the rotation and the restart are
# deliberately three escalating steps rather than one: most failures are a
# single unresponsive Proton endpoint, and reaching for a unit restart first
# would take Transmission down with it (it is PartOf the P2P tunnel) for
# something a live `wg set` fixes without dropping a single transfer.

#
# Called from ./default.nix once per client tunnel and once for the P2P tunnel.
{
  lib,
  pkgs,
  cfg,
  wg,
  candidatesOf,
}:

{
  t,
  resetCmd,
  resetName,
  probePrefix,
  curlArgs,
  wgPrefix,
}:
let
  cands = candidatesOf t;
  failFile = "/run/protonvpn-${t.interface}.fails";
  # Present while an outage alert is out, so the alert fires once per
  # outage (not once a minute) and the recovery is announced exactly once.
  downFile = "/run/protonvpn-${t.interface}.down";
  # When each candidate last failed. In /var/lib, not /run: a server that
  # died yesterday is still the worst bet after a reboot.
  histFile = "/var/lib/protonvpn-watchdog/${t.interface}.history";
  notify = cfg.watchdog.notify;
in
{
  timer = {
    description = "Probe ${t.interface} and rotate its endpoint on failure";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Deliberately OnActiveSec, not OnBootSec. A monotonic timer whose
      # deadline is already in the past when it starts fires immediately,
      # and on a `nixos-rebuild switch`/`test` into a host that booted days
      # ago an OnBootSec deadline always is — so the first probe landed in
      # the same second the tunnel came up, long before any handshake could
      # complete, and the watchdog restarted it on the spot. OnActiveSec is
      # relative to the timer's own activation, so the grace window is real
      # both at boot and at switch.
      OnActiveSec = cfg.watchdog.interval * 2;
      OnUnitActiveSec = cfg.watchdog.interval;
      AccuracySec = "5s";
    };
  };

  service = {
    description = "ProtonVPN watchdog for ${t.interface}";
    serviceConfig = {
      Type = "oneshot";
      # Shared by every tunnel's watchdog; one history file per interface.
      StateDirectory = "protonvpn-watchdog";
      EnvironmentFile = lib.mkIf (notify.environmentFile != null) notify.environmentFile;
      ExecStart = pkgs.writeShellScript "protonvpn-watchdog-${t.interface}" ''
        set -u

        # Parallel arrays: candidate i is keys[i] reached at endpoints[i].
        keys=(${lib.concatMapStringsSep " " (c: "'${c.publicKey}'") cands})
        endpoints=(${lib.concatMapStringsSep " " (c: "'${c.endpoint}'") cands})
        labels=(${lib.concatMapStringsSep " " (c: lib.escapeShellArg c.label) cands})
        n=''${#endpoints[@]}

        # notify <priority> <tags> <title> <message> — best-effort; returns
        # whether the alert was delivered.
        notify() {
          ${
            if notify.command == null then
              "return 1"
            else
              ''
                ${notify.command} ${lib.escapeShellArg notify.topic} \
                  "$3" "$1" "$2" "$4 ($(${pkgs.coreutils}/bin/date -Is))"''
          }
        }

        # Index of the candidate the interface is on right now, or -1 for
        # none (a hand-set endpoint). Read from the LIVE peer, never
        # remembered: anything else that changes the peer (a reboot, a
        # hand-run `wg set`) would leave a remembered index stale.
        live_idx() {
          local live i
          live=$(${wgPrefix}${pkgs.wireguard-tools}/bin/wg show ${t.interface} endpoints 2>/dev/null)
          for i in "''${!keys[@]}"; do
            if [ "$live" = "''${keys[$i]}"$'\t'"''${endpoints[$i]}" ]; then
              echo "$i"; return
            fi
          done
          echo -1
        }

        label_of() {
          if [ "$1" -ge 0 ]; then echo "''${labels[$1]}"; else echo "an unconfigured endpoint"; fi
        }

        probe() {
          ${probePrefix}${pkgs.curl}/bin/curl -fsS -o /dev/null \
            ${curlArgs} --max-time ${toString cfg.watchdog.timeout} \
            ${cfg.watchdog.probeUrl}
        }

        # Point the interface at candidate $1. Same server: just move the
        # endpoint. Different server: swap the peer, removing whatever is
        # there in the SAME `wg set`, so the interface never sits with zero
        # peers or with two.
        set_peer() {
          local key=''${keys[$1]} args=() cur
          for cur in $(${wgPrefix}${pkgs.wireguard-tools}/bin/wg show ${t.interface} peers); do
            [ "$cur" != "$key" ] && args+=(peer "$cur" remove)
          done
          args+=(peer "$key" endpoint "''${endpoints[$1]}" allowed-ips 0.0.0.0/0 \
            persistent-keepalive ${toString t.peer.persistentKeepalive})
          ${wgPrefix}${pkgs.wireguard-tools}/bin/wg set ${t.interface} "''${args[@]}"
        }

        # Failure history: "<publicKey> <endpoint> <epoch>" per candidate
        # that has failed and not passed a probe since. Keyed by the pair,
        # never by index, so reordering or extending the config cannot pin
        # one server's history on another. Entries for candidates no longer
        # configured are dropped on the next save.
        declare -A lastfail=()
        if [ -r ${histFile} ]; then
          while read -r k e ts; do
            [ -n "''${ts:-}" ] && lastfail["$k $e"]=$ts
          done < ${histFile}
        fi

        save_history() {
          local i id tmp=${histFile}.tmp
          : > "$tmp"
          for i in "''${!keys[@]}"; do
            id="''${keys[$i]} ''${endpoints[$i]}"
            [ -n "''${lastfail[$id]:-}" ] && echo "$id ''${lastfail[$id]}" >> "$tmp"
          done
          ${pkgs.coreutils}/bin/mv -f "$tmp" ${histFile}
        }

        # mark <idx> ok|failed — no-op for -1 (a hand-set endpoint).
        mark() {
          [ "$1" -ge 0 ] || return 0
          local id="''${keys[$1]} ''${endpoints[$1]}"
          if [ "$2" = ok ]; then
            [ -n "''${lastfail[$id]:-}" ] || return 0
            unset 'lastfail[$id]'
          else
            lastfail[$id]=$(${pkgs.coreutils}/bin/date +%s)
          fi
          save_history || true
        }

        # Every candidate but $1, best bet first: never failed (or passed
        # since) before failed, and among the failed the one that failed
        # LONGEST ago first. Ties keep the configured order, so with no
        # history this is exactly the declared list. When everything has
        # failed this degrades to round-robin, which is what you want while
        # Proton itself, not one server, is the problem.
        failover_order() {
          local i
          for i in "''${!keys[@]}"; do
            [ "$i" = "$1" ] && continue
            echo "''${lastfail["''${keys[$i]} ''${endpoints[$i]}"]:-0} $i"
          done | ${pkgs.coreutils}/bin/sort -s -n -k1,1 -k2,2 \
               | ${pkgs.coreutils}/bin/cut -d' ' -f2
        }

        # Consecutive failures, carried across invocations: this unit is a
        # oneshot, so the count cannot live in memory.
        fails=0
        [ -r ${failFile} ] && fails=$(${pkgs.coreutils}/bin/cat ${failFile} 2>/dev/null || echo 0)

        if probe; then
          ${pkgs.coreutils}/bin/rm -f ${failFile}
          mark "$(live_idx)" ok
          if [ -e ${downFile} ]; then
            notify default white_check_mark "${t.interface} is back up" \
              "${t.interface} passes its probe again, on $(label_of "$(live_idx)")." \
              && ${pkgs.coreutils}/bin/rm -f ${downFile}
          fi
          exit 0
        fi

        fails=$((fails + 1))
        echo "$fails" > ${failFile}
        echo "watchdog: ${t.interface} failed its probe ($fails/${toString cfg.watchdog.failuresBeforeRestart})"

        # Rotation is NOT gated on the failure count. `wg set` swaps the
        # endpoint on a live interface, so a rotation that works costs
        # nothing — no interface teardown, no dropped sockets, no restart
        # cascade — and there is no reason to sit on a dead endpoint while a
        # counter fills.
        #
        # Try every other candidate in `failover_order` (all n when on a
        # hand-set endpoint), marking each one's outcome so the next
        # failover starts from whatever has been reliable lately.
        from=$(live_idx)
        mark "$from" failed
        order=$(failover_order "$from")

        if [ -n "$order" ]; then
          for idx in $order; do
            next=''${endpoints[$idx]}
            echo "watchdog: rotating ${t.interface} to $next"
            if ! set_peer "$idx"; then
              mark "$idx" failed
              continue
            fi

            # Give the new endpoint a handshake window before judging it.
            ${pkgs.coreutils}/bin/sleep 5
            if probe; then
              echo "watchdog: ${t.interface} recovered on $next"
              mark "$idx" ok
              ${pkgs.coreutils}/bin/rm -f ${failFile}
              if [ -e ${downFile} ]; then
                notify default white_check_mark "${t.interface} is back up" \
                  "${t.interface} recovered on $(label_of "$idx") ($next)." \
                  && ${pkgs.coreutils}/bin/rm -f ${downFile}
              else
                notify high twisted_rightwards_arrows "${t.interface} failed over" \
                  "$(label_of "$from") stopped answering; ${t.interface} now exits via $(label_of "$idx") ($next)." \
                  || true
              fi
              exit 0
            fi
            mark "$idx" failed
          done

          echo "watchdog: no endpoint answered for ${t.interface}"
        fi

        # The restart is the only destructive step here: it resets a
        # handshake that may simply not have completed yet, and for the P2P
        # tunnel it takes Transmission down with it. So it, alone, waits for
        # the failure count.
        if [ "$fails" -lt ${toString cfg.watchdog.failuresBeforeRestart} ]; then
          echo "watchdog: deferring reset of ${resetName}"
          exit 0
        fi

        echo "watchdog: resetting ${resetName} after $fails consecutive failures"
        ${pkgs.coreutils}/bin/rm -f ${failFile}
        # Gated like the reset, so one bad minute is not an outage alert.
        if [ ! -e ${downFile} ]; then
          notify urgent rotating_light "${t.interface} is DOWN" \
            "None of its $n configured endpoints answered for $fails consecutive probes. Resetting ${resetName} and retrying every ${toString cfg.watchdog.interval}s." \
            && ${pkgs.coreutils}/bin/touch ${downFile}
        fi
        # The reset alone does NOT restore the primary: `networkctl
        # reconfigure` re-applies only the .network (addresses, routes) and
        # leaves an existing WireGuard device's peers as they are. So the
        # primary goes back by hand first, making a reset a real return to
        # the configured state (for the P2P tunnel the restart rebuilds the
        # interface anyway, and this is a harmless no-op before it).
        set_peer 0 || true
        exec ${resetCmd}
      '';
    };
  };
}
