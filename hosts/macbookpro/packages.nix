{ pkgs, ... }:

let
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
  rstudio-with-packages =
    pkgs.rstudioWrapper.override { packages = r-packages; };

  python3-with-packages = pkgs.python3.withPackages (ps:
    with ps; [
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
    ]);

in with pkgs; [

  # System
  bartender
  bat
  delta
  direnv
  emacs
  eza
  fastfetch
  fd
  raycast
  ripgrep
  vim
  wget
  wireshark

  # Creative
  blender

  # Internet
  google-chrome
  notion-app
  telegram-desktop

  # IA
  chatgpt
  ollama

  # Security
  gnupg

  # Development
  awscli2
  docker
  dotnet-sdk
  git
  pyenv
  utm
  uv
  virtualenv
  zed-editor

  # Data science
  pandoc
  texliveSmall
  r-with-packages
  radian-with-packages
  rstudio-with-packages
  python3-with-packages
]
