# Aggregator for the per-program modules in this directory. Each file is a
# real home-manager module owning its programs.<name> subtree (it can read
# config/pkgs/host itself), so adding a program is one file plus one line
# here — no argument threading.
{ ... }:
{
  imports = [
    ./atuin.nix
    ./claude-code.nix
    ./eza.nix
    ./fzf.nix
    ./ghostty.nix
    ./gpg.nix
    ./git.nix
    ./ssh.nix
    ./tmux.nix
    ./zoxide.nix
    ./zsh.nix
  ];

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Bare enables with no config of their own.
  programs.bat.enable = true;
  programs.btop.enable = true;
  programs.codex.enable = true;
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;
  programs.gh.enable = true;
  programs.lazygit.enable = true;
  programs.starship.enable = true;
}
