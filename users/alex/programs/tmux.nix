{ pkgs, ... }:
{
  enable = true;
  shell = "${pkgs.zsh}/bin/zsh";
  terminal = "screen-256color";
  mouse = true;
  keyMode = "emacs";
  baseIndex = 1;
  escapeTime = 0;
  historyLimit = 1000000;
}
