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

    dnsResolverPort = lib.mkOption {
      type = lib.types.port;
      default = 5300;
      description = "Local port for the DNS resolver proxy";
    };

    upstreamServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "dns4eu-unfiltered"
        "quad9-dnscrypt-ip4-nofilter-pri"
      ];
      description = "Upstream DNS resolver server names";
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

    dnsRewrites = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          domain = lib.mkOption { type = lib.types.str; };
          answer = lib.mkOption { type = lib.types.str; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; };
        };
      });
      default = [];
      description = "DNS rewrites for AdGuard Home (domain → IP)";
    };
  };

  config = lib.mkIf config.my.dns-filtering.enable {
    networking.firewall.allowedTCPPorts = [ config.my.dns-filtering.dnsPort ];
    networking.firewall.allowedUDPPorts = [ config.my.dns-filtering.dnsPort ];

    # DNSCrypt proxy
    services.dnscrypt-proxy = {
      enable = true;
      settings = {
        server_names = config.my.dns-filtering.upstreamServers;
        require_dnssec = true;
        require_nofilter = true;
        listen_addresses = [
          "127.0.0.1:${toString config.my.dns-filtering.dnsResolverPort}"
          "[::1]:${toString config.my.dns-filtering.dnsResolverPort}"
        ];
      };
    };

    # Adguard Home
    services.adguardhome = {
      enable = true;
      mutableSettings = false;
      settings = {
        dns = {
          bind_host = "0.0.0.0";
          port = config.my.dns-filtering.dnsPort;
          upstream_dns = [ "127.0.0.1:${toString config.my.dns-filtering.dnsResolverPort}" ];
          bootstrap_dns = [ "1.1.1.1" "1.0.0.1" ];
        };
        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          parental_enabled = false;
          safe_search.enabled = false;
          filters = map(url: { enabled = true; url = url; }) config.my.dns-filtering.filterLists;
          rewrites = config.my.dns-filtering.dnsRewrites;
        };
      };
    };

    services.caddy.virtualHosts = lib.mkIf (config.my.dns-filtering.virtualHost != null) {
      ${config.my.dns-filtering.virtualHost}.extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (config.my.dns-filtering.basicAuthFile != null)
          "import ${config.my.dns-filtering.basicAuthFile}")
        "reverse_proxy http://127.0.0.1:${toString config.my.dns-filtering.adguardPort}"
        "encode gzip"
      ]);
    };
  };
}
