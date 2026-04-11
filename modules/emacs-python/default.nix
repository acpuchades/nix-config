{ config, lib, pkgs, ... }:

{
  options.my.emacs-python = {
    enable = lib.mkEnableOption "Emacs Python development environment";
    
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Python development.";
    };

    blackenLineLength = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Line length for blacken formatter.";
    };
  };

  config = lib.mkIf config.my.emacs-python.enable {
    # Herramientas del sistema necesarias para Emacs
    home.packages = with pkgs; [
      black
      pyright
    ];

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        blacken
      ] ++ config.my.emacs-python.extraPackages;
    };

    # Configuración de Python para Emacs
    home.file.".emacs.d/config/17-python.el".source = ./config/17-python.el;
  };
}
