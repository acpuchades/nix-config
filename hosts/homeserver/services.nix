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
    enable = true;pulse.enable = true;
  };

  # Enable CUPS to print documents
  printing.enable = true;

  # Enable fstrim
  fstrim.enable = true;

  # Timestamps & logs
  timesyncd.enable = true;

  # Avahi/mDNS (.local)
  avahi = {
    enable = true;
    nssmdns4 = true;
    publish.enable = true;
    publish.userServices = true;
  };

  # DDClient
  ddclient = {
    enable = true;
    configFile = config.sops.templates."ddclient/config".path;
  };

  # DNSCrypt
  dnscrypt-proxy2 = {
    enable = true;
    settings = {
      server_names = [
        "dns4eu-unfiltered"
        "quad9-dnscrypt-ip4-nofilter-pri"
      ];
      require_dnssec = true;
      require_nolog = true;
      require_nofilter = true;
      listen_addresses = [
        "127.0.0.1:53"
        "192.168.1.2:53"
        "10.0.0.1:53"
        "[::1]:53"
      ];
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

      "prefect.acpuchades.com" = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile =
          config.sops.secrets."prefect/htpasswd".path;
        locations."/" = {
          proxyPass = "http://127.0.0.1:4200";
          proxyWebsockets = true;
        };
      };

    };
  };

  # Postgres
  postgresql = {
    enable = true;
    ensureDatabases = [ "prefect" ];
    ensureUsers = [
      {
        name = "prefect";
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
    baseUrl = "https://prefect.acpuchades.com";
    workerPools = {
      default.installPolicy = "always";
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

}
