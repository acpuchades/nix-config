{ config, ... }:
{
  # Enable the X11 windowing system.
  # xserver.enable = true;

  # Configure keymap in X11
  # xserver.xkb.layout = "us";
  # xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable touchpad support (enabled default in most desktopManager).
  # libinput.enable = true;

  # Enable sound.
  # pulseaudio.enable = true;
  # OR
  pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # Enable CUPS to print documents
  printing.enable = true;

  # Enable fstrim
  fstrim.enable = true;

  # Timestamps & logs
  timesyncd.enable = true;

  # systemd-resolved
  resolved.enable = true;

  # Adguard Home
  adguardhome = {
    enable = true;
    settings = {
      dns = {
        bind_host = "0.0.0.0";
        port = 53;
        upstream_dns = [ "127.0.0.1:5300" ];
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = false;
        safe_search.enabled = false;
        filters = map(url: { enabled = true; url = url; }) [
          # Ads
          "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
          "https://easylist.to/easylist/easylist.txt"
          "https://easylist.to/easylist/easyprivacy.txt"

          # Privacy
          "https://easylist.to/easylist/fanboy-enhanced-tracking.txt"
          "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml"
        ];
      };
    };
  };

  # Avahi/mDNS (.local)
  avahi = {
    enable = true;
    nssmdns4 = true;
    publish.enable = true;
    publish.userServices = true;
  };

  # Bitcoin
  bitcoind.main = {
    enable = true;
    dataDir = "/srv/bitcoind";
    extraConfig = ''
      server=1
      txindex=1
      rpcallowip=127.0.0.1
    '';
  };

  # DDClient
  ddclient = {
    enable = true;
    configFile = config.sops.templates."ddclient/config".path;
  };

  # DNSCrypt
  dnscrypt-proxy = {
    enable = true;
    settings = {
      server_names = [
        "dns4eu-unfiltered"
        "quad9-dnscrypt-ip4-nofilter-pri"
      ];
      require_dnssec = true;
      require_nofilter = true;
      #require_nolog = true;
      listen_addresses = [
        "127.0.0.1:5300"
        "[::1]:5300"
      ];
    };
  };

  # DNSMasq
  dnsmasq = {
    enable = true;
    settings = {
      interface = "wlp229s0f3u4";
      bind-dynamic = true;
      port = 0; # disable DNS
      dhcp-range = [
        "192.168.10.2,192.168.10.254,12h"
      ];
      dhcp-option = [
        "option:dns-server,10.2.0.1" # Proton DNS via wg-vpn-in
      ];
    };
  };

  # Hostapd
  hostapd = {
    enable = true;
    radios.wlp229s0f3u4 = {
      band = "5g";
      channel = 0;
      countryCode = "ES";
      networks = {
        wlp229s0f3u4 = {
          ssid = "HomeServerVPN-IN";
          authentication = {
            mode = "wpa2-sha256";
            wpaPasswordFile = config.sops.secrets."vpn/in/wifi-password".path;
          };
        };
      };
    };
  };

  # SMTP
  postfix = {
    enable = true;
    settings.main = {
      myorigin = "acpuchades.com";
      myhostname = "home.acpuchades.com";
      inet_interfaces = "loopback-only";
      mydestination = "localhost, localhost.localdomain, $myhostname, homeserver";
      relayhost = [ "[in-v3.mailjet.com]:587" ];
      smtp_address_preference = "ipv4";
      smtp_tls_security_level = "encrypt";
      smtp_tls_loglevel = "1";
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_password_maps = "texthash:${config.sops.templates."postfix/sasl_passwd".path}";
      smtp_sasl_security_options = "noanonymous";
    };
  };

  # Nginx
  nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {

      "www.acpuchades.com" = {
        forceSSL = true;
        enableACME = true;
      };

      "adguard.acpuchades.com" = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile = config.sops.secrets."nginx/htpasswd/adguard".path;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
        };
      };

      "bitwarden.acpuchades.com" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8000";
        };
      };

      "prefect.acpuchades.com" = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile = config.sops.secrets."nginx/htpasswd/prefect".path;
        locations."/" = {
          proxyPass = "http://127.0.0.1:4200";
          proxyWebsockets = true;
        };

      };
    };
  };

  # SSH
  openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false; # ensure you have SSH keys set
      AllowTcpForwarding = "yes";
      X11Forwarding = false;
    };
    openFirewall = true; # keep closed by default; open explicitly if needed
  };

  # Postgres
  postgresql = {
    enable = true;
    ensureDatabases = [
      "prefect"
      "vaultwarden"
    ];
    ensureUsers = [
      {
        name = "prefect";
        ensureDBOwnership = true;
      }
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
    ];
  };

  # Prefect {
  prefect = {
    enable = true;
    host = "0.0.0.0";
    port = 4200;
    database = "postgres";
    databaseHost = "";
    databasePort = 0;
    databaseUser = "prefect";
    databaseName = "prefect";
    dataDir = "/var/lib/prefect-server";
    baseUrl = "https://prefect.acpuchades.com";
    workerPools = {
      default.installPolicy = "if-not-present";
    };
  };

  # Bitwarden
  vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    config = {
      DOMAIN = "https://bitwarden.acpuchades.com";
      DATABASE_URL = "postgresql://vaultwarden?host=/var/run/postgresql";
      SIGNUPS_ALLOWED = false;
      SMTP_HOST = "127.0.0.1";
      SMTP_PORT = 25;
      SMTP_SSL = false;
      SMTP_FROM = "noreply@acpuchades.com";
      SMTP_FROM_NAME = "acpuchades.com Bitwarden Server";
    };
  };

}
