# Off-site backup: restic to Backblaze B2 (docs/BACKUP.md).
{ config, ... }:
{
  imports = [
    ../../modules/backup
  ];

  # Encrypted off-site backups to Backblaze B2 (restic, client-side AES-256).
  # Covers the irreplaceable, non-declarative state: DB dumps, all user homes
  # (keys, configs, shell histories, ~/.claude memory, eva's Maildir + agent
  # state) and the cloud-suite data dirs. Home coverage is a DENYLIST, not an
  # allowlist — backing up all of /home and excluding the re-acquirable caches
  # means new important dirs are caught automatically instead of silently
  # missed (the failure mode of a curated path list). Still EXCLUDES the big
  # reproducible sets — Bitcoin chainstate, Nominatim DB, Samba media/downloads,
  # and per-home caches/build artifacts — so the off-site copy stays small.
  # Repo password + B2 credentials come from sops (backup/* in ./sops.nix).
  my.backup = {
    enable = true;
    repository = "b2:acpuchades-homeserver-restic:restic";
    # Nightly plaintext DB dumps (Vaultwarden's TOTP seeds among them) go on
    # the LUKS volume, not the unencrypted root NVMe where deleted blocks
    # linger. The live databases are there too, so a dead /srv/encrypted
    # leaves nothing to dump anyway.
    stagingDir = "/srv/encrypted/backup-staging";
    passwordFile = config.sops.secrets."backup/restic-password".path;
    environmentFile = config.sops.templates."backup/b2-env".path;

    # Data-directory paths tracked off their owning modules' options so they
    # follow any relocation. /home covers both alex and eva (incl. Maildir).
    paths = [
      "/home" # all user homes (caches excluded below)
      "/var/lib/openclaw/eva" # eva agent state/memory
      "/var/lib/hass" # Home Assistant config
      "/srv/prefect" # Prefect data dir

      # --- machine identity, not user data --------------------------------
      # These are what turn "the config rebuilds" into "the machine comes
      # back". Small, and none of them is reproducible from this repo.
      #
      # /etc/ssh holds the host keys, and the ed25519 one IS the age identity
      # sops-nix decrypts every homeserver secret with (sops.age.sshKeyPaths).
      # Storing it here is safe — restic encrypts client-side with AES-256
      # before anything reaches B2, which only ever sees opaque blobs, and
      # the repo password never leaves the host. What it does NOT do is
      # bootstrap itself: the repo password is `backup/restic-password`, a
      # sops secret decrypted by this very key, so a copy of the restic
      # password (and the master age key) must live OFF this machine — and
      # not only in Vaultwarden, which is hosted here. With those two in hand
      # this entry is what makes a rebuild on new hardware a restore rather
      # than a re-key of every secret in the repo.
      "/etc/ssh" # host keys = the sops age identity
      # NixOS records its allocated uids/gids here. Restore the data without
      # it and every dynamically-allocated service user can come back on a
      # different number, leaving the restored trees owned by nobody.
      "/var/lib/nixos" # uid/gid allocation map
      # ACME account key + issued certs. Re-issue is automatic, so this is
      # only a convenience — but it means HTTPS works the minute the new box
      # boots, and it keeps a migration from spending a Let's Encrypt
      # duplicate-certificate rate limit on ~15 vhosts at once.
      "/var/lib/acme"
      # The bridge's long-term identity: lose it and the relay comes back as
      # a brand-new bridge (new fingerprint, reputation and uptime history
      # reset, and any obfs4 bridgeline already handed out stops working).
      "/var/lib/tor"
      # Accounts, watch state and library metadata. The MEDIA is deliberately
      # not backed up (below), but "who watched what, and where they left
      # off" is not re-acquirable from anywhere.
      "/var/lib/jellyfin"
      # Torrent files + resume state. Tiny, and without it every active
      # transfer restarts from zero and re-hashes.
      "/var/lib/transmission"

      config.my.cloud-suite.nextcloud.dataDir # /srv/encrypted/nextcloud
      config.my.cloud-suite.bitwarden.dataDir # /srv/encrypted/vaultwarden
      config.my.cloud-suite.immich.mediaLocation # /srv/encrypted/immich
      "/srv/shared" # Samba share (media/downloads excluded)
    ];

    # Keep the big, re-acquirable trees out of the off-site copy.
    exclude = [
      "/srv/shared/Media"
      "/srv/shared/Downloads"
      # 1.2 T of sequencing data — on its own it was ~60% of every snapshot
      # and pushed the repo past 2 TiB, which is the difference between a
      # restore measured in hours and one measured in days (plus the B2
      # egress to match). It is bulk source data, not service state, so it
      # belongs on its own copy (a second local disk, or a separate restic
      # repo with its own retention) rather than in the nightly one whose job
      # is getting this HOST back.
      "/srv/shared/NGS"
      # Re-derivable from the media itself: artwork/NFO scraped from the
      # metadata providers. The parts of /var/lib/jellyfin worth keeping
      # (library.db, users, playstate) are not in here. Transcodes need no
      # exclude: Jellyfin writes them under its cacheDir
      # (/var/cache/jellyfin), which is not a backup path at all.
      "/var/lib/jellyfin/metadata"
      # Immich's derivatives live INSIDE mediaLocation, so without these
      # they ride along with the originals — regenerable data (3.x
      # derivatives can rival the originals in size) paying for B2 space
      # and restore time. Immich rebuilds both from the originals;
      # profile/ (avatars, not regenerable) stays in.
      "${config.my.cloud-suite.immich.mediaLocation}/thumbs"
      "${config.my.cloud-suite.immich.mediaLocation}/encoded-video"
      "/srv/shared/**/.incomplete"
      "/var/lib/hass/*.log*"
      # Per-home caches / build artifacts: re-acquirable and they churn every
      # snapshot. Drops ~7.7G of /home/alex's 8.2G while keeping keys, configs,
      # histories, Org, and ~/.claude (memory + transcripts).
      "/home/*/.cache"
      "/home/*/.cargo"
      "/home/*/.npm"
      "/home/*/.local/share/uv"
      "/home/*/.claude/projects/*/shell-snapshots" # ephemeral shell captures
      "/home/alex/nominatim" # Geofabrik import data, re-downloadable
      "/home/alex/nix-config" # version-controlled + pushed to GitHub
    ];

    # PostgreSQL: dump every live DB except the huge, re-importable Nominatim
    # extract (rebuild from Geofabrik, not worth the off-site GB).
    postgres.excludeDatabases = [ "nominatim" ];

    # SQLite services snapshot-copied consistently before upload.
    sqliteDatabases = [
      {
        name = "grafana";
        path = "/var/lib/grafana/grafana.db";
      }
      {
        name = "ntfy";
        path = "/var/lib/ntfy-sh/user.db";
      }
    ];

    # Quiesce NextCloud during the backup so files + DB agree.
    nextcloudOccBin = "${config.services.nextcloud.occ}/bin/nextcloud-occ";

    # Retention: 7 daily, 4 weekly, 6 monthly (host default; here explicit).
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];

    # Failure alerting is handled by my.ntfy-alert — restic-backups-homeserver
    # is opted into its failureUnits in ./monitoring.nix.
  };
}
