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

  # systemd-resolved → AdGuard Home → dnscrypt-proxy
  resolved = {
    enable = true;
    extraConfig = "DNSStubListener=no";
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
      # Parallelism
      par=0                   # 0 = auto-detect cores; explicit value caps it

      # Mempool — bigger = more fee-rate visibility, more RAM
      maxmempool=1000         # MiB; default 300

      # Connection limits
      maxconnections=64       # default 125; lower = less bandwidth/CPU
      maxuploadtarget=5000    # MiB/day cap on upload to peers; 0 = unlimited

      # Indexes you may want for analysis work
      txindex=1
      coinstatsindex=1        # UTXO set statistics; useful for chain analysis
      # blockfilterindex=1    # BIP157/158 compact filters; enable if you query them

      # Persist mempool across restarts
      persistmempool=1

      # Disable wallet entirely (not in use)
      disablewallet=1
    '';
  };

  # DDClient
  ddclient = {
    enable = true;
    configFile = config.sops.templates."ddclient/config".path;
  };

  # OpenSSH
  openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
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
    dataDir = "/srv/encrypted/postgresql";
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

}
