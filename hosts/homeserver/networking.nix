{ ... }:
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
  #nat.enable = true;
  #nat.externalInterface = externalInterface;
  #nat.internalInterfaces = [ "wg0" ];

  # Enable WireGuard
  #wireguard = {
  #  enable = true;
  #  interfaces.wg0 = {
  #    # Server interface
  #    ips = [ "192.168.200.1/24" ];
  #    listenPort = 51820;
  #    privateKeyFile = "/run/keys/wg0.key";
  #    peers = [
  #      # Example peer; add as many as needed
  #      {
  #        publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  #        presharedKeyFile = "/run/keys/wg0-psk";
  #        allowedIPs = [ "192.168.200.2/32" ];
  #        endpoint = hostDomain + ":51820";
  #        persistentKeepalive = 25;
  #      }
  #    ];
  #  };
  #};
}
