inputs: {
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  atuin = import ./atuin.nix inputs;
  eza = import ./eza.nix inputs;
  fzf = import ./fzf.nix inputs;
  ghostty = import ./ghostty.nix inputs;
  gpg = import ./gpg.nix inputs;
  git = import ./git.nix inputs;
  ssh = import ./ssh.nix inputs;
  tmux = import ./tmux.nix inputs;
  zoxide = import ./zoxide.nix inputs;
  zsh = import ./zsh.nix inputs;

  bat.enable = true;
  btop.enable = true;
  direnv.enable = true;
  direnv.nix-direnv.enable = true;
  gh.enable = true;
  lazygit.enable = true;
  starship.enable = true;
}
