{ config, lib, pkgs, ... }:

{
  options.my.vpn-server = {
    enable = lib.mkEnableOption "VPN server with WiFi hotspot";
    
    interface = lib.mkOption {
      type = lib.types.str;
      description = "WiFi interface for the hotspot";
    };
    
    ssid = lib.mkOption {
      type = lib.types.str;
      description = "WiFi network SSID";
    };
    
    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to WiFi password file";
    };
    
    dhcpRange = lib.mkOption {
      type = lib.types.str;
      default = "192.168.10.2,192.168.10.254,12h";
      description = "DHCP range for connected clients";
    };
    
    dnsServer = lib.mkOption {
      type = lib.types.str;
      default = "10.2.0.1";
      description = "DNS server to provide to clients";
    };
    
    countryCode = lib.mkOption {
      type = lib.types.str;
      default = "ES";
      description = "WiFi country code";
    };
  };

  config = lib.mkIf config.my.vpn-server.enable {
    # DNSMasq for DHCP
    services.dnsmasq = {
      enable = true;
      settings = {
        interface = config.my.vpn-server.interface;
        bind-dynamic = true;
        port = 0; # disable DNS
        dhcp-range = [
          config.my.vpn-server.dhcpRange
        ];
        dhcp-option = [
          "option:dns-server,${config.my.vpn-server.dnsServer}"
        ];
      };
    };

    # Hostapd for WiFi hotspot
    services.hostapd = {
      enable = true;
      radios.${config.my.vpn-server.interface} = {
        band = "5g";
        channel = 0;
        countryCode = config.my.vpn-server.countryCode;
        networks = {
          ${config.my.vpn-server.interface} = {
            ssid = config.my.vpn-server.ssid;
            authentication = {
              mode = "wpa2-sha256";
              wpaPasswordFile = config.my.vpn-server.passwordFile;
            };
          };
        };
      };
    };
  };
}
