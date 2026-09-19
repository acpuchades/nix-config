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
    # The toolchain (gopls, gotools) comes from modules/golang-dev — the
    # *-dev modules own binaries, the emacs-* modules own elisp. The config
    # uses only the built-in go-ts-mode, so no external Emacs packages either.
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: config.my.emacs-golang.extraPackages;
    };

    # Configuración de Go para Emacs
    home.file.".emacs.d/config/75-go.el".source = ./config/75-go.el;
  };
}
