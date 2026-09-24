{ lib, ... }:

{
  # rust-analyzer and rustfmt come from modules/rust-dev — the *-dev
  # modules own toolchains, the emacs-* modules own elisp.

  # Paquetes de Emacs
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      cargo-mode
    ];
  };

  # Configuración de Rust para Emacs
  home.file.".emacs.d/config/70-rust.el".source = ./config/70-rust.el;
}
