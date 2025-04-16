{
	enable = true;
	enableCompletion = true;
	autosuggestion.enable = true;
	syntaxHighlighting.enable = true;

	oh-my-zsh = {
		enable = true;
		theme = "robbyrussell";
		plugins = [
			"git"
			"direnv"
			"history"
		];
	};

	shellAliases = {
		la = "ls -A";
		ll = "ls -lh";
		lla = "la -lhA";
	};

	history.size = 10000;
}