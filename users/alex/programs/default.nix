inputs: {
  # Let home Manager install and manage itself.
  home-manager.enable = true;

  emacs = import ./emacs.nix inputs;
  ghostty = import ./ghostty.nix inputs;
  gpg = import ./gpg.nix inputs;
  git = import ./git.nix inputs;
  zsh = import ./zsh.nix inputs;

  direnv.enable = true;
  direnv.nix-direnv.enable = true;
  gh.enable = true;
  mbsync.enable = true;
  msmtp.enable = true;
  mu.enable = true;
  starship.enable = true;
}
