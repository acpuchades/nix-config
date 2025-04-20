{ pkgs, ... }:

let
	r-packages = with pkgs.rPackages; [
		DBI
		dbscan
		devtools
		ggsurvfit
		gtsummary
		httpgd
		janitor
		knitr
		languageserver
		mice
		missForest
		readxl
		renv
		rmarkdown
		rvest
		RSQLite
		Rtsne
		shiny
		stringi
		SKAT
		tidyverse
		uwot
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
	direnv
	vim

	# Development
	docker
	dotnet-sdk
	git
	poetry
	zed-editor

	# Fonts
	font-awesome
	nerd-fonts.fira-code

	# Genetics
	bcftools
	snakemake

	# Data science
	pandoc
	texliveFull
	r-with-packages
	radian-with-packages
	rstudio-with-packages
	python3-with-packages

	# Security
	gnupg
]