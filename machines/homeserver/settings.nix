{ lib, ... }:

{
  # Allow claude-code (unfree) without opting the whole server into unfree.
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

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

  security.sudo.wheelNeedsPassword = true;

  # Enable Mesa userspace drivers (VAAPI) for hardware-accelerated transcoding
  hardware.graphics.enable = true;

}
