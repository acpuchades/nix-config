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
    # rust-analyzer and rustfmt come from modules/rust-dev — the *-dev
    # modules own toolchains, the emacs-* modules own elisp.

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        cargo-mode
      ] ++ config.my.emacs-rust.extraPackages;
    };

    # Configuración de Rust para Emacs
    home.file.".emacs.d/config/70-rust.el".source = ./config/70-rust.el;
  };
}
