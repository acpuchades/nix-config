{ config, lib, pkgs, ... }:

{
  options.my.dns-filtering = {
    enable = lib.mkEnableOption "DNS filtering with AdGuard Home and DNSCrypt";
    
    adguardPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for AdGuard Home web interface";
    };
    
    dnsPort = lib.mkOption {
      type = lib.types.port;
      default = 53;
      description = "DNS port";
    };
    
    dnscryptPort = lib.mkOption {
      type = lib.types.port;
      default = 5300;
      description = "DNSCrypt proxy port";
    };
    
    upstreamServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "dns4eu-unfiltered"
        "quad9-dnscrypt-ip4-nofilter-pri"
      ];
      description = "DNSCrypt upstream servers";
    };
    
    filterLists = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Ads
        "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
        "https://easylist.to/easylist/easylist.txt"
        "https://easylist.to/easylist/easyprivacy.txt"
        # Privacy
        "https://easylist.to/easylist/fanboy-enhanced-tracking.txt"
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml"
      ];
      description = "List of filter URLs to use";
    };
    
    basicAuthFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Basic auth file for web interface";
    };
    
    virtualHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Virtual host for reverse proxy";
    };
  };

  config = lib.mkIf config.my.dns-filtering.enable {
    # DNSCrypt proxy
    services.dnscrypt-proxy = {
      enable = true;
      settings = {
        server_names = config.my.dns-filtering.upstreamServers;
        require_dnssec = true;
        require_nofilter = true;
        listen_addresses = [
          "127.0.0.1:${toString config.my.dns-filtering.dnscryptPort}"
          "[::1]:${toString config.my.dns-filtering.dnscryptPort}"
        ];
      };
    };

    # Adguard Home
    services.adguardhome = {
      enable = true;
      settings = {
        dns = {
          bind_host = "0.0.0.0";
          port = config.my.dns-filtering.dnsPort;
          upstream_dns = [ "127.0.0.1:${toString config.my.dns-filtering.dnscryptPort}" ];
        };
        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          parental_enabled = false;
          safe_search.enabled = false;
          filters = map(url: { enabled = true; url = url; }) config.my.dns-filtering.filterLists;
        };
      };
    };

    # Nginx reverse proxy (if virtual host is specified)
    services.nginx.virtualHosts = lib.mkIf (config.my.dns-filtering.virtualHost != null) {
      ${config.my.dns-filtering.virtualHost} = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile = config.my.dns-filtering.basicAuthFile;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.my.dns-filtering.adguardPort}";
        };
      };
    };
  };
}
