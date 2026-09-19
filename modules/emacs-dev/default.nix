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

        # Development tools. Deliberately absent: which-key and project
        # (built into Emacs 30 — a MELPA copy here would shadow the newer
        # bundled version) and the treesit grammars (emacs-core owns them via
        # treesit-extra-load-path; a second declaration here could silently
        # diverge into a different store closure).
        magit
        treesit-auto
        multiple-cursors
        rainbow-delimiters
        rainbow-mode

      ] ++ config.my.emacs-dev.extraPackages;
    };

    # Development configuration that will be loaded by init.el
    home.file.".emacs.d/config/30-devel.el".source = ./config/30-devel.el;
    home.file.".emacs.d/config/31-prog-mode.el".source = ./config/31-prog-mode.el;
  };
}
