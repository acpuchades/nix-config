{ pkgs, ... }:
{
  enable = true;
  package = pkgs.emacs-pgtk;
  extraConfig = ''
    ;; Nix-provided coreutils
    (setq insert-directory-program "${pkgs.coreutils}/bin/ls")

    ;; Nix-provided grammars
    (setq treesit-extra-load-path
        '("${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib"))
  '';
  extraPackages =
    epkgs: with epkgs; [
      aidermacs
      auto-dark
      blacken
      cape
      catppuccin-theme
      consult
      corfu
      dashboard
      doom-modeline
      editorconfig
      embark
      embark-consult
      envrc
      eshell-toggle
      ess
      ess-smart-equals
      ess-view-data
      gcmh
      ligature
      magit
      marginalia
      markdown-mode
      multiple-cursors
      nerd-icons
      nerd-icons-corfu
      nerd-icons-dired
      nerd-icons-ibuffer
      nix-ts-mode
      no-littering
      orderless
      org-modern
      org-roam
      polymode
      poly-markdown
      poly-R
      quarto-mode
      rainbow-mode
      super-save
      treemacs
      treemacs-nerd-icons
      treemacs-magit
      treesit-auto
      treesit-grammars.with-all-grammars
      use-package
      vertico
      which-key
      yasnippet
      yasnippet-snippets
    ];
}
