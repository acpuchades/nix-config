# Migrating `homeserver` to new hardware

The NixOS side of this box is fully declarative: a `git clone` of this repo plus
`nixos-rebuild switch --flake .#homeserver` reproduces every service. Nothing
below is about the services — it is about the five things that live *outside*
the repo and that a rebuild alone will not bring back.

Read the whole file before starting. The ordering matters in two places, and
both of them are the difference between a rebuild that works and one that fails
in activation with no services running.

---

## 0. Before anything: three secrets that must already be off this machine

`sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` — the host's SSH
key **is** the age identity that decrypts every secret in
`machines/homeserver/secrets/`. A new machine generates a new host key, so
without one of the two recovery paths below, the first `nixos-rebuild switch`
fails in sops-nix activation and *nothing* comes up.

That key is now in the backup set, but the backup cannot bootstrap itself: the
restic repository password is `backup/restic-password`, a sops secret decrypted
by that same key. So these three must be held somewhere that is not this
machine — and not only in Vaultwarden, which is hosted *on* this machine:

| What | Where it lives now | Why |
|---|---|---|
| `/etc/ssh/ssh_host_ed25519_key` | this host, and the restic repo | the sops age identity |
| the master age private key (`age1a868f…`, see `.sops.yaml`) | wherever you put it | re-keys every secret file without the host key |
| `backup/restic-password` + the B2 application key | `machines/homeserver/secrets/default.yml` | opens the repo that holds the other two |

A paper copy or a hardware key is fine. **Verify the master key actually
decrypts, from the MacBook, before you need it** — an untested recovery path is
not one:

```sh
SOPS_AGE_KEY_FILE=<master key> sops -d machines/homeserver/secrets/default.yml | head
```

Also check the GitHub PAT in `github/token` has not expired: the `fugazi-web`
and `fugazi-web-testing` flake inputs are a *private* repo tracked by branch
head, so they are refetched on every evaluation. An expired PAT means the whole
homeserver configuration will not evaluate — not just those two services.

---

## 1. Decide which migration you are doing

**A — the disks come with you.** Much the easier path. `/srv` and
`/srv/encrypted` carry their filesystem UUIDs, so `hardware-configuration.nix`
mostly still applies, and there is no 2 TiB restore. What still changes: the
root/boot/swap UUIDs if you reinstall the OS disk, the LUKS TPM binding, and the
NIC name.

**B — new disks, restore from backup.** Everything in section 5. Budget for the
download: the repo is a few hundred GB after `/srv/shared/NGS` was excluded, but
`/srv/encrypted/immich` and `/home/alex` are still substantial over a domestic
line. Start the restore the day *before* you need the box.

---

## 2. Hardware-bound values to update

| Value | Where | Note |
|---|---|---|
| root / boot / swap / `/srv` / `/srv/encrypted` UUIDs | `machines/homeserver/hardware-configuration.nix` | regenerate with `nixos-generate-config --show-hardware-config`, then re-apply the `options` we set by hand (`noatime`, `compress=zstd`, `nofail`) — the generator will not produce them |
| LUKS container UUID | `machines/homeserver/default.nix`, `environment.etc."crypttab"` | unchanged if the disk moves; new if you re-create the container |
| `uplinkInterface` | `machines/homeserver/default.nix` (one `let` binding) | NIC names follow the PCI path, so new hardware renames it. Changing this one string covers the static address, the WiFi association and the WireGuard NAT. If the new box has ethernet, the `networking.wireless` block in `networking.nix` goes away and the networkd `10-*` network attaches to the wired NIC instead |
| CPU / platform bits | `hardware-configuration.nix` | `kvm-amd` and `hardware.cpu.amd.updateMicrocode` are AMD-specific; swap for the Intel equivalents on Intel |
| `system.stateVersion = "25.05"` | `machines/homeserver/default.nix` | **do not bump.** It describes the state you are restoring, not the release you are installing |
| hostname `homeserver` | `networking.nix` | keep it — it is the flake output name, and AdGuard rewrites and vhosts assume it |

The static LAN address `192.168.2.2` should stay too: it is hardcoded in AdGuard
rewrites, the `*.acpuchades.com` vhosts, `homeServerLocalAddress`, and the
router's port forwards. Keep it outside the router's DHCP pool, and update any
MAC-based DHCP reservation to the new NIC.

---

## 3. LUKS and the TPM

`/srv/encrypted` is unlocked from `/etc/crypttab` with `tpm2-device=auto`. The
TPM seals the key to *that* motherboard's state, so on new hardware the unlock
simply fails — as it can after a firmware update on the current one.

Before the move, confirm a passphrase keyslot exists and that you have its
passphrase stored with the secrets in section 0:

```sh
sudo cryptsetup luksDump /dev/disk/by-uuid/c5e7c042-5625-493f-9b8a-487ecdac277a
```

After the move, unlock by passphrase once, then re-enroll against the new TPM:

```sh
sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-uuid/<container>
```

---

## 4. Bootstrap order for the first switch

This is the ordering that matters. Steps 2 and 3 both have to happen *before*
the first `nixos-rebuild`, and each fails in a way that looks like something
else.

1. **Install NixOS** on the new box — minimal installer, same hostname, EFI
   (`systemd-boot`, `canTouchEfiVariables`).

2. **Restore the SSH host key**, before anything else touches sops:

   ```sh
   sudo install -m600 ssh_host_ed25519_key     /etc/ssh/
   sudo install -m644 ssh_host_ed25519_key.pub /etc/ssh/
   ```

   *Or*, if you would rather the new machine have its own identity: add its
   `ssh-to-age` output to `.sops.yaml` under `&homeserver`, run
   `sops updatekeys machines/homeserver/secrets/default.yml` (and
   `users/alex/secrets/homeserver.yml`) with the master key, and commit.

3. **Seed the netrc by hand.** `nix.settings.netrc-file` points at a sops
   template that only exists *after* a successful switch, but the private
   `fugazi-web` inputs are fetched *during* evaluation — so without this the
   first rebuild 404s on an input and never gets far enough to create the file
   it needed:

   ```sh
   printf 'machine github.com\n  login x-access-token\n  password ghp_…\n' \
     | sudo tee /etc/nix/netrc >/dev/null && sudo chmod 0400 /etc/nix/netrc
   ```

4. **Clone and switch:**

   ```sh
   git clone https://github.com/acpuchades/nix-config.git && cd nix-config
   # update hardware-configuration.nix + uplinkInterface first (section 2)
   sudo nixos-rebuild switch --flake .#homeserver
   ```

   Expect the first build to be long: Nominatim, Immich and the Caddy plugin FOD
   are all built or fetched here.

---

## 5. Restoring data

How the backup itself works — what is in a snapshot, why the databases are
dumped rather than copied, and per-service restore recipes — is in
[BACKUP.md](BACKUP.md). What follows is only the migration path.

With `RESTIC_PASSWORD`, `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` in the environment:

```sh
export RESTIC_REPOSITORY=b2:acpuchades-homeserver-restic:restic
restic snapshots
restic restore latest --target /            # or --target /restore, then move
```

Restore selectively with `--include` if you only need part of it — `/home`,
`/srv/encrypted/nextcloud`, and so on.

**PostgreSQL is dumped, not copied.** The data directory is not in the backup;
`/var/backup/dumps` is. Restore the cluster globals first, then each database:

```sh
sudo -u postgres psql -f /restore/var/backup/dumps/postgres/globals.sql
sudo -u postgres pg_restore --clean --create -d postgres \
  /restore/var/backup/dumps/postgres/<db>.dump
```

SQLite services (grafana, ntfy) restore by copying `<name>.sqlite` from the same
staging tree over the live file with the service stopped.

Stop the services that own the data before restoring into their directories, and
check ownership afterwards — `/var/lib/nixos` is in the backup precisely so the
uid/gid allocations match, but restore it *before* the services start.

---

## 6. What is deliberately not backed up

None of this is lost — all of it is re-acquirable, which is why it is not paying
for off-site storage. Recreating it is post-migration work, not a blocker.

| Not backed up | How it comes back |
|---|---|
| `/srv/bitcoind` | re-syncs from the network (days, unattended) |
| Nominatim DB + `/home/alex/nominatim` | re-import from the Geofabrik extract |
| `/srv/shared/{Media,Downloads}` | re-acquirable, or already copied at the source |
| `/srv/shared/NGS` (1.2 T) | **keep your own copy** — this is bulk source data and it is not in any snapshot |
| `/var/lib/immich` thumbnails | Immich regenerates them from the originals in `/srv/encrypted/immich` |
| Jellyfin metadata/transcodes | re-scraped; users and watch state *are* backed up |
| Prometheus / netdata history | metrics history, not state |
| Ollama models | re-downloaded on demand |
| `/var/lib/samba` | passdb is re-provisioned from sops at boot (`samba-provision-users`) |
| `/var/lib/github-runner` | the runner re-registers from `github-runner/acpuchades-site` |
| AdGuard config | declarative (`mutableSettings = false`) |

---

## 7. Out-of-band checklist after the move

Things no amount of Nix will do for you:

- **Router:** forward TCP 22 (if exposed), 25, 80, 443, 9001 + 9002 (Tor
  ORPort/obfs4), 51413, and UDP 51820 to `192.168.2.2`. Update the DHCP
  reservation to the new NIC's MAC.
- **Mail:** inbound port 25 must be unblocked by the ISP, and the rDNS/PTR for
  the public IP has to match. Outbound DKIM is Mailjet's, so nothing to move.
- **DNS:** ddclient refreshes the Cloudflare A records once it is up; confirm
  `/var/cache/ddclient` is being written and the records actually moved.
- **Vaultwarden / NextCloud / Immich:** log in and confirm before you wipe the
  old box. NextCloud's `instanceid` and secrets live in
  `/srv/encrypted/nextcloud/config` and are restored with it.
- **eva (openclaw):** state under `/home/eva` and `/var/lib/openclaw/eva` is
  restored, but the Claude device authorization may need redoing — check
  `systemctl status openclaw-eva` and send her a message.
- **Backups:** run `systemctl start restic-backups-homeserver.service` manually
  and watch it complete, rather than finding out at 00:12 that it does not.

---

## 8. Not done yet

There is no `disko` configuration, so the disk layout — partitioning, the btrfs
filesystems, the LUKS container — is manual and lives only in this document.
Adding one would make provisioning reproducible; retrofitting it against live
disks needs care (`disko --mode mount` only, never `destroy`).
