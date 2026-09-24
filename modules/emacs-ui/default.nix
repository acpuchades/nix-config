{ lib, ... }:

{
  # Configure Emacs with UI packages
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      # UI packages
      auto-dark
      catppuccin-theme
      dashboard
      doom-modeline
      ligature
      nerd-icons
      nerd-icons-dired
      nerd-icons-ibuffer
      treemacs
      treemacs-magit
      treemacs-nerd-icons
    ];
  };

  # UI configuration that will be loaded by init.el
  home.file.".emacs.d/config/20-ui.el".source = ./config/20-ui.el;
}
