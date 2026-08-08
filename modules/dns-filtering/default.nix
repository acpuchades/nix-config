{ config, lib, pkgs, ... }:

let
  # One accept rule per (network, protocol) for the plain-DNS port, emitted as
  # bare `nixos-fw …` specs so the caller prefixes -I (insert) or -D (delete)
  # and the two stay in sync by construction.
  dnsFirewallRules = cfg:
    lib.concatMap
      (net: map
        (proto: "nixos-fw -p ${proto} -s ${net} --dport ${toString cfg.dnsPort} -j nixos-fw-accept")
        [ "udp" "tcp" ])
      cfg.allowedClientNetworks;
in
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
        "scaleway-fr"                     # Paris, maintained by dnscrypt-proxy's author
        "dnscry.pt-madrid-ipv4"           # Madrid, lowest latency from here
        "quad9-dnscrypt-ip4-nofilter-pri" # Swiss non-profit, anycast EU PoP
      ];
      description = ''
        Upstream resolver names, as they appear in dnscrypt-proxy's
        public-resolvers list. All must advertise DNSSEC + no-log + no-filter in
        their sdns:// stamp or the require_* settings below silently drop them —
        dnscrypt-proxy does not warn, it just reports fewer live servers.
        NOTE the names are matched literally: an entry that does not exist is
        ignored just as silently (this is how "dns4eu-unfiltered", which was
        never a real name, sat here unused). Verify a change with
        `journalctl -u dnscrypt-proxy | grep "live servers"` — the count must
        equal the number of entries here.

        Kept deliberately European and unfiltered: AdGuard does the filtering
        locally, so the upstream only needs to be fast, honest and quiet.
      '';
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

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict web interface access to these CIDR ranges (empty = unrestricted)";
    };

    allowedClientNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        CIDR ranges allowed to send plain DNS queries (port 53). Empty opens the
        port on every interface, which makes the box a public open resolver and
        therefore a DNS amplification reflector — set this to the local networks
        unless the resolver is meant to be public. Does not apply to DNS-over-TLS,
        which exists precisely to be reached from off-LAN.
      '';
    };

    rateLimit = lib.mkOption {
      type = lib.types.int;
      default = 200;
      description = ''
        Queries per second per client before AdGuard starts dropping them; 0
        disables the limit. AdGuard's own default is 20, which a single machine
        exceeds trivially (a parallel `nix` fetch or a browser opening many tabs),
        and the symptom is silent packet loss rather than an error — so this is
        set explicitly rather than left implicit. Keep it non-zero while port 53
        is reachable beyond the LAN: it is the only cap on amplification abuse.
      '';
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

    tls = {
      enable = lib.mkEnableOption "DNS-over-TLS";

      serverName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Server name for TLS certificate (SNI)";
      };

      certFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to TLS certificate chain (fullchain PEM)";
      };

      keyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to TLS private key (PEM)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 853;
        description = "DNS-over-TLS listen port";
      };
    };
  };

  config = lib.mkIf config.my.dns-filtering.enable {
    # Port 53 is opened globally only when no client networks are configured;
    # otherwise it is accepted per-source below, so the resolver is not exposed
    # to the internet. DoT (853) stays global on purpose — it is meant to be
    # reached from off-LAN and its clients authenticate the server by cert.
    networking.firewall.allowedTCPPorts =
      lib.optionals (config.my.dns-filtering.allowedClientNetworks == [])
        [ config.my.dns-filtering.dnsPort ] ++
      lib.optionals config.my.dns-filtering.tls.enable [ config.my.dns-filtering.tls.port ];
    networking.firewall.allowedUDPPorts =
      lib.optionals (config.my.dns-filtering.allowedClientNetworks == [])
        [ config.my.dns-filtering.dnsPort ];

    # Accept DNS only from the configured client networks. Inserted at the top of
    # the nixos-fw chain so it precedes the default refuse rule (same pattern as
    # print-server/samba-server). VPN peers are already covered by the trusted wg
    # interface; these rules cover the LAN.
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n"
      (rule: "iptables -I ${rule}")
      (dnsFirewallRules config.my.dns-filtering);

    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n"
      (rule: "iptables -D ${rule} || true")
      (dnsFirewallRules config.my.dns-filtering);

    # DNSCrypt proxy
    services.dnscrypt-proxy = {
      enable = true;
      settings = {
        server_names = config.my.dns-filtering.upstreamServers;
        require_dnssec = true;
        require_nofilter = true;
        # Only use resolvers that advertise a no-logging policy in their stamp.
        require_nolog = true;
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
          ratelimit = config.my.dns-filtering.rateLimit;
        };
        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          parental_enabled = false;
          safe_search.enabled = false;
          filters = map(url: { enabled = true; url = url; }) config.my.dns-filtering.filterLists;
          rewrites = config.my.dns-filtering.dnsRewrites;
        };
      } // lib.optionalAttrs config.my.dns-filtering.tls.enable {
        tls = {
          enabled = true;
          server_name = config.my.dns-filtering.tls.serverName;
          force_https = false;
          port_https = 0;
          port_dns_over_tls = config.my.dns-filtering.tls.port;
          port_dns_over_quic = 0;
          certificate_path = config.my.dns-filtering.tls.certFile;
          private_key_path = config.my.dns-filtering.tls.keyFile;
        };
      };
    };

    services.caddy.virtualHosts = lib.mkIf (config.my.dns-filtering.virtualHost != null) {
      ${config.my.dns-filtering.virtualHost}.extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (config.my.dns-filtering.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " config.my.dns-filtering.allowedNetworks}\nabort @denied")
        (lib.optionalString (config.my.dns-filtering.basicAuthFile != null)
          "import ${config.my.dns-filtering.basicAuthFile}")
        "reverse_proxy http://127.0.0.1:${toString config.my.dns-filtering.adguardPort}"
        "encode gzip"
      ]);
    };
  };
}
