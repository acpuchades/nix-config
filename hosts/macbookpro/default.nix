{
  self,
  nix-darwin,
  home-manager,
  sops-nix,
  ...
}:

let
  configuration =
	inputs@{ config, pkgs, ... }:
	import ./settings.nix inputs
	// {

	  # Necessary for using flakes on this system.
	  nix.settings.experimental-features = "nix-command flakes";

	  # Set Git commit hash for darwin-version.
	  system.configurationRevision = self.rev or self.dirtyRev or null;

	  # Used for backwards compatibility, please read the changelog before changing.
	  # $ darwin-rebuild changelog
	  system.stateVersion = 5;

	  # Set the primary user for the system.
	  system.primaryUser = "alex";

	  sops.defaultSopsFile = ./secrets/default.yml;
	  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
	  sops.age.generateKey = true;

	  sops.secrets."alex/github-token" = {
		sopsFile = ../../users/alex/secrets/macbookpro.yml;
		format = "yaml";
		key = "github-token";
	  };

	  sops.templates."alex/gh-hosts.yml".content = ''
		github.com:
		  user: alex
		  git_protocol: https
		  oauth_token: ${config.sops.placeholder."alex/github-token"}
	  '';

	  environment.systemPackages = import ./packages.nix inputs;
	  homebrew = import ./homebrew.nix inputs;
	};

in
nix-darwin.lib.darwinSystem {
  modules = [
	configuration
	sops-nix.darwinModules.sops
	home-manager.darwinModules.home-manager
	{
	  home-manager.useGlobalPkgs = true;
	  home-manager.useUserPackages = true;
	  home-manager.users.alex = import ../../users/alex;

	  users.users.alex.home = "/Users/alex";
	}
  ];
}
