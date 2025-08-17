{ pkgs, ... }:
{
  enable = true;
  extraConfig = ''
    ;; Nix-provided grammars
    (setq treesit-extra-load-path
        '("${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib"))
  '';
  extraPackages =
    epkgs: with epkgs; [
      all-the-icons
      all-the-icons-dired
      auto-dark
      blacken
      cape
      catppuccin-theme
      corfu
      editorconfig
      envrc
      gcmh
      ligature
      magit
      marginalia
      markdown-mode
      multiple-cursors
      nix-ts-mode
      no-littering
      orderless
      org-bullets
      treesit-auto
      treesit-grammars.with-all-grammars
      use-package
      vertico
      vterm
      vterm-toggle
      which-key
    ];
}
