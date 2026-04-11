{ config, lib, ... }:

{
  options.my.emacs-ui = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for user interface.";
    };
  };

  config = {
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
      ] ++ config.my.emacs-ui.extraPackages;
    };

    # UI configuration that will be loaded by init.el
    home.file.".emacs.d/config/10-ui.el".source = ./config/10-ui.el;
  };
}
