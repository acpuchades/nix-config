{ pkgs, ... }:
{
  enable = true;
  shell = "${pkgs.zsh}/bin/zsh";
  terminal = "tmux-256color";
  keyMode = "emacs";
  baseIndex = 1;
  escapeTime = 0;
  historyLimit = 1000000;
  mouse = true;
  plugins = with pkgs.tmuxPlugins; [
    sensible
    vim-tmux-navigator
    {
      plugin = resurrect;
      extraConfig = ''
        set -g @resurrect-capture-pane-contents 'on'
      '';
    }
    {
      plugin = continuum;
      extraConfig = ''
        set -g @continuum-restore 'on'
        set -g @continuum-save-interval '15'
      '';
    }
  ];
}
