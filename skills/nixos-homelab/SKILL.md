---
name: nixos-homelab
description: How to operate a NixOS homelab — applying configuration changes, inspecting service state and logs, diagnosing failures, understanding the module system, and knowing when to escalate. Consult it whenever the owner asks about the homeserver, a failing service, a rebuild, or a NixOS configuration change.
---

# NixOS homelab

Check TOOLS.md for the owner's specific server details (hostname, SSH access,
services deployed, notable configuration paths). This skill covers the general
operational framework.

## Your role: diagnose, report, restart — the owner changes config

What you may actually run is set by the `policy` skill (the security
boundary) and the `toolkit` skill (the diagnostic wrappers you have). Read
those, not this skill, for what is permitted. In a typical setup:

- **Read-only inspection** (`systemctl status/cat/list-units`, `ps`, `ss`,
  `df`, …) needs no privileges — do it freely.
- **Restarting a failed service** is granted via `sudo` for a fixed set of
  units only, as `sudo systemctl restart <unit>.service`. Any other verb or
  unit is refused by sudo, even after approval.
- **Logs**: you may not be in the system journal group, so a plain
  `journalctl` shows only your own logs. Use the journal/health-check wrappers
  listed in the `toolkit` skill.
- **Configuration changes and rebuilds are the owner's operation, never
  yours.** You don't have the config repo or `nixos-rebuild`. When a fix needs
  a config change, diagnose it, then hand the owner a precise proposal: which
  option, which file if you know it, the suggested value and why.

## Configuration management (how the owner applies changes)

Background, so your proposals fit the workflow. NixOS is declared in a git
repository:
1. Edit `.nix` files in the repo
2. Commit the change
3. Run `nixos-rebuild` on the target host to activate

```bash
sudo nixos-rebuild switch        # activate immediately
sudo nixos-rebuild test          # activate but don't set as boot default
sudo nixos-rebuild boot          # set as boot default, activate on next reboot
sudo nixos-rebuild dry-activate  # show what would change, don't apply
sudo nixos-rebuild switch --rollback   # revert to previous generation
```

If the owner pastes a failed rebuild, read the failing unit and its log snippet
first — it usually contains the root cause.

## Service management

NixOS services are systemd units:

```bash
systemctl status <unit>          # current state + recent log tail
systemctl --failed               # every failed unit
systemctl cat <unit>             # the generated unit file (no sudo needed)
systemctl list-timers            # scheduled jobs and their last/next run
```

`systemctl cat` is useful when you cannot read journal logs due to permission
constraints — it shows the full unit definition including `Environment=` lines,
`ExecStart`, and `serviceConfig`, which often reveals misconfiguration.

Restart only when the failure looks transient (crash, dependency hiccup,
network blip). If it fails again right after a restart, stop and report
instead of retrying in a loop — a repeat failure is a config or data problem.

## NixOS module system — common patterns

### Priority conflicts (`lib.mkForce`)

When two modules set the same NixOS option, NixOS raises a conflict error —
unless one uses `lib.mkForce` to override the other. Use `lib.mkForce` when
your module must win over an upstream (nixpkgs) module's default.

For systemd environment variables specifically: if both modules produce an
`Environment=VAR=value` line in the same unit, **systemd uses the last one**.
This silently overrides earlier lines, which can cause hard-to-diagnose bugs
(e.g. a worker connecting to the wrong API URL). Use `lib.mkForce` at the NixOS
attribute level to prevent this.

### Debugging a broken service

1. `systemctl status <unit>` — is it active, failed, activating?
2. Its recent journal (via the journal wrapper) — what was the last error?
3. `systemctl cat <unit>` — what does the unit file actually contain?
   Check `Environment=` lines, `ExecStart`, `User`, `WorkingDirectory`.
4. If a path is missing: `ls -la <path>` — does it exist? Right permissions?
5. If it's an environment variable issue: compare what the unit sets vs. what
   the application expects.
6. If the service starts but immediately exits: check `Type=` (simple vs. exec
   vs. oneshot) and whether the process is actually staying alive.

### Common module patterns

```nix
# Conditional config
lib.mkIf cfg.enable { ... }

# Merge multiple service definitions
systemd.services = lib.mkMerge [ { serviceA = ...; } { serviceB = ...; } ];

# Map over an attrset to generate multiple units
systemd.services = lib.mapAttrs' (name: value:
  lib.nameValuePair "prefix-${name}" { ... }
) cfg.someAttrset;

# Force priority over upstream module
environment.SOME_VAR = lib.mkForce "my-value";
```

## Reverse proxy (Caddy)

If the homelab uses Caddy as a reverse proxy:
- Virtual host configs are typically in `services.caddy.virtualHosts.<domain>.extraConfig`
- Caddy logs: the `caddy` unit's journal (via the journal wrapper)
- Validating a Caddy config change is part of the owner's rebuild, not yours
- If a site returns 502, the upstream service is likely down — check it first

## Monitoring and health

Before querying anything by hand, check the `toolkit` skill's notes for
server-diagnostics wrappers the owner has granted you (e.g. a health-check
digest or a per-unit journal reader, run via `sudo` at an exact path). They
are the sanctioned route: they cover the routine health and security checks
without whole-journal access or raw network tools. If a plain `journalctl`
shows nothing, you likely lack journal access — use the wrapper, don't try to
widen your permissions.

If Prometheus + Grafana are deployed:
- Check dashboards before digging into logs for broad issues (CPU, RAM, disk)
- `node_systemd_unit_state{state="failed"}` shows failed units
- `node_filesystem_avail_bytes` for disk space
- Details in TOOLS.md if the owner has a Grafana instance

## Nix store maintenance

```bash
df -h /nix/store               # check store size
du -sh ~/.cache ~/workspace    # your own footprint
```

System-wide garbage collection (`sudo nix-collect-garbage -d`) and store
verification are the owner's operations — the host usually runs GC on a
timer anyway. If the store is filling the disk, report the numbers and
suggest GC rather than trying it yourself.

## What to check in TOOLS.md

- SSH access to the server (hostname, user, key)
- Which services are deployed and their unit names
- Notable config paths in the nix-config repo
- Any services with unusual setups or known quirks
