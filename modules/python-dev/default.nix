{ config, lib, pkgs, ... }:

{
  options.my.python-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = ps: [];
      description = "Additional Python packages to install.";
    };
  };

  config = let

    python-pkgs = (ps: with ps; [
      ipykernel
      ipywidgets
      jupyter
      jupyterlab-widgets
      debugpy
    ] ++ (config.my.python-dev.extraPackages ps));

  in {

    home.packages = with pkgs; [
      (python3.withPackages python-pkgs)
      mamba-cpp
      pyright
      ruff
      uv
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
