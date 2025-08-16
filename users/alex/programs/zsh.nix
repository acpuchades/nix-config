{ pkgs, ... }:
{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history.size = 10000;
  plugins = [
	{
	  name = "zsh-autosuggestions";
	  src = pkgs.zsh-autosuggestions;
	}
	{
	  name = "zsh-syntax-highlighting";
	  src = pkgs.zsh-syntax-highlighting;
	}
  ];
}
