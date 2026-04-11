{ config, lib, pkgs, ... }:

{
  options.my.python-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = ps: [];
      description = "Additional Python packages to install alongside the base set.";
    };
  };

  config = {
    home.packages = with pkgs; [
      # Python interpreters and package managers
      (python3.withPackages (ps: with ps; [
        # Data science and analysis
        datasets
        numpy
        pandas
        polars
        pyarrow
        scipy
        scikit-learn
        statsmodels

        # Visualization
        matplotlib
        seaborn

        # Jupyter ecosystem
        ipykernel
        ipywidgets
        jupyter
        jupyterlab-widgets

        # Machine learning
        tensorflow
      ] ++ config.my.python-dev.extraPackages ps))
      
      pyenv
      poetry
      uv
      virtualenv

      # Development tools
      black
      pyright
      ruff
    ];

    home.file.".condarc".text = ''
      channels:
        - bioconda
        - conda-forge
        - defaults
      changeps1: false
      channel_priority: strict
      auto_activate_base: false
    '';
  };
}
