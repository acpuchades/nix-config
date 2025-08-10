{
  self,
  nix-darwin,
  home-manager,
  ...
}:

let
  configuration =
    { pkgs, ... }:
    import ./settings.nix { inherit pkgs; }
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

      fonts.packages = with pkgs; [
        emacs-all-the-icons-fonts
        font-awesome
        nerd-fonts.fira-code
      ];

      environment.systemPackages = import ./packages.nix { inherit pkgs; };
      homebrew = import ./homebrew.nix;
    };

in
nix-darwin.lib.darwinSystem {
  modules = [
    configuration
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      users.users.alex.home = "/Users/alex";
      home-manager.users.alex = import ../../users/alex;
    }
  ];
}
