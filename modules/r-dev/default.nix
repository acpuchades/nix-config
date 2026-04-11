{ config, lib, pkgs, ... }:

{
  options.my.r-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Paquetes adicionales de R para instalar junto al conjunto base.";
    };
  };

  config = {
    home.packages = with pkgs; [
      # R con paquetes base
      (rWrapper.override { 
        packages = with rPackages; [
          devtools
          gitignore
          rix
        ] ++ config.my.r-dev.extraPackages;
      })
      
      # Radian con los mismos paquetes
      (radianWrapper.override { 
        packages = with rPackages; [
          devtools
          gitignore
          rix
        ] ++ config.my.r-dev.extraPackages;
      })
      
      # Herramientas relacionadas con R
      air-formatter
      pandoc
      texliveSmall
    ];

    home.file.".Rprofile".source = ./Rprofile;
  };
}
