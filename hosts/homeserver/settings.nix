{ lib, ... }:

let

  adminEmail = "acaravacapuchades@gmail.com";

in
{
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

  # Boot (UEFI)
  boot.loader.timeout = 3;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Forwarding + NAT (replace external iface as needed)
  boot.kernel.sysctl = {
	"net.ipv4.ip_forward" = 1;
	"net.ipv6.conf.all.forwarding" = 1;
  };

  # Set your time zone.
  time.timeZone = "Europe/Madrid";

  # Select internationalisation properties.
  i18n.defaultLocale = "es_ES.UTF-8";
  i18n.extraLocaleSettings = {
	LC_TIME = "en_US.UTF-8"; # optional: ISO-like dates in some tools
  };

  console = {
	font = "Lat2-Terminus16";
	keyMap = lib.mkForce "es";
	useXkbConfig = true; # use xkb.options in tty.
  };

  # Automatic security updates (reboots allowed)
  system.autoUpgrade = {
	enable = true;
	dates = "daily";
	allowReboot = false;
	randomizedDelaySec = "1h";
  };

  programs.zsh.enable = true;

  security.sudo.wheelNeedsPassword = true;

  # ACME certificates management
  security.acme = {
	acceptTerms = true;
	defaults.email = adminEmail;
	# no dnsProvider -> uses HTTP-01 on port 80
  };
}
