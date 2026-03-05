{ pkgs, ... }:
{
  enable = true;
  shell = "${pkgs.zsh}/bin/zsh";
  terminal = "tmux-256color";
  keyMode = "emacs";
  baseIndex = 1;
  escapeTime = 0;
  historyLimit = 1000000;
}
