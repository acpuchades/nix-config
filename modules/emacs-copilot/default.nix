{ config, lib, ... }:

{
  options.my.emacs-copilot = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for GitHub Copilot.";
    };
  };

  config = {
    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        copilot
      ] ++ config.my.emacs-copilot.extraPackages;
    };

    # Configuración de GitHub Copilot para Emacs
    home.file.".emacs.d/config/26-copilot.el".source = ./config/26-copilot.el;
  };
}
