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
      # Unset, the default is the full X11/Lucid build — on the headless
      # homeserver that pulls the whole graphics closure for an Emacs only
      # ever run as `emacs -nw`/emacsclient. Darwin gets the native NS build.
      package = if pkgs.stdenv.isDarwin then pkgs.emacs30 else pkgs.emacs30-nox;
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

        # Core tools
        super-save
        editorconfig

        # Shell integration
        eshell-toggle
        exec-path-from-shell

        # Environment (envrc only — the `direnv` package is a competing
        # integration that fights envrc over exec-path; see 00-core.el)
        envrc

      ] ++ config.my.emacs-core.extraPackages;
    };

    # Core emacs configuration
    home.file.".emacs.d/early-init.el".source = ./early-init.el;
    home.file.".emacs.d/init.el".source = ./init.el;
    home.file.".emacs.d/share/logo.svg".source = ./share/logo.svg;

    # Deploy config files
    home.file.".emacs.d/config/00-core.el".source = ./config/00-core.el;
    home.file.".emacs.d/config/02-defaults.el".source = ./config/02-defaults.el;
    home.file.".emacs.d/config/01-nix-integration.el".text = ''
      ;; Nix-provided coreutils
      (setq insert-directory-program "${pkgs.coreutils}/bin/ls")
      ;; Nix-provided grammars (add-to-list, not setq, so nothing else that
      ;; touches this variable is silently clobbered)
      (add-to-list 'treesit-extra-load-path
        "${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib")
    '';
    home.file.".emacs.d/config/03-calendar.el".source = ./config/03-calendar.el;

    # A real daemon on Linux (systemd user unit), so `emacsclient -t -a ""`
    # (EDITOR/VISUAL) attaches instantly instead of cold-starting a private
    # daemon per invocation. Darwin has no HM unit for this; there init.el's
    # own server-start covers the interactive session.
    services.emacs.enable = pkgs.stdenv.isLinux;
  };
}
