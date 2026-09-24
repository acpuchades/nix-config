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

  # "Emacs Client.app": the GUI entry point to that daemon (Spotlight, Home
  # Manager Apps). It opens a frame on the running server (--reuse-frame
  # raises an existing one) instead of paying Emacs.app's cold start. It
  # falls back to the standalone Emacs.app if the daemon is down, e.g. while
  # a rebuild restarts it. LSUIElement keeps this launcher's own Dock icon
  # hidden, so the daemon's Emacs owns the Dock. It is a shell script, not an
  # AppleScript applet, so Finder's "Open With" hands it no files.
  home.packages = lib.optional pkgs.stdenv.isDarwin (
    let emacs = config.programs.emacs.finalPackage; in
    pkgs.runCommand "emacs-client-app" { } ''
      contents="$out/Applications/Emacs Client.app/Contents"
      mkdir -p "$contents/MacOS" "$contents/Resources"
      cp ${emacs}/Applications/Emacs.app/Contents/Resources/Emacs.icns "$contents/Resources/"
      cat > "$contents/Info.plist" <<'EOF'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleName</key><string>Emacs Client</string>
        <key>CFBundleIdentifier</key><string>org.nix-community.home.emacs-client</string>
        <key>CFBundleExecutable</key><string>emacs-client</string>
        <key>CFBundleIconFile</key><string>Emacs</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSUIElement</key><true/>
      </dict>
      </plist>
      EOF
      cat > "$contents/MacOS/emacs-client" <<'EOF'
      #!/bin/sh
      ${emacs}/bin/emacsclient --no-wait --reuse-frame "$@" 2>/dev/null \
        || exec /usr/bin/open -a ${emacs}/Applications/Emacs.app --args "$@"
      EOF
      chmod +x "$contents/MacOS/emacs-client"
    ''
  );
  launchd.agents.emacs-daemon = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${config.programs.emacs.finalPackage}/bin/emacs" "--fg-daemon" ];
      # Home-manager restarts an agent only when its plist bytes change, so a
      # rebuild that touched only ~/.emacs.d left the daemon on the old config.
      # Every file deployed there (across all emacs-* modules and
      # 99-personal.el), collected into one store path, makes any config edit
      # change the plist. This restart drops unsaved buffers in the daemon.
      EnvironmentVariables.EMACS_CONFIG = toString (pkgs.linkFarm "emacs-d-config"
        (lib.mapAttrsToList (_: f: { name = f.target; path = f.source; })
          (lib.filterAttrs (_: f: lib.hasPrefix ".emacs.d/" f.target) config.home.file)));
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "/tmp/emacs-daemon.err";
    };
  };
}
