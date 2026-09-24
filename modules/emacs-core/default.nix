{ config, lib, pkgs, ... }:

{
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

      # Shell integration
      eshell-toggle
      exec-path-from-shell

      # Environment (envrc only — the `direnv` package is a competing
      # integration that fights envrc over exec-path; see 00-core.el)
      envrc

    ];
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

  # A real daemon on both hosts, so `emacsclient -t` (EDITOR/VISUAL) attaches
  # instantly instead of paying a full cold start on the first `git commit`.
  # Linux: home-manager's systemd user unit. Darwin has no HM unit, so a
  # launchd agent; its bare launchd PATH is why 00-core.el also runs
  # exec-path-from-shell under (daemonp). A GUI Emacs started later sees this
  # server running and skips its own server-start (02-defaults.el).
  services.emacs.enable = pkgs.stdenv.isLinux;
  launchd.agents.emacs-daemon = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${config.programs.emacs.finalPackage}/bin/emacs" "--fg-daemon" ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "/tmp/emacs-daemon.err";
    };
  };
}
