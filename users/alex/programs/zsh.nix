{
	enable = true;
	enableCompletion = true;
	autosuggestion.enable = true;
	syntaxHighlighting.enable = true;
	history.size = 10000;

	oh-my-zsh = {
		enable = true;
		theme = "robbyrussell";
		plugins = [
			"git"
			"direnv"
			"history"
		];
	};
}