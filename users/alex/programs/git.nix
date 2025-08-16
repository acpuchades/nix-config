{ ... }:
{
  enable = true;
  userName = "acpuchades";
  userEmail = "59510094+acpuchades@users.noreply.github.com";
  ignores = [ ".DS_Store" ];
  extraConfig = {
	core.pager = "delta";
	delta.navigate = true;
	init.defaultBranch = "main";
	interactive.diffFilter = "delta --color-only";
	merge.conflictstyle = "zdiff3";
	push.autoSetupRemote = true;
	credential.helper = "!gh auth git-credential";
  };
}
