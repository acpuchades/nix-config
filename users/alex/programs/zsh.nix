{ config, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 10000;
    initContent = ''
      # The PyPI token goes to `uv publish` alone, not into every shell's
      # environment where any build script or tool could read it. uv
      # ignores ~/.pypirc, hence the wrapper.
      uv() {
        if [ "$1" = publish ] && [ -r "${config.sops.secrets."pypi/token".path}" ]; then
          UV_PUBLISH_TOKEN="$(cat "${config.sops.secrets."pypi/token".path}")" command uv "$@"
        else
          command uv "$@"
        fi
      }

      if [ -n "$SSH_CONNECTION" ]; then
        alias emacs="emacs -nw"
      fi

      unalias rm cp mv 2>/dev/null

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
  };
}
