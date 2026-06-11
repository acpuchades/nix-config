{ ... }:
{
  enable = true;

  # Rendered to ~/.claude/settings.json. The module also exposes `agents`,
  # `commands`, `hooks`, `mcpServers` and `memory` (CLAUDE.md) if needed later.
  settings = {
    # Keep git history clean: no Co-Authored-By trailer / "Generated with
    # Claude Code" line on commits and PRs.
    includeCoAuthoredBy = false;

    permissions = {
      # Auto-allow harmless, read-only inspection so they don't prompt.
      allow = [
        "Bash(git status:*)"
        "Bash(git diff:*)"
        "Bash(git log:*)"
        "Bash(git show:*)"
        "Bash(git branch:*)"
        "Bash(ls:*)"
        "Bash(tree:*)"
        "Bash(fd:*)"
        "Bash(rg:*)"
        "Bash(eza:*)"
      ];
      # Anything that writes, pushes, or deletes still prompts (default behavior).
    };
  };
}
