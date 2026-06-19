inputs@{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/r-dev
    ../../modules/python-dev
    ../../modules/rust-dev
    ../../modules/golang-dev
    ../../modules/nix-dev

    ../../modules/emacs-core
    ../../modules/emacs-completion
    ../../modules/emacs-ui
    ../../modules/emacs-dev
    ../../modules/emacs-org
    ../../modules/emacs-ess
    ../../modules/emacs-python
    ../../modules/emacs-nix
    ../../modules/emacs-rust
    ../../modules/emacs-golang
    ../../modules/emacs-copilot
  ];

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.11";

  programs = import ./programs inputs;
  services = import ./services.nix inputs;
  sops = import ./sops.nix inputs;
  launchd = lib.mkIf pkgs.stdenv.isDarwin (import ./launchd.nix inputs);

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  home.file.".emacs.d/config/99-personal.el".source = ./files/emacs.d/config/99-personal.el;

  home.file.".config/starship.toml" = {
    source = ./files/starship.toml;
  };

  home.activation.writeGhHosts = lib.hm.dag.entryAfter [ "sops-nix" ] ''
    set -euo pipefail

    mkdir -p "$HOME/.config/gh"
    install -C -m 600 \
      "${config.sops.templates."gh/hosts.yml".path}" \
      "$HOME/.config/gh/hosts.yml"
  '';

  home.activation.writePrefectProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail

      mkdir -p "$HOME/.prefect"
      install -C -m 600 \
        "${config.sops.templates."prefect/profiles.toml".path}" \
        "$HOME/.prefect/profiles.toml"
  '';

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {
  #  "Xcursor.size" = 16;
  #  "Xft.dpi" = 172;
  # };

  fonts.fontconfig.enable = true;

  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [

    # Fonts
    font-awesome
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
    nerd-fonts.ubuntu
    nerd-fonts.ubuntu-mono
    nerd-fonts.ubuntu-sans
    noto-fonts
    noto-fonts-color-emoji
    unifont

    # System
    apg
    coreutils
    direnv
    delta
    duckdb
    fd
    fastfetch
    jq
    lnav
    ripgrep
    tree
    zstd

    # Network
    curl
    nmap
    netcat
    openssh
    samba
    wget

    # Security
    age
    libfido2
    mkpasswd
    pynitrokey

    # Dev
    cffconvert
    docker
    git-crypt
    ntfy
    prefect
  ];

  home.sessionVariables = {
    EDITOR = "emacsclient -a ''";
    PAGER = "bat --paging=always";
    VISUAL = "emacsclient -a ''";
    LANG = "es_ES.UTF-8";
    LC_ALL = "es_ES.UTF-8";
    LC_TIME = "en_DK.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
  };

  home.shellAliases = {
    l = "ls";
  };

  my.r-dev.extraPackages = with pkgs.rPackages; [
    gitignore
    tidyverse
  ];

  my.python-dev.extraPackages = ps: with ps; [
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

    # Machine learning
    tensorflow
  ];
}
