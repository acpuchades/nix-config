{
  self,
  nix-darwin,
  home-manager,
  sops-nix,
  ...
}:

let

  configuration = inputs@{ config, pkgs, ... }:

    import ./settings.nix inputs // {

    # Necessary for using flakes on this system.
    nix.settings.experimental-features = "nix-command flakes";

    # Set Git commit hash for darwin-version.
    system.configurationRevision = self.rev or self.dirtyRev or null;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    system.stateVersion = 5;

    # Set the primary user for the system.
    system.primaryUser = "alex";

    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    sops.defaultSopsFile = ./secrets/default.yml;
    sops.defaultSopsFormat = "yaml";

    environment.systemPackages = import ./packages.nix inputs;
    environment.variables = {
      HOMEBREW_AUTO_UPDATE_SECS = "86400";
      HOMEBREW_NO_ENV_HINTS = "1";
    };

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
      home-manager.extraSpecialArgs = { host = "macbookpro"; };
      home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];

      users.users.alex.home = "/Users/alex";
    }
  ];
}
