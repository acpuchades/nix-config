{ pkgs }:
{
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  emacs = import ./emacs.nix { inherit pkgs; };
  gh = import ./gh.nix;
  git = import ./git.nix;
  zed-editor = import ./zed-editor.nix;
  zsh = import ./zsh.nix { inherit pkgs; };
}
