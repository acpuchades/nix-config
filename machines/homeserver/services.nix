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

    # Self-hosted GitHub Actions runner for the acpuchades-site repo, so its
    # workflows build here instead of on GitHub-hosted runners. Runs under a
    # systemd DynamicUser (the module's default) with the usual hardening; the
    # token file is only ever read by the root-run ExecStartPre, so the sops
    # secret stays root-owned. No extraLabels: GitHub already applies
    # `self-hosted`/`Linux`/`X64` as default labels (noDefaultLabels = false).
    #
    # The repo's .github/workflows/deploy.yml is `make build` + an rsync of
    # public/ into $DEPLOY_PATH — which is this host's own web root, so the
    # deploy is a local copy, not an ssh one.
    github-runners.acpuchades-site = {
      enable = true;
      url = "https://github.com/acpuchades/acpuchades-site";
      tokenFile = config.sops.secrets."github-runner/acpuchades-site".path;

      # The module's own PATH is only bash/coreutils/git/tar/gzip/nix (node for
      # JS actions comes bundled with the runner), so everything `make build`
      # shells out to has to be listed here:
      #   * go      — the Blowfish theme is a Hugo Module (go.mod, no _vendor/),
      #               so hugo shells out to `go` to fetch it on a fresh checkout.
      #   * python3 — the CV PDF renderer (WeasyPrint) and the PII guard. Built
      #               with withPackages rather than the repo's uv venv on
      #               purpose: WeasyPrint dlopen()s Pango/HarfBuzz/fontconfig,
      #               and programs.nix-ld cannot help here — it exports
      #               NIX_LD_LIBRARY_PATH through environment.variables, which a
      #               systemd service never sees. Fonts are not needed: the CV
      #               print CSS @font-face's the woff2 files out of the repo.
      #               The workflow passes `make build PY=python3` to override the
      #               Makefile's hardcoded .venv/bin/python (a command-line
      #               assignment beats the `:=` in the file).
      extraPackages = with pkgs; [
        gnumake
        hugo
        go
        rsync
        (python3.withPackages (ps: with ps; [ weasyprint pyyaml pypdf ]))
      ];

      # Take over an existing GitHub-side runner of the same name instead of
      # failing on it. The module purges the state directory and re-registers
      # whenever the registration config changes — that set is {ephemeral,
      # extraLabels, name, noDefaultLabels, runnerGroup, tokenFile, url,
      # workDir}, so e.g. touching extraLabels is enough. The purge destroys the
      # credentials the old registration would have deregistered with, leaving
      # an orphan on GitHub that the next `configure` collides with ("A runner
      # exists with the same name"). Without --replace that is a hard failure
      # and the unit will not start; `replace` is itself outside the hashed set,
      # so setting it does not trigger yet another registration.
      replace = true;

      user = "acpuchades-site";
      group = "acpuchades-site";

      serviceOverrides = {
        # ProtectSystem = "strict" leaves the whole filesystem read-only apart
        # from the unit's own state/runtime/logs dirs, so the deploy step's
        # target has to be punched back through.
        ReadWritePaths = [ "/var/www/acpuchades.com" ];

        # The module defaults to 0066, which would have hugo write public/ as
        # 0600 — and `rsync -a` preserves those bits, so the deployed site would
        # be unreadable by caddy. 0022 gives the usual 0644/0755.
        UMask = "0022";

        # The deploy's `rsync --chmod=Dg+ws` keeps the web root 2775 so alex can
        # still deploy by hand; the module's default (true) makes systemd refuse
        # the setgid half of that with EPERM on every directory, even though the
        # runner OWNS them — the restriction is on the bit, not on ownership, so
        # the deploy step fails wholesale with rsync exit 23. Nothing weaker
        # works: dropping the `s` costs the group inheritance that keeps a
        # hand-made directory writable by the runner, and `--no-perms` leaves
        # new directories 2755 (alex cannot write inside them). Cheap to allow —
        # the unit is an unprivileged user and NoNewPrivileges stays on, so a
        # setgid file it creates confers nothing beyond acpuchades-site.
        RestrictSUIDSGID = false;
      };
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

  # bitcoind's dataDir is on a separate disk and nothing orders the daemon after
  # that mount — systemd only infers mount dependencies from RootDirectory=,
  # WorkingDirectory= and RootImage=, none of which apply here. Starting before
  # the mount lands means bitcoind finds no chainstate at its datadir and begins
  # laying down a fresh one on the parent filesystem, under the mountpoint, where
  # it is both invisible afterwards and a genuine risk of filling the root disk.
  # Read from the option so it follows wherever dataDir is set above.
  systemd.services.bitcoind-main.unitConfig.RequiresMountsFor =
    [ config.services.bitcoind.main.dataDir ];

  # Web root for www.acpuchades.com (my.web-server.virtualHosts). Setgid so the
  # tree the runner rsyncs in keeps the group, and group-writable so alex can
  # still deploy over ssh by hand. Not recursive — this only fixes the top
  # directory; the contents get their ownership from whoever last deployed.
  systemd.tmpfiles.rules = [
    "d /var/www/acpuchades.com 2775 acpuchades-site acpuchades-site -"
  ];
}
