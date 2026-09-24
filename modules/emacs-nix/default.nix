{ lib, ... }:

{
  # The `nil` LSP binary comes from modules/nix-dev — the *-dev modules own
  # toolchains, the emacs-* modules own elisp.

  # Paquetes de Emacs
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      nix-ts-mode
    ];
  };

  # Configuración de Nix para Emacs
  home.file.".emacs.d/config/65-nix.el".source = ./config/65-nix.el;
}
