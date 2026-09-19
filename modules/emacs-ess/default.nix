{ config, lib, pkgs, ... }:

{
  options.my.emacs-ess = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for ESS/R development.";
    };
  };

  config = {
    # System packages needed for ESS. R itself (rWrapper + packages) comes
    # from modules/r-dev — this module only adds what ESS needs on top.
    home.packages = with pkgs; [
      air-formatter    # LSP formatter for R
      pandoc          # For R Markdown
      texliveSmall    # For PDF generation from R Markdown
    ];

    # Configure Emacs with ESS packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # ESS packages
        ess
        ess-smart-equals
        ess-view-data
        
        # R-Markdown and Quarto support (markdown-mode declared explicitly:
        # 80-ess.el hands plain .md to it, keeping polymode to .Rmd only)
        markdown-mode
        polymode
        poly-R
        poly-markdown
        quarto-mode
      ] ++ config.my.emacs-ess.extraPackages;
    };

    # ESS configuration that will be loaded by init.el
    home.file.".emacs.d/config/80-ess.el".source = ./config/80-ess.el;

    # R snippets for yasnippet
    home.file.".emacs.d/snippets/ess-r-mode/ggcox".source = ./snippets/ggcox;
    home.file.".emacs.d/snippets/ess-r-mode/ggkm".source = ./snippets/ggkm;
    home.file.".emacs.d/snippets/ess-r-mode/ggpie".source = ./snippets/ggpie;
    home.file.".emacs.d/snippets/ess-r-mode/gtreg".source = ./snippets/gtreg;
    home.file.".emacs.d/snippets/ess-r-mode/gtsum".source = ./snippets/gtsum;
    home.file.".emacs.d/snippets/ess-r-mode/rix".source = ./snippets/rix;
  };
}
