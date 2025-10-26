{ config, pkgs, ... }:
{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history.size = 10000;
  loginExtra = ''
    # export api keys from secrets
    if [[ -r '${config.sops.secrets."anthropic/token".path}' ]]; then
      export ANTHROPIC_API_KEY="$(<'${config.sops.secrets."anthropic/token".path}')"
    fi

    # mamba shell hook
    if command -v mamba >/dev/null 2>&1; then
      eval "$(${pkgs.mamba-cpp}/bin/mamba shell hook --shell zsh)"
    fi
  '';
  oh-my-zsh = {
    enable = true;
    theme = "";
    plugins = [
      "colored-man-pages"
      "common-aliases"
      "extract"
      "fzf"
      "git"
      "history-substring-search"
      "sudo"
      "z"
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
}
