{ config, pkgs, ... }:
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

  # Fail2ban
  fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
      factor = "4";
    };
    jails = {
      sshd.settings = {
        enabled = true;
        maxretry = 3;
        findtime = "10m";
      };
    };
  };

  # OpenSSH
  openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      X11Forwarding = false;
      MaxAuthTries = 3;
      LoginGraceTime = 20;
      AllowAgentForwarding = false;
      AllowTcpForwarding = "no";
    };
  };

  # Postgres
  postgresql = {
    enable = true;
    ensureDatabases = [
      "prefect"
    ];
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
    dataDir = "/var/lib/prefect-server";
    baseUrl = "https://prefect.acpuchades.com";
    workerPools = {
      default.installPolicy = "if-not-present";
    };
  };


}
