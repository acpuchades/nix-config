# Backups

Off-site, client-side-encrypted backups of `homeserver`, using
[restic](https://restic.net) against a Backblaze B2 bucket.

- Module: `modules/backup/default.nix` (`my.backup`), a wrapper over the
  upstream `services.restic.backups.<name>` module.
- Configured in: `machines/homeserver/default.nix`, the `my.backup` block.
- Repository: `b2:acpuchades-homeserver-restic:restic`
- Runs as: `restic-backups-homeserver.service`, driven by a daily timer.

For rebuilding the whole machine — of which restoring data is only step five —
see [MIGRATION.md](MIGRATION.md).

---

## 1. What happens each night

The timer is `daily` with a 30-minute jitter and `Persistent = true`, so a run
missed while the box was off happens at the next boot. One run is four phases:

1. **Prepare** (`backupPrepareCommand`). Puts NextCloud into maintenance mode,
   then writes database dumps into `/var/backup/dumps`.
2. **Backup.** restic snapshots the configured paths *plus* that staging
   directory, encrypting everything locally before upload.
3. **Prune.** `restic forget --prune` applies the retention policy.
4. **Cleanup** (`backupCleanupCommand`, wired as `ExecStopPost`). Takes
   NextCloud out of maintenance mode and wipes `/var/backup/dumps`. Because it
   is `ExecStopPost` it runs even when the backup *fails* — maintenance mode is
   never left stuck on, and plaintext dumps never linger on disk.

Failures push to ntfy: the unit is listed in `my.ntfy-alert.failureUnits`, so a
failed run posts to the `alerts-system` topic (§8 covers verifying that path
actually works).

## 2. What is in a snapshot

| Path | Why |
|---|---|
| `/home` | all user homes, including eva's Maildir (caches excluded) |
| `/var/lib/openclaw/eva` | the agent's state and memory |
| `/var/lib/hass` | Home Assistant configuration |
| `/srv/prefect` | Prefect data directory |
| `/etc/ssh` | host keys — **the sops age identity** (see §4) |
| `/var/lib/nixos` | NixOS' uid/gid allocation map |
| `/var/lib/acme` | ACME account key and issued certificates |
| `/var/lib/tor` | the bridge's long-term identity keys |
| `/var/lib/jellyfin` | accounts and playstate |
| `/var/lib/transmission` | torrent and resume state |
| `/srv/encrypted/nextcloud` | NextCloud data *and* its config (`instanceid`, secrets) |
| `/srv/encrypted/vaultwarden` | Vaultwarden data directory |
| `/srv/encrypted/immich` | Immich originals |
| `/srv/shared` | the Samba share, minus the big trees below |
| `/var/backup/dumps` | the database dumps produced in phase 1 |

Deliberately absent, because all of it is re-acquirable and none of it should
be paying for off-site storage: Bitcoin's chainstate, the Nominatim database and
its import data, `/srv/shared/{Media,Downloads}`, **`/srv/shared/NGS`** (bulk
source data — keep your own copy, it is in no snapshot), Jellyfin's scraped
metadata, Prometheus/netdata history, Ollama models, per-home caches (`.cache`,
`.cargo`, `.npm`, uv, Claude shell snapshots), Home Assistant logs, and
`/home/alex/nix-config` (version-controlled and pushed). The full list, with
how each item comes back, is [MIGRATION.md](MIGRATION.md) §6.

Two notes on that boundary. Immich's derivatives (`thumbs/`,
`encoded-video/`) live *inside* `/srv/encrypted/immich` and are explicitly
excluded — Immich regenerates both from the originals; `profile/` (avatars,
not regenerable) stays in. Jellyfin transcodes need no exclude: they live
under `/var/cache/jellyfin`, which is not a backup path at all.

Two things are re-derived rather than restored: Samba's passdb is provisioned
from sops at boot by `samba-provision-users`, and the GitHub Actions runner
re-registers itself from its token. AdGuard is fully declarative
(`mutableSettings = false`), so there is no state to keep.

## 3. Databases are dumped, not copied

Copying a live PostgreSQL data directory produces a torn image — pages
half-written, WAL mid-flight — that can restore to a corrupt cluster. So
`/srv/encrypted/postgresql` is **not** in the path list. Instead, each run:

- writes `pg_dumpall --globals-only` to `/var/backup/dumps/postgres/globals.sql`
  (roles, grants and tablespaces are cluster-wide and appear in no per-database
  dump);
- writes one `pg_dump --format=custom` per live database to
  `/var/backup/dumps/postgres/<db>.dump`. The database list is enumerated at
  runtime, so a new database is picked up with no config change. `nominatim` is
  excluded (large and re-importable from Geofabrik), as are the template DBs
  and the `postgres` maintenance DB — so do not expect a `postgres.dump`;
- snapshots each SQLite database with `sqlite3 .backup`, which is consistent
  even under concurrent writes: `grafana.sqlite` (dashboards, users) and
  `ntfy.sqlite` (the ntfy user/ACL database, which is imperative and exists
  nowhere else);
- quiesces NextCloud with `occ maintenance:mode --on` for the duration, so the
  copied `data/` tree and the dumped database agree with each other.

## 4. Encryption, and the one thing it cannot do

restic encrypts everything client-side before a byte leaves the host; B2 never
sees the repository password, which is why it is safe for the snapshot to
contain private host keys and Vaultwarden's data directory.

Four sops secrets make it work, in `machines/homeserver/secrets/default.yml`:
`backup/restic-password`, `backup/b2-account-id`, `backup/b2-account-key`, and
`ntfy/token` for the failure alert.

**The circularity that matters.** The repository password is a sops secret, and
sops decrypts with `/etc/ssh/ssh_host_ed25519_key` — which is itself inside the
repository. The backup therefore cannot bootstrap its own decryption. Losing
the machine without an off-box copy of the repository password means every
snapshot is unrecoverable, whatever else survives. So keep, somewhere that is
not this machine and not Vaultwarden (which is hosted on it):

- `backup/restic-password`,
- the B2 application key,
- the master age key from `.sops.yaml`,
- ideally `/etc/ssh/ssh_host_ed25519_key` itself.

## 5. Retention

`--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, applied by a prune after
every run.

Two consequences worth knowing. A file removed from the path list or added to
the excludes stays in the repository until every snapshot referencing it has
aged out — up to six months. To drop something *now*:

```sh
sudo restic-homeserver rewrite --exclude /path/to/thing --dry-run
sudo restic-homeserver rewrite --exclude /path/to/thing --forget
sudo restic-homeserver prune
```

And prune repacks partially-used pack files, which means downloading them from
B2; `prune --max-repack-size 5G` bounds that traffic.

---

## 6. Operating it

`restic-homeserver` is a generated wrapper on `PATH` that sets
`RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE`, the B2 credentials and the cache
directory. It needs root, because those secrets are root-only.

```sh
sudo restic-homeserver snapshots                # what exists
sudo restic-homeserver stats latest             # size of the latest snapshot
sudo restic-homeserver ls latest /etc/ssh       # browse a snapshot's tree
sudo restic-homeserver diff <snap1> <snap2>     # what changed between two

systemctl status restic-backups-homeserver      # last run's outcome
journalctl -u restic-backups-homeserver -n 100  # its log
systemctl list-timers restic-backups-homeserver # when the next one is due

sudo systemctl start restic-backups-homeserver.service   # run one now
```

Integrity checks — worth running occasionally, and after anything unusual:

```sh
sudo restic-homeserver check                          # structure only, cheap
sudo restic-homeserver check --read-data-subset=5%    # actually re-reads data
```

Changing what is backed up means editing the `my.backup` block in
`machines/homeserver/default.nix` and rebuilding; nothing here is configured
imperatively.

---

## 7. Restoring

> Restoring onto a *new* machine has prerequisites — the host key, the netrc,
> the hardware-bound values — that must be handled first. Work through
> [MIGRATION.md](MIGRATION.md) rather than starting here.

### Finding what you want

```sh
sudo restic-homeserver snapshots
sudo restic-homeserver find '**/Nextcloud/Documents/tax*'   # which snapshots hold it
```

Or browse the repository as a filesystem, which is usually the fastest way to
answer "what did this look like on the 3rd" — it downloads only what you read:

```sh
sudo mkdir -p /mnt/restic && sudo restic-homeserver mount /mnt/restic
# /mnt/restic/snapshots/latest/... ; Ctrl-C to unmount
```

### A single file or directory

Restore beside the original, never over it, and copy into place yourself:

```sh
sudo restic-homeserver restore latest \
  --target /restore --include /home/alex/Documents/thing.org
```

### PostgreSQL

The data directory is not in the backup — the dumps under
`/var/backup/dumps/postgres/` are. Restore the globals first (only needed if
roles are missing, e.g. a fresh cluster), then the database:

```sh
sudo restic-homeserver restore latest --target /restore --include /var/backup/dumps
sudo -u postgres psql -f /restore/var/backup/dumps/postgres/globals.sql
sudo -u postgres pg_restore --clean --create -d postgres \
  /restore/var/backup/dumps/postgres/<db>.dump
```

Stop the service that owns the database first (`systemctl stop immich-server`,
`prefect-server`, `phpfpm-nextcloud`, …) — `--clean` drops objects out from
under a running client.

### SQLite (Grafana, ntfy)

```sh
sudo systemctl stop grafana
sudo restic-homeserver restore latest --target /restore \
  --include /var/backup/dumps/grafana.sqlite
sudo install -o grafana -g grafana -m600 \
  /restore/var/backup/dumps/grafana.sqlite /var/lib/grafana/grafana.db
sudo systemctl start grafana
```

The same shape restores `ntfy.sqlite` over `/var/lib/ntfy-sh/user.db` (owner
`ntfy-sh`). That database holds the ntfy users and ACLs, including the token
the backup alert itself publishes with.

### NextCloud

Files and database must be restored from the *same* snapshot — the
maintenance-mode quiesce is what makes them agree:

```sh
sudo nextcloud-occ maintenance:mode --on
sudo restic-homeserver restore <snap> --target /restore \
  --include /srv/encrypted/nextcloud --include /var/backup/dumps/postgres/nextcloud.dump
# move the data tree into place, restore the dump as above, then:
sudo nextcloud-occ maintenance:mode --off
sudo nextcloud-occ files:scan --all
```

`config/config.php` is inside the restored tree, so `instanceid`, `passwordsalt`
and `secret` come back with it. Restoring the data directory *without* them
makes existing encrypted content unreadable.

### Vaultwarden, Immich, Home Assistant, eva

Plain directory restores: stop the unit, restore the path over its data
directory, fix ownership, start it. Immich additionally needs its database
restored from the same snapshot, and will regenerate thumbnails on its own.

### After any restore

- Check ownership. `/var/lib/nixos` is in the backup so uid/gid allocations
  match, but restore it *before* the services that depend on those numbers
  start for the first time.
- Confirm the services are actually serving, not merely `active`.
- Run one backup by hand and let it finish, rather than discovering at 00:12
  that the restored state broke the next run.

---

## 8. Troubleshooting

**`repository is already locked`.** A run is in progress, or one died holding a
lock. Confirm nothing is running (`systemctl status restic-backups-homeserver`),
then `sudo restic-homeserver unlock`.

**NextCloud stuck in maintenance mode.** Cleanup runs as `ExecStopPost`, so this
should not happen — but `sudo nextcloud-occ maintenance:mode --off` is the fix,
and the journal for that run is where the reason will be.

**B2 authentication failures.** The credentials come from the sops template
`backup/b2-env`; a failure here usually means the application key was rotated in
B2 without updating `machines/homeserver/secrets/default.yml`.

**A run takes much longer than usual.** Check what grew — `restic-homeserver
diff` between the last two snapshots is the quickest answer. Bulk data landing
somewhere under a backed-up path is the usual cause, and the usual fix is an
exclude plus a `rewrite` (§5).

**Nothing has alerted in months.** That is the intended steady state, but verify
it rather than trusting it: stop the service mid-run, or temporarily point the
unit at a failing command, and confirm the ntfy push arrives.
