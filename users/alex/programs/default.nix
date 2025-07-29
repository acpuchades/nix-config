{ pkgs, ... }:

{
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  git = import ./git.nix;
  zed-editor = import ./zed-editor.nix { inherit pkgs; };
  zsh = import ./zsh.nix;
}
