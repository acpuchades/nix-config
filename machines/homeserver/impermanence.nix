{ config, lib, pkgs, ... }:
#
# Ephemeral root for the homeserver.
#
# Layout assumed on the root NVMe (see hardware-configuration.nix for UUIDs):
#   nvme-rootp1   vfat   → /boot
#   nvme-rootp2   swap
#   nvme-rootp3   btrfs  with subvolumes:
#       @            → /              (wiped to @root-blank every boot)
#       @root-blank  →                (never mounted; snapshot template)
#       @nix         → /nix
#       @persist     → /persist       (whitelisted state, see below)
#       @log         → /var/log
#
# /srv and /srv/encrypted are unaffected — Bitcoin, Postgres, NextCloud,
# Vaultwarden, Immich, Prefect all keep their data dirs there.
#
# ---------------------------------------------------------------------------
# Migration checklist (one-time, from the live USB before first impermanent boot)
# ---------------------------------------------------------------------------
# Copy the following from the current ext4 root into /mnt/persist/<same path>
# so the system can boot and services don't start with empty state:
#
#   MANDATORY (system won't boot / decrypt without these):
#     /etc/machine-id
#     /etc/ssh/ssh_host_ed25519_key       ← sops age key derives from this
#     /etc/ssh/ssh_host_ed25519_key.pub
#     /etc/ssh/ssh_host_rsa_key
#     /etc/ssh/ssh_host_rsa_key.pub
#     /var/lib/nixos                      ← UID/GID allocations, neededForUsers
#
#   SERVICE STATE (regenerates if dropped, but you'll lose history / settings):
#     /var/lib/AdGuardHome                ← filter cache, query log, stats
#     /var/lib/caddy                      ← ACME account + issued certs.
#                                           Losing this re-requests every cert
#                                           on first boot — Let's Encrypt rate
#                                           limits will bite if you have many.
#     /var/lib/fail2ban                   ← ban database
#     /var/lib/hass                       ← Home Assistant config + recorder DB
#                                           (re-pair integrations if dropped)
#     /var/lib/nextcloud                  ← cloud-suite NextCloud config.php +
#                                           occ secrets (user files are on
#                                           /srv/encrypted/nextcloud — separate)
#     /var/lib/prometheus2                ← server-stats TSDB; losing this drops
#                                           ALL historical metrics. Biggest one.
#     /var/lib/grafana                    ← server-stats users/orgs/annotations
#                                           (dashboards are provisioned, safe)
#     /var/spool/postfix                  ← mail-relay queue. Drop = lose any
#                                           mail Postfix hadn't delivered yet.
#     /etc/wireguard/profiles.d           ← vpn-server peer profiles created by
#                                           `wg-create-profile` at runtime.
#                                           Server privkey is sops, peers aren't.
#     /var/lib/systemd                    ← persistent timer state, random-seed,
#                                           coredump index
#
#   OPTIONAL (skip unless you actually use them):
#     /var/lib/ddclient                   ← last-known-IP cache; ddclient just
#                                           re-queries on boot, low value.
#     /var/lib/cups                       ← print queue + printer definitions;
#                                           printing.enable is on but this is
#                                           a server — likely unused.
#
#   USER STATE:
#     /home/alex                          ← whole home, or cherry-pick
#                                           .ssh, .gnupg, .config, .local/share
#
#   OPTIONAL:
#     /var/log                            ← lives on its own @log subvolume; copy
#                                           if you want journald history preserved
#
# Anything NOT in the list above is intentionally ephemeral. If a service
# breaks on first impermanent boot, that's the discovery — add it here and
# rebuild.
#
# ---------------------------------------------------------------------------
# Rollback unit (initrd, runs before sysroot is mounted)
# ---------------------------------------------------------------------------

let
  # Derived from hardware-configuration.nix so the UUID lives in exactly one
  # place. Assumes `/` is mounted by-uuid (it is, in the post-install layout).
  rootDevice = config.fileSystems."/".device;
  rootBtrfsUuid =
    assert lib.assertMsg
      (lib.hasPrefix "/dev/disk/by-uuid/" rootDevice)
      "impermanence: expected fileSystems.\"/\".device to be /dev/disk/by-uuid/<uuid>, got ${rootDevice}";
    lib.removePrefix "/dev/disk/by-uuid/" rootDevice;
in
{
  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.services.rollback-root = {
    description = "Rollback / to @root-blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "dev-disk-by\\x2duuid-${rootBtrfsUuid}.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      mount -t btrfs -o subvol=/ /dev/disk/by-uuid/${rootBtrfsUuid} /mnt

      # Delete any nested subvolumes inside @ before deleting @ itself,
      # otherwise btrfs refuses with ENOTEMPTY.
      btrfs subvolume list -o /mnt/@ \
        | cut -f9 -d' ' \
        | while read sub; do
            btrfs subvolume delete "/mnt/$sub"
          done

      btrfs subvolume delete /mnt/@
      btrfs subvolume snapshot /mnt/@root-blank /mnt/@

      umount /mnt
    '';
  };

  # ---------------------------------------------------------------------------
  # Persistence whitelist
  # ---------------------------------------------------------------------------
  # Mirrors the migration checklist above. Adding an entry here only makes the
  # bind-mount; you still need the underlying directory under /persist (either
  # migrated from the old system, or auto-created empty on first boot).

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/AdGuardHome"
      "/var/lib/caddy"
      "/var/lib/fail2ban"
      "/var/lib/hass"
      "/var/lib/nextcloud"
      "/var/lib/prometheus2"
      "/var/lib/grafana"
      "/var/spool/postfix"
      "/etc/wireguard/profiles.d"
      {
        directory = "/home/alex";
        user = "alex";
        group = "users";
        mode = "0700";
      }
    ];

    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # sops-nix derives its age key from the SSH host key, which lives on
  # /persist. /persist must therefore be mounted before stage-2 activation —
  # set neededForBoot = true on the /persist entry in hardware-configuration.nix.
}
