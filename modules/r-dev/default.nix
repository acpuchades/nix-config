{ config, lib, pkgs, ... }:

{
  options.my.r-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional R packages to install.";
    };
  };

  config = let
    r-pkgs = with pkgs.rPackages; [
      devtools
      renv
      rix
    ] ++ config.my.r-dev.extraPackages;

  in {
    home.packages = with pkgs; [

      (rWrapper.override { packages = r-pkgs; })
      (radianWrapper.override { packages = r-pkgs; })
      air-formatter   # R formatter + language server (`air format`, `air language-server`)
      pandoc          # R Markdown / knitr rendering
      texliveSmall    # PDF output from R Markdown, R CMD check manuals
    ];
  };
}
