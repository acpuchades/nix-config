{ pkgs, ... }:

with pkgs; let

	r-with-packages = rWrapper.override {
		packages = with pkgs.rPackages; [
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
			SKAT
			tidyverse
			uwot
			writexl
		];
	};

	python3-with-packages = python3.withPackages (ps: with ps; [
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

in [
	# System
	pkgs.bat
	pkgs.direnv
	pkgs.vim

	# Development
	pkgs.docker
	pkgs.dotnet-sdk
	pkgs.git
	pkgs.poetry

	# Fonts
	pkgs.font-awesome
	pkgs.nerd-fonts.fira-code

	# Genetics
	pkgs.bcftools
	pkgs.snakemake

	# Data science
	pkgs.pandoc
	pkgs.texliveFull
	r-with-packages
	python3-with-packages

	# Security
	pkgs.gnupg
]