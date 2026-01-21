{ config, ... }:
{
  hostName = "homeserver"; # Define your hostname.

  # Pick only one of the below networking options.
  # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networkmanager = {
    enable = true; # Easiest to use and most distros use this by default.
    dns = "systemd-resolved";
    wifi.backend = "iwd";
    wifi.powersave = false;
    unmanaged = [ "wlan1" ];
  };

  wireless = {
    iwd.enable = true;
  };

  # DNS name servers
  nameservers = [
    "127.0.0.1"
    "::1"
  ];

  nftables = {
    enable = true;
    ruleset = ''
      table inet mangle {
        chain prerouting {
          type filter hook prerouting priority -150;
          iifname "wlan1" meta mark set 0x1
        }
      }
    '';
  };

  # Enable NAT
  nat = {
    enable = true;
    externalInterface = "wlan1";
    internalInterfaces = [ "wg-vpn-in" ];
  };

  # Configure network proxy if necessary
  # proxy.default = "http://user:password@proxy:port/";
  # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable firewall
  firewall = {
    enable = true;
    # Open ports in the firewall.
    allowedTCPPorts = [
      53    # dns
      80    # http
      443   # https
      8333  # bitcoin
    ];
    allowedUDPPorts = [
      53    # dns
      51820 # wireguard
    ];
    trustedInterfaces = [ "wg0" ];
  };

  # Enable WireGuard
  wireguard = {
    enable = true;
    interfaces = {
      wg0 = {
        # Server interface
        ips = [ "10.0.0.1/24" ];
        listenPort = 51820;
        privateKeyFile = config.sops.secrets."wg/server/private-key".path;
        peers = [{
          # alex-iphone
          publicKey = "ydxXaMhlYBE43YdvCP00mJTiSpn907G5qb51DqTOVjA=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-iphone/psk".path;
          allowedIPs = [ "10.0.0.2/32" ];
        } {
          # alex-ipad
          publicKey = "nP9sZryp7DwUBMjOyTnjEEXOV8PeMJNchn+WN9IM8FQ=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-ipad/psk".path;
          allowedIPs = [ "10.0.0.3/32" ];
        } {
          # alex-macbookpro
          publicKey = "rbTxWfmkK3YAGRqAPqic3br14/bocwW0o2qThWfgjDE=";
          presharedKeyFile = config.sops.secrets."wg/peers/alex-macbookpro/psk".path;
          allowedIPs = [ "10.0.0.4/32" ];
        } {
          # mubin-phone
          publicKey = "vOJgOdMoC1YTfNyJM9LVnJMQSRzc7tAatJJNoEY4DnA=";
          presharedKeyFile = config.sops.secrets."wg/peers/mubin-phone/psk".path;
          allowedIPs = [ "10.0.0.5/32" ];
        } {
          # mubin-laptop
          publicKey = "2HGtWcDxkTjZM24qqtFwg3BSIBSE9dBeedlUZOygpBE=";
          presharedKeyFile = config.sops.secrets."wg/peers/mubin-laptop/psk".path;
          allowedIPs = [ "10.0.0.6/32" ];
        }];
      };
      wg-vpn-in = {
        ips = [ "10.2.0.2/32" ];
        table = "51820";
        fwMark = "0x1";
        privateKeyFile = config.sops.secrets."vpn/in/wg-private-key".path;
        peers = [{
          publicKey = "QnqJI0C2xQZrKfZLrBaCHa2h3TZ9CBt6sCuzg3ue4X4=";
          endpoint = "146.70.142.18:51820";
          allowedIPs = [ "0.0.0.0/0" ];
          persistentKeepalive = 25;
        }];
      };
    };
  };
}
