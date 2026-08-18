{ lib, pkgs, ... }:

{
  # Allow installation of not-free software.
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;

    # Build off /tmp. /tmp is an 8 GB tmpfs that also carries live working data
    # (analysis scratch, venvs), so builds only ever see ~6 GB of it — and a
    # rust dep graph blows past that, since tmpfs pages are unreclaimable and
    # can only spill to a swap cushion that already runs near full. / has ~290 GB
    # spare, so point builds at disk and let the 8 GB cap keep guarding the rest.
    #
    # Must be /nix/var/nix/builds, not somewhere under /var/tmp: nix walks every
    # ancestor of build-dir and refuses to build if any of them is world-writable
    # or a symlink ("Path \"/var/tmp\" is world-writable ... not allowed for
    # security"), which /var/tmp (1777) always is. Nix's own state dir is
    # root-owned 0755 the whole way down and sits on / like the store, so
    # finished outputs move into the store instead of being copied across
    # filesystems.
    build-dir = "/nix/var/nix/builds";

    # 16 jobs x all-16-cores oversubscribes a box running bitcoind, Jellyfin and
    # Prefect 24/7, and multiplies peak build-scratch by the job count. 4x4
    # saturates the CPU without starving the services. Raise for faster rebuilds.
    max-jobs = 4;
    cores = 4;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Weekly TRIM for the NVMe.
  services.fstrim.enable = true;

  # Memory tuning for a 64 GB host. None of these reserve RAM: swappiness just
  # biases the kernel away from swapping out the working set (keeping analysis
  # data resident), and vfs_cache_pressure keeps the dentry/inode cache around
  # for the many-file workloads (NextCloud, Samba, Jellyfin, Bitcoin blocks).
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };

  # RAM-backed /tmp — faster and saves NVMe wear. tmpfs is demand-paged and
  # swappable, so it costs nothing until used; the cap keeps a temp-file-heavy
  # analysis job from silently eating into RAM (point big jobs at a disk TMPDIR).
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "8G";

  # This box does Bitcoin validation and Jellyfin transcoding 24/7; bias the
  # AMD cores toward responsiveness rather than the default powersave.
  #
  # The kernel param is what makes the governor below actually take. amd-pstate
  # comes up in *active* mode (the amd-pstate-epp driver), where the hardware
  # chooses the frequency and the only governors that exist are `performance` and
  # `powersave` — so `schedutil` was silently unavailable and the cores sat on
  # powersave, which is precisely what the line below claims to avoid. Found by
  # reading the machine rather than the config: scaling_governor said `powersave`
  # and scaling_available_governors listed only those two.
  #
  # `guided` over `passive`: both restore the generic governors, but guided still
  # lets the hardware pick a frequency autonomously *within* the bounds schedutil
  # sets, so it keeps the sub-millisecond response that passive hands back to the
  # kernel. `performance` was the other candidate and is rejected on purpose — it
  # pins the ceiling on a machine that idles most of the day.
  #
  # Verify after a REBOOT. A kernel parameter does not take on `nixos-rebuild
  # switch` alone, so both of these still read the old values until then:
  #   cat /sys/devices/system/cpu/amd_pstate/status              # -> guided
  #   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor  # -> schedutil
  boot.kernelParams = [ "amd_pstate=guided" ];
  powerManagement.cpuFreqGovernor = "schedutil";

  # Compressed RAM-backed swap. Costs nothing until used, and gives the kernel
  # a fast cushion to absorb transient memory pressure during heavy analysis —
  # cold pages get compressed in RAM (higher priority than the disk swap) rather
  # than triggering a hard OOM-kill. Not a reservation and never touches the NVMe.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25; # cap on compressible pages held; ~15 GB of a 64 GB host
  };

  # Cap journald growth so a chatty service can't fill /.
  services.journald.extraConfig = ''
    SystemMaxUse=2G
  '';

  # Boot (UEFI)
  boot.loader.timeout = 3;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set your time zone.
  time.timeZone = "Europe/Madrid";

  # Select internationalisation properties.
  i18n.defaultLocale = "es_ES.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_DK.UTF-8"; # optional: ISO-like dates in some tools
  };

  console = {
    font = "Lat2-Terminus16";
    keyMap = lib.mkForce "es";
    useXkbConfig = true; # use xkb.options in tty.
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.zsh.enable = true;

  # mosh (mobile shell): local echo + predictive typing over UDP eliminates the
  # dropped/laggy characters that plain SSH suffers under network jitter. Enabling
  # this installs the server and opens UDP 60000-61000 in the firewall.
  programs.mosh.enable = true;

  # Provide a stub dynamic linker at the FHS path so foreign (non-Nix)
  # dynamically-linked binaries can run — e.g. pip-installed manylinux
  # wheels like numpy that expect libstdc++.so.6 at the system location.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib # libstdc++.so.6, libgcc_s
    zlib # libz.so.1

    # uv provisions its own standalone CPython (python-build-standalone) under
    # ~/.local/share/uv/python — a prebuilt foreign binary. It and the manylinux
    # wheels it installs load these by soname at import time rather than linking
    # them, so nix-ld's aggregate lib dir has to carry them. These are the ones
    # foreign wheels reach for most often; if an import still dies with
    # "libSOMETHING.so.N: cannot open shared object file", add that lib's package
    # here. NOTE: nix-ld exports this via NIX_LD_LIBRARY_PATH through
    # environment.variables, so INTERACTIVE shells (alex) see it but systemd
    # services (eva) do NOT — her uv builds need the path wired into the unit env.
    openssl # libssl.so, libcrypto.so
    libffi # libffi.so (ctypes / _cffi_backend)
    zstd # libzstd.so

    # WeasyPrint (acpuchades-site's CV PDF renderer, run from a uv-managed venv
    # under ~/projects) dlopen()s these by soname at import time rather than
    # linking them, so they have to be findable at runtime — nix-ld's aggregate
    # lib dir is on the loader search path for foreign binaries, and that path
    # serves dlopen too, not just startup linking. pangoft2 ships inside pango.
    glib # libgobject-2.0.so.0
    pango # libpango-1.0.so.0, libpangoft2-1.0.so.0
    harfbuzz # libharfbuzz.so.0, libharfbuzz-subset.so.0
    fontconfig # libfontconfig.so.1 (nix-ld maps getLib over this list)
  ];

  security.sudo.wheelNeedsPassword = true;

  # eva's passwordless sudo grants now live in machines/homeserver/default.nix
  # under my.openclaw.sudoCommands, kept alongside the rest of her config.

  # Enable Mesa userspace drivers (VAAPI) for hardware-accelerated transcoding
  hardware.graphics.enable = true;

}
