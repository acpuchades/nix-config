{ lib, ... }:

{
  # Configure Emacs with org packages
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      # Org-mode packages
      org-modern
      org-roam
    ];
  };

  # Org-mode configuration that will be loaded by init.el
  home.file.".emacs.d/config/40-org.el".source = ./config/40-org.el;
}
