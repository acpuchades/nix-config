{ pkgs, ... }:
{
  services.NetworkManager-ensure-profiles.before = [ "NetworkManager.service" ];
  services.NetworkManager-ensure-profiles.wants  = [ "NetworkManager.service" ];

  services.ddclient.after = [ "network-online.target" ];
  services.ddclient.requires = [ "network-online.target" ];

  tmpfiles.rules = [
    "d /srv/fugazi 2770 fugazi fugazi -"
  ];
}
