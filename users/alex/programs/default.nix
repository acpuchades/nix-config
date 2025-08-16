inputs@{ pkgs }:
{
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  emacs = import ./emacs.nix inputs;
  gh = import ./gh.nix inputs;
  git = import ./git.nix inputs;
  starship = import ./starship.nix inputs;
  zed-editor = import ./zed-editor.nix inputs;
  zsh = import ./zsh.nix inputs;
}
