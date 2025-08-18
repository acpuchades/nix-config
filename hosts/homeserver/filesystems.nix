{ ... }:
{
  "/" = {
    device = "/dev/disk/by-uuid/851be909-0cca-43a0-83c2-a36e353c28a5";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  "/boot" = {
    device = "/dev/disk/by-uuid/AA54-7CAB";
    fsType = "vfat";
  };

  "/srv" = {
    device = "/dev/disk/by-uuid/4f9f29bd-6a19-4cfa-8163-9be6ee7171f5";
    fsType = "btrfs";
    options = [ "noatime" ];
  };

}
