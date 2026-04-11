{ config, lib, ... }:

{
  options.my.emacs-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for development.";
    };
  };

  config = {
    # Configure Emacs with development packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [

        # Development tools
        aidermacs
        magit
        treesit-auto
        treesit-grammars.with-all-grammars
        which-key
        multiple-cursors
        rainbow-delimiters
        rainbow-mode
        project

      ] ++ config.my.emacs-dev.extraPackages;
    };

    # Development configuration that will be loaded by init.el
    home.file.".emacs.d/config/15-devel.el".source = ./config/15-devel.el;
    home.file.".emacs.d/config/16-prog-mode.el".source = ./config/16-prog-mode.el;
  };
}
