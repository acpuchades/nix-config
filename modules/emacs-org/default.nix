{ config, lib, ... }:

{
  options.my.emacs-org = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Org-mode.";
    };
  };

  config = {
    # Configure Emacs with org packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # Org-mode packages
        org-modern
        org-roam
      ] ++ config.my.emacs-org.extraPackages;
    };

    # Org-mode configuration that will be loaded by init.el
    home.file.".emacs.d/config/20-org.el".source = ./config/20-org.el;
  };
}
