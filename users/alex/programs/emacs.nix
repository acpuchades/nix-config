{
  enable = true;

  extraPackages =
    epkgs: with epkgs; [
      ligature
      magit
      markdown-mode
      org-bullets
      tree-sitter-langs
      treesit-auto
      use-package
    ];
}
