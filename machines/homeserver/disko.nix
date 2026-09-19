# Declarative description of this host's disk layout, for PROVISIONING ONLY.
#
# disko.enableConfig = false is the load-bearing line: with it, this file
# generates NO fileSystems/boot/swap config at runtime — hardware-configuration
# .nix remains the single authority for the live system, and importing this
# module changes nothing about how the machine boots today. What it buys is
# that the layout MIGRATION.md used to describe only in prose is now
# executable: on new hardware,
#
#   disko --mode format --flake .#homeserver   # NEW blank disks only
#   disko --mode mount  --flake .#homeserver   # or: mount an existing layout
#
# reproduces/attaches the layout below. NEVER run `format` (or `destroy`)
# against the live disks — `mount` is the only mode that is safe here.
#
# Device paths are the CURRENT hardware's stable by-id names; on replacement
# hardware they are the first thing to edit (lsblk -o NAME,MODEL,SERIAL).
# After a real format, refresh hardware-configuration.nix's UUIDs as before —
# this file provisions, it does not replace the generated config.
#
# Captured from the live system 2026-09-19 (lsblk + hardware-configuration):
#   nvme0n1  512G NVMe: ESP 512M vfat /boot · 4G swap · rest ext4 /
#   sda      6T USB (TerraMas bay): LUKS2 (tpm2 unlock via crypttab in
#            default.nix) → btrfs /srv/encrypted
#   sdb      6T USB (TerraMas bay): whole-disk btrfs /srv
# (zram swap is runtime config, not a disk, and lives in settings.nix.)
{
  disko.enableConfig = false;

  disko.devices.disk = {
    system = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-TWSC_TSC3AN512-F2T60S_TTSMA254AX16249";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0022" "dmask=0022" ];
            };
          };
          swap = {
            size = "4G";
            content.type = "swap";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };

    # Whole-disk btrfs, no partition table — that is how the live disk is laid
    # out, so this mirrors it rather than "improving" it.
    srv = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD60EZAX-00C8VB0_WD-WX32D45H5FVN";
      content = {
        type = "filesystem";
        format = "btrfs";
        mountpoint = "/srv";
        mountOptions = [
          "compress=zstd"
          "noatime"
          "nofail"
          "x-systemd.before=systemd-tmpfiles-setup.service"
        ];
      };
    };

    # Whole-disk LUKS2 → btrfs. The live unlock is TPM2-bound via
    # environment.etc."crypttab" in default.nix (not initrd); a fresh format
    # here asks for a passphrase, and the TPM enrollment is re-done afterwards
    # with systemd-cryptenroll (MIGRATION.md §3).
    srv-encrypted = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD60EZAX-00C8VB0_WD-WX42D45P44NT";
      content = {
        type = "luks";
        name = "srv-encrypted";
        content = {
          type = "filesystem";
          format = "btrfs";
          mountpoint = "/srv/encrypted";
          mountOptions = [
            "compress=zstd"
            "noatime"
            "nofail"
            "x-systemd.before=systemd-tmpfiles-setup.service"
          ];
        };
      };
    };
  };
}
