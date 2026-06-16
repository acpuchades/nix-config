{ config, ... }:
{
  networking = {
    hostName = "homeserver"; # Define your hostname.

    # Pick only one of the below networking options.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    useNetworkd = true;
    networkmanager.enable = false;

    wireless = {
      enable = true;
      interfaces = [ "wlp3s0" ];
      userControlled = false;
      secretsFile = config.sops.templates."wifi/secrets".path;
      networks."MIWIFI_5G_dehC" = {
        pskRaw = "ext:home-wlan-psk";
      };
    };

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Enable firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [
        8333  # bitcoin
      ];
    };
  };
}
