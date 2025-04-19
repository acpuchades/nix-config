{ pkgs, ... }:

with pkgs; let

	r-with-packages = rWrapper.override {
		packages = with pkgs.rPackages; [
			DBI
			devtools
			ggsurvfit
			httpgd
			languageserver
			knitr
			readxl
			rmarkdown
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
	pkgs.git
	pkgs.poetry

	# Fonts
	pkgs.font-awesome
	pkgs.nerd-fonts.fira-code
	pkgs.nerd-fonts.fira-mono

	# Genetics
	pkgs.bcftools
	pkgs.snakemake

	# Data science
	pkgs.pandoc
	pkgs.quarto
	pkgs.texliveFull
	r-with-packages
	python3-with-packages

	# Security
	pkgs.gnupg
]