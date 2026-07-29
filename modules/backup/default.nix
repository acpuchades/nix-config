{ config, lib, pkgs, ... }:

#
# backup — encrypted off-site backups with restic.
#
# A thin, opinionated wrapper over the upstream `services.restic.backups`
# module. restic encrypts EVERYTHING client-side (AES-256) before a single byte
# leaves the host, so the destination (Backblaze B2 here) only ever sees an
# opaque, deduplicated, content-addressed blob store. The repo password and the
# B2 credentials both come from sops — see `passwordFile`/`environmentFile`.
#
# Two things this wrapper adds on top of plain restic, because backing up live
# service state by copying files alone is subtly wrong:
#
#   - Databases are dumped, not file-copied. A PostgreSQL data directory copied
#     while the server is running is torn — pages half-written, WAL mid-flight —
#     and may restore to a corrupt cluster. So a `backupPrepareCommand` runs
#     `pg_dump` (custom format, per database) plus a `pg_dumpall --globals-only`
#     for roles/grants into a staging dir, and restic backs up THAT. SQLite
#     databases (grafana, ntfy) get the same treatment via `.backup`, which
#     takes a consistent snapshot even under concurrent writes.
#
#   - NextCloud is quiesced. With `nextcloudOccBin` set, the prepare step flips
#     NextCloud into maintenance mode before the DB dump and the file copy, and
#     the cleanup step flips it back off — so the copied `data/` tree and the
#     dumped DB agree with each other. Cleanup runs as ExecStopPost, i.e. even
#     if the backup fails, so maintenance mode is never left stuck on.
#
# What is deliberately NOT backed up is a design choice, set in the host config:
# Bitcoin's chainstate (re-syncs from the network), the Nominatim DB (re-import
# from Geofabrik), and the media/downloads under the Samba share (large, and
# either re-acquirable or already backed up at the source). Keeping those out is
# what makes an off-site copy affordable.
#
# Restore, for when you need it (repo password + B2 creds in the environment):
#   restic -r <repository> snapshots
#   restic -r <repository> restore latest --target /restore --include /home/eva
# PostgreSQL dumps land under <stagingDir>/postgres/<db>.dump; restore one with
#   pg_restore --clean --create -d postgres /restore/<stagingDir>/postgres/<db>.dump
#

let
  cfg = config.my.backup;

  # Staging tree the prepare step fills and the cleanup step wipes. Lives on the
  # root fs (not the encrypted spinning disk) so a dump can run even if that
  # disk is the thing being recovered.
  staging = cfg.stagingDir;

  psql = "${cfg.postgresqlPackage}/bin/psql";
  pg_dump = "${cfg.postgresqlPackage}/bin/pg_dump";
  pg_dumpall = "${cfg.postgresqlPackage}/bin/pg_dumpall";

  # Run a command as the postgres superuser. The prepare step runs as root
  # (restic's service user); postgres peer auth on the local socket trusts the
  # `postgres` system user, so this is how we authenticate without a password.
  asPostgres = c: "${pkgs.util-linux}/bin/runuser -u postgres -- ${c}";

  excludeArg = lib.concatStringsSep " "
    (map (e: "'${lib.escape [ "'" ] e}'") cfg.postgres.excludeDatabases);

  prepareScript = pkgs.writeShellApplication {
    name = "backup-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.sqlite ];
    text = ''
      umask 077
      rm -rf ${staging}
      mkdir -p ${staging}

      ${lib.optionalString (cfg.nextcloudOccBin != null) ''
        # Quiesce NextCloud so the file tree and the DB dump are mutually
        # consistent. Cleanup (ExecStopPost) turns this back off unconditionally.
        echo "backup: NextCloud → maintenance mode on"
        ${cfg.nextcloudOccBin} maintenance:mode --on
      ''}

      ${lib.optionalString cfg.postgres.enable ''
        echo "backup: dumping PostgreSQL"
        mkdir -p ${staging}/postgres
        # Roles, tablespaces and grants are cluster-global — not in any single
        # per-database dump — so capture them once here.
        ${asPostgres pg_dumpall} --globals-only > ${staging}/postgres/globals.sql
        # One compressed custom-format dump per live database, minus the
        # excluded ones (large/re-importable). Enumerated at runtime so new
        # databases are picked up automatically.
        dbs=$(${asPostgres psql} -tAc \
          "SELECT datname FROM pg_database \
             WHERE datistemplate = false AND datallowconn \
               AND datname NOT IN ('postgres'${lib.optionalString (cfg.postgres.excludeDatabases != []) ", ${excludeArg}"});")
        # Write via a root shell redirect (not pg_dump --file), so the output
        # file is created by root: the postgres process only writes to the
        # already-open fd, and can't otherwise write into the 0700 staging dir.
        for db in $dbs; do
          echo "backup:   pg_dump $db"
          ${asPostgres "${pg_dump} --format=custom --compress=6"} \
            "$db" > "${staging}/postgres/$db.dump"
        done
      ''}

      ${lib.concatMapStringsSep "\n" (db: ''
        if [ -f '${db.path}' ]; then
          echo "backup: sqlite .backup ${db.name}"
          ${pkgs.sqlite}/bin/sqlite3 '${db.path}' ".backup '${staging}/${db.name}.sqlite'"
        else
          echo "backup: sqlite ${db.name} missing (${db.path}), skipping"
        fi
      '') cfg.sqliteDatabases}

      echo "backup: prepare done"
    '';
  };

  cleanupScript = pkgs.writeShellApplication {
    name = "backup-cleanup";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${lib.optionalString (cfg.nextcloudOccBin != null) ''
        echo "backup: NextCloud → maintenance mode off"
        ${cfg.nextcloudOccBin} maintenance:mode --off || true
      ''}
      # Wipe the staged dumps — they are plaintext DB contents and must not
      # linger on disk after restic has captured them.
      rm -rf ${staging}
      echo "backup: cleanup done"
    '';
  };

  # Paths restic actually uploads: the caller's file paths, plus the staging
  # dir whenever we produced dumps there.
  backupPaths = cfg.paths
    ++ lib.optional (cfg.postgres.enable || cfg.sqliteDatabases != []) staging;
in
{
  options.my.backup = {
    enable = lib.mkEnableOption "Encrypted off-site backups with restic";

    repository = lib.mkOption {
      type = lib.types.str;
      example = "b2:acpuchades-homeserver-restic:restic";
      description = "restic repository URL (e.g. a Backblaze B2 bucket).";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        File holding the restic repository password (from sops). This is the ONLY
        thing that decrypts the backups — store a copy OFF this server too, or a
        server loss makes every snapshot unrecoverable.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file with the backend credentials (from a sops template),
        e.g. B2_ACCOUNT_ID / B2_ACCOUNT_KEY for Backblaze B2.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Filesystem paths to back up (in addition to DB dumps).";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "restic exclude patterns applied to the backed-up paths.";
    };

    stagingDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/backup/dumps";
      description = "Directory the DB dumps are written to before upload (wiped after).";
    };

    postgresqlPackage = lib.mkOption {
      type = lib.types.package;
      default = config.services.postgresql.package;
      defaultText = lib.literalExpression "config.services.postgresql.package";
      description = "PostgreSQL package providing pg_dump/psql for the dumps.";
    };

    postgres = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Dump all live PostgreSQL databases (minus excludeDatabases) before upload.";
      };
      excludeDatabases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "nominatim" ];
        description = "Databases to skip (large and/or reproducible from source).";
      };
    };

    sqliteDatabases = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Label for the staged copy (<name>.sqlite).";
          };
          path = lib.mkOption {
            type = lib.types.str;
            description = "Path to the live SQLite database file.";
          };
        };
      });
      default = [];
      description = "SQLite databases to snapshot with `.backup` before upload.";
    };

    nextcloudOccBin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression ''"''${config.services.nextcloud.occ}/bin/nextcloud-occ"'';
      description = ''
        Path to the nextcloud-occ wrapper. When set, NextCloud is put into
        maintenance mode for the duration of the backup (consistent files + DB).
        null disables the quiesce.
      '';
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
      description = "restic forget/prune retention policy.";
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        OnCalendar = "daily";
        RandomizedDelaySec = "30m";
        Persistent = "true";
      };
      description = "systemd timer config controlling when the backup runs.";
    };

    notify = {
      enable = lib.mkEnableOption "ntfy push on backup failure";
      url = lib.mkOption {
        type = lib.types.str;
        example = "https://ntfy.acpuchades.com/backups";
        description = "ntfy topic URL to POST to on failure.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File with an ntfy access token (Bearer auth), if the topic requires one.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.backups.homeserver = {
      inherit (cfg) repository passwordFile environmentFile exclude pruneOpts timerConfig;
      paths = backupPaths;
      initialize = true;
      backupPrepareCommand = lib.getExe prepareScript;
      backupCleanupCommand = lib.getExe cleanupScript;
      # Prune runs after every backup so B2 usage tracks the retention policy.
      # (restic prune is a full repack; on a large repo you may later move this
      # to a weekly maintenance job instead.)
    };

    # Failure notification. onFailure fires the notify unit only when the
    # restic-backups-homeserver service exits non-zero.
    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.notify.enable {
        "restic-backups-homeserver".onFailure = [ "backup-notify-failure.service" ];

        "backup-notify-failure" = {
          description = "Notify (ntfy) that the homeserver backup failed";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe (pkgs.writeShellApplication {
              name = "backup-notify-failure";
              runtimeInputs = [ pkgs.curl pkgs.coreutils ];
              text = ''
                auth=()
                ${lib.optionalString (cfg.notify.tokenFile != null) ''
                  auth=(-H "Authorization: Bearer $(cat ${cfg.notify.tokenFile})")
                ''}
                curl -fsS "''${auth[@]}" \
                  -H "Title: Homeserver backup FAILED" \
                  -H "Priority: high" \
                  -H "Tags: rotating_light,floppy_disk" \
                  -d "restic-backups-homeserver.service failed at $(date -Is). Check: journalctl -u restic-backups-homeserver" \
                  "${cfg.notify.url}"
              '';
            });
          };
        };
      })
    ];
  };
}
