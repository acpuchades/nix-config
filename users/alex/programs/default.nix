inputs: {
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  ghostty = import ./ghostty.nix inputs;
  gpg = import ./gpg.nix inputs;
  git = import ./git.nix inputs;
  ssh = import ./ssh.nix inputs;
  tmux = import ./tmux.nix inputs;
  zsh = import ./zsh.nix inputs;

  direnv.enable = true;
  direnv.nix-direnv.enable = true;
  gh.enable = true;
  starship.enable = true;
}
