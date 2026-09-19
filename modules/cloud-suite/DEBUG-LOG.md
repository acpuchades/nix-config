# cloud-suite — working log

Append-only. Newest entry at the bottom.

---

## 2026-09-19 — cloud.acpuchades.com returned 503 on every request

### Symptom

Every request 503. Both `phpfpm-nextcloud` and `nginx` were **active and healthy**,
and nginx returned the 503 itself:

```
$ curl -H 'Host: cloud.acpuchades.com' http://127.0.0.1:8080/
App directory "/nix/store/1ixwdg6…-nextcloud-33.0.8-with-apps/store-apps" not found!
```

So the failure was inside Nextcloud's PHP bootstrap, not the web tier. Note the
path: **33.0.8**, while the running package is **33.0.9**.

### Cause

Nextcloud has two config sources and they disagreed:

* `override.config.php` — a tmpfiles `L+` symlink into the store, regenerated
  every activation. **This was correct**, listing only `…33.0.9-with-apps/apps`
  and `…/nix-apps`. Correctly no `store-apps`, because `appstoreEnable = false`.
* `config.php` — **stateful**, and it carried its own `apps_paths` with *three*
  entries. Indices 0 and 1 tracked 33.0.9 fine. Index 2 pointed at
  `…33.0.8-with-apps/store-apps`.

Nextcloud writes its merged in-memory config back to `config.php` on some
`setValue` paths, which is how the generated entries ended up duplicated there
and how the extra third entry kept riding along across upgrades.

Two things were wrong with that entry, not one:

1. It referenced a package version that had since been **garbage-collected**, so
   the directory genuinely did not exist.
2. `store-apps` was never valid as a *store* path anyway — it is meant to be
   **writable**, at `${cfg.home}/store-apps` (`/var/lib/nextcloud/store-apps`).
   A read-only store path could never have served its purpose.

**So this broke when nix-collect-garbage ran, not when the package was bumped.**
Before GC it "worked" while quietly loading apps out of a superseded package.

### Why it could not self-heal

A deadlock: the repair is `occ config:system:delete apps_paths`, but **`occ`
refuses to start on the same broken config**. And `nextcloud-setup.service`
**exits 0** while every `occ` call inside it fails — systemd reported
`Finished nextcloud-setup.service` with the error printed four times. Nothing
alerted, and rebuilding changed nothing.

### Fix

Removed the whole `apps_paths` key from the stateful `config.php`, leaving the
generated `override.config.php` as its only source. Done with a backup +
`php -l` validation + automatic rollback (`scratchpad/nc-fix.sh`), because that
file also holds `dbpassword`, `passwordsalt` and `secret`.

Result: `status.php` 200, all five vhosts healthy, `occ` working again
(`nextcloud-setup` now enables apps and sets `trusted_domains` normally), and

```
apps_paths:
  0: …33.0.9-with-apps/apps
  1: …33.0.9-with-apps/nix-apps
```

Backup at `/srv/encrypted/nextcloud/config/config.php.bak-20260919-020532`.

### Notes

* **`trusted_domains` is not in `config.php`** and should not be — it comes from
  the declarative settings JSON via `override.config.php`. A sanity check that
  expects it there will report a false "MISSING".
* Deriving a helper binary path with `nix eval` gives an *evaluated* store path
  that may never have been **realised**. Discover it from a running unit instead
  (`systemctl show -p ExecStart --value phpfpm-nextcloud`).
* **Unresolved weakness:** `nextcloud-setup.service` succeeding while `occ`
  fails means a totally dead Nextcloud looks green to systemd, so the existing
  `my.ntfy-alert` unit-failure alerting never fired. A health check that fails
  the unit when Nextcloud does not respond would have caught this immediately.
