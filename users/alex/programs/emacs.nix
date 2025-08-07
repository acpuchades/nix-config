{
  enable = true;

  extraPackages =
    epkgs: with epkgs; [
      magit
      markdown-mode
      treesit-auto
      use-package
    ];
}
