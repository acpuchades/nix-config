{ pkgs, ... }:

{
	programs.git = import ./git.nix;
	programs.vscode = import ./vscode.nix;
	programs.zsh = import ./zsh.nix;
}