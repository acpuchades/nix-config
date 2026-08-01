---
name: nixos-homelab
description: How to operate a NixOS homelab — applying configuration changes, inspecting service state and logs, diagnosing failures, understanding the module system, and knowing when to escalate. Consult it whenever the owner asks about the homeserver, a failing service, a rebuild, or a NixOS configuration change.
---

# NixOS homelab

Check TOOLS.md for the owner's specific server details (hostname, SSH access,
services deployed, notable configuration paths). This skill covers the general
operational framework.

## Configuration management

NixOS is declared in a git repository. The workflow is always:
1. Edit `.nix` files in the repo
2. Commit (or at least stage) the change
3. Run `nixos-rebuild` on the target host to activate

**Always `git pull` before editing** — the owner may have made changes directly
on the server or from another machine.

### Applying changes

```bash
# On the target host (or via ssh):
sudo nixos-rebuild switch        # activate immediately
sudo nixos-rebuild test          # activate but don't set as boot default
sudo nixos-rebuild boot          # set as boot default, activate on next reboot
sudo nixos-rebuild dry-activate  # show what would change, don't apply
```

If the host is remote, build locally and push:
```bash
nixos-rebuild switch --target-host user@host --use-remote-sudo
```

On failure, `nixos-rebuild` prints the failing unit and its log snippet. Read
it before anything else — it usually contains the root cause.

### Rolling back

```bash
sudo nixos-rebuild switch --rollback   # revert to previous generation
sudo nix-env --list-generations -p /nix/var/nix/profiles/system
sudo nix-env --switch-generation N -p /nix/var/nix/profiles/system
```

## Service management

NixOS services are systemd units. Standard commands:

```bash
systemctl status <unit>          # current state + recent log tail
systemctl restart <unit>
systemctl stop / start <unit>
journalctl -u <unit> -n 100      # last 100 lines
journalctl -u <unit> -f          # follow live
journalctl -u <unit> --since "1 hour ago"
systemctl cat <unit>             # show the generated unit file (no sudo needed)
```

`systemctl cat` is useful when you cannot read journal logs due to permission
constraints — it shows the full unit definition including `Environment=` lines,
`ExecStart`, and `serviceConfig`, which often reveals misconfiguration.

To list all failed units:
```bash
systemctl --failed
```

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
2. `journalctl -u <unit> -n 50` — what was the last error?
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
- Caddy logs: `journalctl -u caddy`
- Test config: `sudo caddy validate --config /etc/caddy/caddy.json`
- If a site returns 502, the upstream service is likely down — check it first

## Monitoring and health

If Prometheus + Grafana are deployed:
- Check dashboards before digging into logs for broad issues (CPU, RAM, disk)
- `node_systemd_unit_state{state="failed"}` shows failed units
- `node_filesystem_avail_bytes` for disk space
- Details in TOOLS.md if the owner has a Grafana instance

## Nix store maintenance

```bash
nix-collect-garbage -d          # remove all unreferenced store paths
nix-collect-garbage --delete-older-than 30d  # keep last 30 days of generations
sudo nix-store --verify --check-contents     # verify store integrity (slow)
df -h /nix/store               # check store size
```

Run garbage collection before complaining about disk space.

## What to check in TOOLS.md

- SSH access to the server (hostname, user, key)
- Which services are deployed and their unit names
- Notable config paths in the nix-config repo
- Any services with unusual setups or known quirks
