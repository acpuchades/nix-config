{
  enable = true;
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
