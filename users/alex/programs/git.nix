{ ... }:
{
  enable = true;
  ignores = [ ".DS_Store" ];
  settings = {
    core.pager = "delta";
    credential.helper = "!gh auth git-credential";
    delta.navigate = true;
    init.defaultBranch = "main";
    interactive.diffFilter = "delta --color-only";
    merge.conflictstyle = "zdiff3";
    user.name = "acpuchades";
    user.email = "59510094+acpuchades@users.noreply.github.com";
    push.autoSetupRemote = true;
  };
}
