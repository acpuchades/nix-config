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
        # Don't snapshot/restore pane scrollback, so `clear` stays cleared
        # across restores. Live scrollback is still kept via historyLimit.
        set -g @resurrect-capture-pane-contents 'off'
      '';
    }
    {
      plugin = continuum;
      extraConfig = ''
        set -g @continuum-restore 'on'
        # Save often so an exited tab is dropped from the snapshot quickly
        # and won't be resurrected on the next restore.
        set -g @continuum-save-interval '1'
      '';
    }
  ];
}
