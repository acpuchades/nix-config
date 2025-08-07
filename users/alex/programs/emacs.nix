{
  enable = true;

  extraPackages =
    epkgs: with epkgs; [
      ligature
      magit
      markdown-mode
      treesit-auto
      use-package
    ];
}
