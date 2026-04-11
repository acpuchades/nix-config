{ config, lib, pkgs, ... }:

{
  options.my.r-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs.rPackages; [
        devtools
        gitignore
        rix
        tidyverse
      ];
      description = "Paquetes adicionales de R para instalar junto al conjunto base.";
    };
  };

  config = {
    home.packages = with pkgs; [

      (rWrapper.override { packages = config.my.r-dev.extraPackages; })
      (radianWrapper.override { packages = config.my.r-dev.extraPackages; })

      air-formatter
      pandoc
      texliveSmall
    ];
  };
}
