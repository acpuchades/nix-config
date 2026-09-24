{
  self,
  nix-darwin,
  nixpkgs-unstable,
  home-manager,
  sops-nix,
  better-zen,
  emacs-overlay,
  ...
}:

let

  # nixpkgs-unstable, for the packages this machine deliberately runs ahead of
  # nixpkgs-26.05. One consumer today — claude-code, via
  # ../../modules/claude-code/system.nix, which both machines import and which
  # takes this set rather than importing unstable itself (the homeserver has one
  # of these for openclaw and immich, and the module reusing it saves that host a
  # second nixpkgs evaluation).
  #
  # claude-code is unfree, and this instance does NOT inherit the
  # `nixpkgs.config.allowUnfree` in ./settings.nix: that option configures the
  # module system's own pkgs, and this is a separate evaluation. The permit is a
  # predicate on the package NAME rather than a blanket flag, so it stays scoped
  # to the one package taken from here. `lib` comes from the unstable input
  # because the plain `nixpkgs` one is not an argument of this file.
  pkgsUnstable = import nixpkgs-unstable {
    system = "aarch64-darwin";
    config.allowUnfreePredicate = p: nixpkgs-unstable.lib.getName p == "claude-code";
  };

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
      inherit sops-nix emacs-overlay pkgsUnstable;
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
