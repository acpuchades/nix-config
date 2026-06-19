{ config, lib, pkgs, ... }:

{
  options.my.emacs-rust = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Rust development.";
    };
  };

  config = {
    # Herramientas del sistema necesarias para Emacs
    home.packages = with pkgs; [
      rust-analyzer  # Rust LSP server
      rustfmt
    ];

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        cargo-mode
      ] ++ config.my.emacs-rust.extraPackages;
    };

    # Configuración de Rust para Emacs
    home.file.".emacs.d/config/19-rust.el".source = ./config/19-rust.el;
  };
}
