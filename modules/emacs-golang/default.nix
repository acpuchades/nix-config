{ config, lib, pkgs, ... }:

{
  options.my.emacs-golang = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Go development.";
    };
  };

  config = {
    # Herramientas del sistema necesarias para Emacs
    home.packages = with pkgs; [
      gopls     # Go LSP server
      gotools   # goimports
    ];

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        go-mode
      ] ++ config.my.emacs-golang.extraPackages;
    };

    # Configuración de Go para Emacs
    home.file.".emacs.d/config/21-go.el".source = ./config/21-golang.el;
  };
}
