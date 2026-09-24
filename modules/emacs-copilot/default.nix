{ lib, ... }:

{
  # Paquetes de Emacs
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      copilot
    ];
  };

  # Configuración de GitHub Copilot para Emacs
  home.file.".emacs.d/config/50-copilot.el".source = ./config/50-copilot.el;
}
