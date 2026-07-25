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
    zlib
  ];

  security.sudo.wheelNeedsPassword = true;

  # Enable Mesa userspace drivers (VAAPI) for hardware-accelerated transcoding
  hardware.graphics.enable = true;

}
