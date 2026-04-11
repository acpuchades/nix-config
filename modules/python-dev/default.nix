{ config, lib, pkgs, ... }:

{
  options.my.python-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = ps: [];
      description = "Additional Python packages to install.";
    };
  };

  config = {
    home.packages = with pkgs; [
      # Python interpreters and package managers
      (python3.withPackages config.my.python-dev.extraPackages)

      uv
      black
      pyright
      ruff
    ];

    home.file.".condarc".text = ''
      channels:
        - conda-forge
        - defaults
      changeps1: false
      channel_priority: strict
      auto_activate_base: false
    '';
  };
}
