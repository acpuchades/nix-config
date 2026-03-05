{ pkgs, ... }:
{
  enable = true;
  shell = "${pkgs.zsh}/bin/zsh";
  terminal = "tmux-256color";
  mouse = true;
  keyMode = "emacs";
  baseIndex = 1;
  escapeTime = 0;
  historyLimit = 1000000;
  extraConfig = ''
    set -as terminal-overrides ',*:XT'
  '';
}
