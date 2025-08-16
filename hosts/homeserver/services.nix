{ ... }:
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

  # Avahi/mDNS (.local)
  avahi = {
	enable = true;
	nssmdns4 = true;
	publish.enable = true;
	publish.userServices = true;
  };

  # DNSCrypt
  dnscrypt-proxy2 = {
	enable = true;
	settings = {
	  server_names = [
		"cloudflare"
		"quad9-dnscrypt-ip4-filter-pri"
	  ];
	  require_dnssec = true;
	  listen_addresses = [
		"127.0.0.1:53"
		"[::1]:53"
	  ];
	};
  };

  # Use dnscrypt-proxy instead of systemd-resolved
  resolved.enable = false;

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
