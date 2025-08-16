{ ... }:
{
  "/" = {
	device = "/dev/disk/by-uuid/851be909-0cca-43a0-83c2-a36e353c28a5";
	fsType = "ext4";
	options = [ "noatime" "nodiratime" ];
  };

  "/boot" = {
	device = "/dev/disk/by-uuid/AA54-7CAB";
	fsType = "vfat";
  };
}
