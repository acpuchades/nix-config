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

    # Necessary for using flakes on this system.
    nix.settings.experimental-features = "nix-command flakes";

    # Binary cache for emacs-overlay / nix-community builds so they download
    # instead of compiling locally. Merges with the rstats cache from r-dev.
    nix.settings.extra-substituters = [ "https://nix-community.cachix.org" ];
    nix.settings.extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Deduplicate identical files in the store to reclaim disk, weekly.
    nix.optimise.automatic = true;
    nix.optimise.interval = { Weekday = 0; Hour = 3; Minute = 30; };

    # Garbage-collect old generations weekly so /nix/store doesn't grow unbounded.
    nix.gc.automatic = true;
    nix.gc.interval = { Weekday = 0; Hour = 3; Minute = 0; };
    nix.gc.options = "--delete-older-than 14d";

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
      ../../modules/r-dev/system.nix

      (import ../../modules/emacs-core/system.nix { inherit emacs-overlay; })

      {
        # WORKAROUND: disable direnv failing test suite on macos
        nixpkgs.overlays = [
          (final: prev: {
            direnv = prev.direnv.overrideAttrs (_: { doCheck = false; });
          })
        ];
      }

      ./settings.nix

      configuration
      sops-nix.darwinModules.sops
      home-manager.darwinModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.alex = {
          imports = [
            ../../users/alex
            (import ./browser.nix { inherit better-zen; })
          ];
        };
        home-manager.extraSpecialArgs = { host = "macbookpro"; };
        home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];

        users.users.alex.home = "/Users/alex";
        users.users.alex.openssh.authorizedKeys.keys = [
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOsBCI8pMjSqQFPxJsyFWBrKxo2scz9zLhCyJKKiBJZFAAAABHNzaDo= acpuchades-nitrokey-20260225"
        ];
      }
  ];
}
