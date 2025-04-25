{ pkgs, ... }:

let
	r-packages = with pkgs.rPackages; [
		broom
		cli
		DBI
		devtools
		effects
		ggsignif
		ggsurvfit
		httpgd
		janitor
		knitr
		languageserver
		MatchIt
		mice
		missForest
		nlme
		nls_multstart
		patchwork
		readxl
		renv
		rmarkdown
		rvest
		RSQLite
		Rtsne
		shiny
		tidyverse
		writexl
	];

	r-with-packages = pkgs.rWrapper.override { packages = r-packages; };
	radian-with-packages = pkgs.radianWrapper.override { packages = r-packages; };
	rstudio-with-packages = pkgs.rstudioWrapper.override { packages = r-packages; };

	python3-with-packages = pkgs.python3.withPackages (ps: with ps; [
		keras
		jupyter
		lifelines
		matplotlib
		numpy
		optuna
		pandas
		playwright
		polars
		scikit-learn
		scipy
		scrapy
		seaborn
		statsmodels
		tensorflow
		torch
		virtualenv
	]);

in with pkgs; [
 	# System
		bat
		delta
		direnv
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
	docker
	dotnet-sdk
	git
	nil
	nixd
	poetry
	zed-editor

	# Data science
	pandoc
	texliveFull
	r-with-packages
	radian-with-packages
	rstudio-with-packages
	python3-with-packages
]
