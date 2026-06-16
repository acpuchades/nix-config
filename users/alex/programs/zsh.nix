{ config, pkgs, ... }:
{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history.size = 10000;
  initContent = ''
    if [ -n "$SSH_CONNECTION" ]; then
      alias emacs="emacs -nw"
    fi

    if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
      exec tmux new-session -A -s main
    fi
  '';
  oh-my-zsh = {
    enable = true;
    theme = "";
    plugins = [
      "colored-man-pages"
      "common-aliases"
      "extract"
      "git"
      "history-substring-search"
      "sudo"
    ];
  };
  plugins = [{
    name = "zsh-autosuggestions";
    src = pkgs.zsh-autosuggestions;
  } {
    name = "zsh-syntax-highlighting";
    src = pkgs.zsh-syntax-highlighting;
  }];
}
