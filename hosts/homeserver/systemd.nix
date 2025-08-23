{ ... }:
{
  services.NetworkManager-ensure-profiles.before = [ "NetworkManager.service" ];
  services.NetworkManager-ensure-profiles.wants  = [ "NetworkManager.service" ];

}
