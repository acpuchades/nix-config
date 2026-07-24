{ config, pkgs, ... }:
{
  services = {
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

    # CUPS network print server (IPP/AirPrint) is configured by the
    # my.print-server module, which owns services.printing.

    # Enable fstrim
    fstrim.enable = true;

    # Timestamps & logs
    timesyncd.enable = true;

    # systemd-resolved → AdGuard Home → dnscrypt-proxy
    resolved = {
      enable = true;
      settings.Resolve.DNSStubListener = false;
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

        # UTXO cache — soft ceiling, not a reservation: bitcoind flushes to
        # disk under memory pressure, so it yields RAM to other workloads.
        # Big win for IBD/reindex/validation speed. Default 450 MiB.
        dbcache=4000            # MiB

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
      # shared_buffers is allocated at startup and held for the postmaster's
      # lifetime — the one knob here that truly locks RAM away — so kept modest
      # to leave the bulk free for ad-hoc data analysis. effective_cache_size is
      # only a planner hint (allocates nothing) and reflects the OS page cache.
      settings = {
        shared_buffers = "2GB";
        effective_cache_size = "24GB";
        work_mem = "64MB";
        maintenance_work_mem = "512MB";
        max_parallel_workers_per_gather = 4;
      };
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

  };
}
