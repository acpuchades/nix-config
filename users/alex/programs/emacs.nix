{ pkgs, ... }:
{
  enable = true;
  package = pkgs.emacs-pgtk;
  extraConfig = ''
    ;; Nix-provided grammars
    (setq treesit-extra-load-path
        '("${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib"))
  '';
  extraPackages =
    epkgs: with epkgs; [
      aidermacs
      all-the-icons
      all-the-icons-dired
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
      ess
      ess-smart-equals
      ess-view-data
      gcmh
      ligature
      magit
      marginalia
      markdown-mode
      multiple-cursors
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
      treemacs-all-the-icons
      treemacs-magit
      treesit-auto
      treesit-grammars.with-all-grammars
      use-package
      vertico
      vterm
      vterm-toggle
      which-key
    ];
}
