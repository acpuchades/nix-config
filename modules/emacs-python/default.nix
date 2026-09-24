{ config, lib, pkgs, ... }:

{
  options.my.emacs-python = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Python development.";
    };
  };

  # Like the other emacs-* modules, gated by presence in `imports`, not by an
  # option. (An earlier `enable` gate here was never set anywhere, so this
  # module silently produced nothing on both hosts.)
  config = {
    # blacken shells out to black; black and pyright come from
    # modules/python-dev (the *-dev modules own toolchains, the emacs-*
    # modules own elisp).

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        blacken
      ] ++ config.my.emacs-python.extraPackages;
    };

    # Configuración de Python para Emacs
    home.file.".emacs.d/config/60-python.el".source = ./config/60-python.el;
  };
}
