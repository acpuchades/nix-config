{ pkgs, ... }:

let
	r-packages = with pkgs.rPackages; [
		cli
		DBI
		httpgd
		janitor
		knitr
		languageserver
		nls_multstart
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
		scikit-learn
		scipy
		seaborn
		statsmodels
		virtualenv
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

	# Internet
	firefox
	google-chrome
	telegram-desktop

	# IA
	chatgpt

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
	nixd
	poetry
	utm
	zed-editor

	# Data science
	pandoc
	texliveFull
	r-with-packages
	radian-with-packages
	rstudio-with-packages
	python3-with-packages
]
