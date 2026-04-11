{ config, lib, pkgs, ... }:

{
  options.my.emacs-core = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for core functionality.";
    };
  };

  config = {
    # Configure Emacs with core packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # Package management
        use-package

        # File organization
        no-littering

        # Performance
        gcmh


        # Snippets
        yasnippet
        yasnippet-snippets

        # Development tools
        which-key
        super-save
        multiple-cursors
        rainbow-delimiters
        rainbow-mode
        editorconfig

        # Shell integration
        eshell-toggle
        exec-path-from-shell

        # Environment
        direnv
        envrc

        # Project management
        project

      ] ++ config.my.emacs-core.extraPackages;
    };

    # Core emacs configuration
    home.file.".emacs.d/early-init.el".source = ./early-init.el;
    home.file.".emacs.d/init.el".source = ./init.el;
    home.file.".emacs.d/share/logo.svg".source = ./share/logo.svg;

    # Deploy config files
    home.file.".emacs.d/config/00-core.el".source = ./config/00-core.el;
    home.file.".emacs.d/config/05-nix-integration.el".text = ''
      ;; Nix-provided coreutils
      (setq insert-directory-program "${pkgs.coreutils}/bin/ls")
      ;; Nix-provided grammars
      (setq treesit-extra-load-path
        '("${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib"))
    '';
    home.file.".emacs.d/config/30-productivity.el".source = ./config/30-productivity.el;
  };
}
