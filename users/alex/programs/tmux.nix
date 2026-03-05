{ pkgs, ... }:
{
  enable = true;
  shell = "${pkgs.zsh}/bin/zsh";
  terminal = "screen-256color";
}
