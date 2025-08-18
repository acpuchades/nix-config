{ config, ... }:
{
  hostName = "homeserver"; # Define your hostname.

  # Pick only one of the below networking options.
  # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networkmanager.wifi.backend = "iwd";
  networkmanager.dns = "systemd-resolved";

  wireless.iwd.enable = true;

  # DNS name servers
  nameservers = [
    "127.0.0.1"
    "::1"
  ];

  # Configure network proxy if necessary
  # proxy.default = "http://user:password@proxy:port/";
  # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable firewall
  firewall.enable = true;
  # Open ports in the firewall.
  firewall.allowedTCPPorts = [
    53
    80
    443
  ];
  firewall.allowedUDPPorts = [
    53
  ];

  # Enable NAT
  nat.enable = true;
  nat.externalInterface = "wlan0";
  nat.internalInterfaces = [ "wg0" ];

  # Enable WireGuard
  wireguard = {
    enable = true;
    interfaces.wg0 = {
      # Server interface
      ips = [ "10.0.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.sops.secrets."wg/server/private-key".path;
      peers = [
        {
          # alex-iphone
          publicKey = "ydxXaMhlYBE43YdvCP00mJTiSpn907G5qb51DqTOVjA=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-iphone/psk".path;
          allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];
          endpoint = "home.acpuchades.com:51820";
          persistentKeepalive = 25;
        }
        {
          # alex-ipad
          publicKey = "nP9sZryp7DwUBMjOyTnjEEXOV8PeMJNchn+WN9IM8FQ=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-ipad/psk".path;
          allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];
          endpoint = "home.acpuchades.com:51820";
          persistentKeepalive = 25;
        }
        {
          # alex-macbookpro
          publicKey = "rbTxWfmkK3YAGRqAPqic3br14/bocwW0o2qThWfgjDE=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-macbookpro/psk".path;
          allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];
          endpoint = "home.acpuchades.com:51820";
          persistentKeepalive = 25;
        }
        {
          # mubin-phone
          publicKey = "vOJgOdMoC1YTfNyJM9LVnJMQSRzc7tAatJJNoEY4DnA=";
          presharedKeyFile = config.sops.secrets."wg/peers/mubin-phone/psk".path;
          allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];
          endpoint = "home.acpuchades.com:51820";
          persistentKeepalive = 25;
        }
        {
          # mubin-laptop
          publicKey = "2HGtWcDxkTjZM24qqtFwg3BSIBSE9dBeedlUZOygpBE=";
          presharedKeyFile = config.sops.secrets."wg/peers/mubin-laptop/psk".path;
          allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];
          endpoint = "home.acpuchades.com:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
