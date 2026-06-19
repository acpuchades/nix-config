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

    # Initialize the mamba shell so `mamba activate` works in interactive shells.
    # nixpkgs wraps the real binary as `.mamba-wrapped`; the generated hook derives
    # its shell-function name from that basename, and the leading dot makes
    # `${name%.*}` strip it to an empty string ("unknown MAMBA_EXE" error). Rewrite
    # the embedded path to the sibling `mamba` wrapper, which runs the same and has a
    # clean basename.
    programs.zsh.initContent = lib.mkAfter ''
      if command -v mamba >/dev/null 2>&1; then
        eval "$(mamba shell hook --shell zsh | sed 's|\.mamba-wrapped|mamba|g')"
      fi
    '';
  };
}
