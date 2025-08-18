{ config, host, lib, pkgs, ... }:

let

  python3-with-packages = pkgs.python3.withPackages (
    ps: with ps; [
      ipykernel
      jupyter
      matplotlib
      numpy
      pandas
      polars
      pyarrow
      scikit-learn
      scipy
      seaborn
      statsmodels
    ]
  );

  r-packages = with pkgs.rPackages; [
    brms
    car
    cardx
    cli
    DBI
    effects
    emmeans
    ggeffects
    ggsurvfit
    ggpubr
    gamm4
    glmmTMB
    gtsummary
    Hmisc
    IRkernel
    janitor
    knitr
    labelled
    languageserver
    lme4
    mgcv
    nls_multstart
    nlme
    psych
    readxl
    renv
    robustlmm
    rmarkdown
    RSQLite
    sjPlot
    tidyverse
    writexl
  ];

  r-with-packages = pkgs.rWrapper.override { packages = r-packages; };
  radian-with-packages = pkgs.radianWrapper.override { packages = r-packages; };
  rstudio-with-packages = pkgs.rstudioWrapper.override { packages = r-packages; };

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

  programs = import ./programs { inherit pkgs; };

  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  sops.age.generateKey = true;

  sops.secrets."github/token" = {
    sopsFile = ./secrets/${host}.yml;
    format = "yaml";
    key = "github/token";
  };

  sops.templates."gh-hosts.yml".content = ''
    github.com:
      user: acpuchades
      git_protocol: https
      oauth_token: ${config.sops.placeholder."github/token"}
  '';

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;
  home.file.".config/gh/hosts.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      config.sops.templates."gh-hosts.yml".path;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };
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

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {
  #  "Xcursor.size" = 16;
  #  "Xft.dpi" = 172;
  # };

  fonts.fontconfig.enable = true;

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [

    # Fonts
    emacs-all-the-icons-fonts
    font-awesome
    nerd-fonts.fira-code

    # System
    bat
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
    awscli2
    docker

    # Nix
    nil
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
    texliveSmall
    r-with-packages
    radian-with-packages
    rstudio-with-packages
  ];

  home.sessionVariables = {
    EDITOR = "vim";
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
