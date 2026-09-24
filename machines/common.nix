# Wiring shared by both machines: the cross-platform system fragments
# (modules/*/system.nix) and the home-manager glue for user alex. Factored out
# because the two copies had already drifted once — the nix-community cachix
# existed only on the MacBook, so the homeserver built emacs-overlay packages
# from source — and a drift here fails silently (e.g. a host missing
# `sharedModules` breaks user-level sops with an unrelated-looking error).
#
# Returns a LIST of modules to splice into darwinSystem/nixosSystem, curried
# over what it needs: an argument used in `imports` cannot come from
# `_module.args` (same pattern as machines/homeserver/fugazi.nix). Mostly flake
# inputs, plus `pkgsUnstable` — each machine instantiates nixpkgs-unstable for
# its own system and hands the set over, so a host that already has one is not
# made to evaluate a second.
#
# Platform-specific things stay in each machine: the sops and home-manager
# platform modules (darwinModules vs nixosModules), packages, settings.
{ host, homeDirectory, sops-nix, emacs-overlay, pkgsUnstable }:

[
  ../modules/r-dev/system.nix
  ../modules/prefect-server/system.nix
  (import ../modules/emacs-core/system.nix { inherit emacs-overlay; })
  (import ../modules/claude-code/system.nix { inherit pkgsUnstable; })

  {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.alex.imports = [ ../users/alex ];
    home-manager.extraSpecialArgs = { inherit host; };
    home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];

    users.users.alex.home = homeDirectory;
  }
]
