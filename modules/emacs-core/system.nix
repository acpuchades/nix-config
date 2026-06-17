# System-level companion to the emacs-core home-manager module, imported by each
# host (cf. r-dev/system.nix). Lives at the system layer because it sets
# `nixpkgs.overlays`, which home-manager refuses under `useGlobalPkgs`.
#
# nixpkgs only snapshots its Emacs (MELPA/ELPA) package set once per release and
# then freezes it, which routinely ships packages broken against the bundled
# Emacs. This overlay swaps in nix-community's daily-regenerated package set that
# tracks the real upstream releases, so a breakage is fixed by rolling the input
# forward (`nix flake update emacs-overlay`) rather than pinning per-package
# commit hashes. Both hosts use home-manager.useGlobalPkgs, so it reaches the
# home-manager Emacs too.
{ emacs-overlay }:
{
  nixpkgs.overlays = [ emacs-overlay.overlays.default ];
}
