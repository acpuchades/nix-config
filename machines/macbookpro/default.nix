{
  self,
  nix-darwin,
  home-manager,
  sops-nix,
  better-zen,
  emacs-overlay,
  ...
}:

let

  configuration = inputs@{ config, pkgs, ... }: {

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

    modules = import ../common.nix {
      host = "macbookpro";
      homeDirectory = "/Users/alex";
      inherit sops-nix emacs-overlay;
    } ++ [
      ./settings.nix

      configuration
      sops-nix.darwinModules.sops
      home-manager.darwinModules.home-manager
      {
        home-manager.users.alex.imports = [
          (import ./browser.nix { inherit better-zen; })
        ];

        users.users.alex.openssh.authorizedKeys.keys = [
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOsBCI8pMjSqQFPxJsyFWBrKxo2scz9zLhCyJKKiBJZFAAAABHNzaDo= acpuchades-nitrokey-20260225"
        ];
      }
  ];
}
