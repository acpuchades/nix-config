inputs@{ config, host, lib, pkgs, ... }:

let

  python3-with-packages = pkgs.python3.withPackages (
    ps: with ps; [
      datasets
      ipykernel
      ipywidgets
      jupyter
      jupyterlab-widgets
      matplotlib
      numpy
      pandas
      polars
      pyarrow
      scikit-learn
      scipy
      seaborn
      statsmodels
      tensorflow
    ]
  );

  r-packages = with pkgs.rPackages; [
    car
    cardx
    DBI
    effects
    emmeans
    ggeffects
    ggsurvfit
    gtsummary
    Hmisc
    IRkernel
    janitor
    knitr
    languageserver
    lme4
    MatchIt
    nls_multstart
    nlme
    psych
    readxl
    rix
    rmarkdown
    RSQLite
    sjPlot
    tidyverse
    writexl
  ];

  r-with-packages = pkgs.rWrapper.override { packages = r-packages; };
  radian-with-packages = pkgs.radianWrapper.override { packages = r-packages; };

in
{
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

  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  sops.age.generateKey = true;
  sops.defaultSopsFile = ./secrets/default.yml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets."anthropic/token" = {
    sopsFile = ./secrets/${host}.yml;
    key = "anthropic/token";
  };

  sops.secrets."github/token" = {
    sopsFile = ./secrets/${host}.yml;
    key = "github/token";
  };

  sops.secrets."prefect/user" = {
    sopsFile = ./secrets/default.yml;
    key = "prefect/user";
  };

  sops.secrets."prefect/password" = {
    sopsFile = ./secrets/default.yml;
    key = "prefect/password";
  };

  sops.templates."gh/hosts.yml".content = ''
  github.com:
    user: acpuchades
    git_protocol: https
    oauth_token: ${config.sops.placeholder."github/token"}
  '';

  sops.templates."prefect/profiles.toml".content = ''
  active = "homeserver"

  [profiles.local]
  PREFECT_API_URL = "http://127.0.0.1:4200/api"

  [profiles.homeserver]
  PREFECT_API_URL = "https://prefect.acpuchades.com/api"
  PREFECT_API_AUTH_STRING = "${config.sops.placeholder."prefect/user"}:${config.sops.placeholder."prefect/password"}"
  '';

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;
  home.file.".emacs.d/share/logo.svg".source = ./files/emacs.d/logo.svg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  home.file.".condarc".text = ''
    channels:
      - bioconda
      - conda-forge
      - defaults
    changeps1: false
    channel_priority: strict
    auto_activate_base: false
  '';

  home.file.".emacs.d" = {
    source = ./files/emacs.d;
    recursive = true;
  };

  home.file.".config/starship.toml" = {
    source = ./files/starship.toml;
  };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  home.activation.linkSecrets = lib.hm.dag.entryAfter [ "sops-nix" "writeBoundary" ] ''
    mkdir -p "$HOME/.config/gh" "$HOME/.prefect"
    ln -sf ${config.sops.templates."gh/hosts.yml".path} "$HOME/.config/gh/hosts.yml"
    ln -sf ${config.sops.templates."prefect/profiles.toml".path} "$HOME/.prefect/profiles.toml"
  '';

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {
  #  "Xcursor.size" = 16;
  #  "Xft.dpi" = 172;
  # };

  fonts.fontconfig.enable = true;

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
    noto-fonts-extra
    noto-fonts-emoji
    unifont

    # System
    apg
    bat
    coreutils
    direnv
    delta
    eza
    fd
    fzf
    fastfetch
    jq
    ripgrep
    vim

    # Network
    curl
    nmap
    netcat
    samba
    wget

    # Encryption
    age
    gnupg
    mkpasswd

    # Dev
    aider-chat
    docker
    mamba-cpp
    prefect

    # Nix
    nil
    nix-direnv
    nixd
    nixfmt-rfc-style
    sops
    ssh-to-age

    # Python
    black
    pyright
    python3-with-packages
    pyenv
    poetry
    ruff
    uv
    virtualenv

    # R
    pandoc
    positron-bin
    r-with-packages
    radian-with-packages
    texliveSmall
  ];

  home.sessionVariables = {
    EDITOR = "emacsclient -a ''";
    VISUAL = "emacsclient -a ''";
    LANG = "es_ES.UTF-8";
    LC_ALL = "es_ES.UTF-8";
    LC_TIME = "en_DK.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    PAGER = "bat --paging=always";
  };

  home.shellAliases = {
    l = "ls";
    la = "ls -A";
    ll = "ls -lh";
    lla = "la -lhA";
  };
}
