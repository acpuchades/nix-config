{
  enable = true;

  extraPackages =
    epkgs: with epkgs; [
      ligature
      magit
      markdown-mode
      tree-sitter-langs
      treesit-auto
      use-package
    ];
}
