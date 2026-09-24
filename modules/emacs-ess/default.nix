{ lib, ... }:

{
  # R, the air language server and the R Markdown toolchain (pandoc,
  # texliveSmall) come from modules/r-dev — the *-dev modules own
  # toolchains, the emacs-* modules own elisp.

  # Configure Emacs with ESS packages
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      # ESS packages
      ess
      ess-smart-equals
      ess-view-data

      # R-Markdown and Quarto support (plain .md is emacs-dev's markdown-mode;
      # polymode only claims .Rmd/.qmd)
      polymode
      poly-R
      poly-markdown
      quarto-mode
    ];
  };

  # ESS configuration that will be loaded by init.el
  home.file.".emacs.d/config/80-ess.el".source = ./config/80-ess.el;

  # R snippets for yasnippet
  home.file.".emacs.d/snippets/ess-r-mode" = {
    source = ./snippets;
    recursive = true;
  };
}
