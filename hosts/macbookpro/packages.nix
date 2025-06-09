{ pkgs, ... }:

let
	r-packages = with pkgs.rPackages; [
		car
		cli
		DBI
		effects
		emmeans
		ggeffects
		ggpubr
		janitor
		knitr
		languageserver
		mgcv
		nls_multstart
		nlme
		psych
		readxl
		renv
		rmarkdown
		RSQLite
		tidyverse
		writexl
	];

	r-with-packages = pkgs.rWrapper.override { packages = r-packages; };
	radian-with-packages = pkgs.radianWrapper.override { packages = r-packages; };
	rstudio-with-packages = pkgs.rstudioWrapper.override { packages = r-packages; };

	python3-with-packages = pkgs.python3.withPackages (ps: with ps; [
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
	bat
	delta
	direnv
	emacs
	eza
	fastfetch
	fd
	ripgrep
	vim
	wget

	# Internet
	firefox
	google-chrome
	telegram-desktop

	# IA
	chatgpt
	ollama

	# Security
	gnupg

	# Fonts
	font-awesome
	nerd-fonts.fira-code

	# Development
	alejandra
	docker
	dotnet-sdk
	git
	nil
	utm
	uv
	virtualenv
	zed-editor

	# Data science
	pandoc
	texliveFull
	r-with-packages
	radian-with-packages
	rstudio-with-packages
	python3-with-packages
]
