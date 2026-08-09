{ pkgs, host, lib, ... }:
{
  enable = true;

  # Playwright browser-automation MCP server, homeserver-only. The nixpkgs
  # `playwright-mcp` wraps its binary with PLAYWRIGHT_BROWSERS_PATH already set
  # to the matching nix-built browsers (playwright-driver.browsers) — the npm
  # driver's own download won't run on NixOS, so this is the only version-aligned
  # way to get it. Referenced by full store path so it needs nothing on PATH.
  # Darwin is excluded: playwright-driver.browsers targets Linux and the user
  # only asked for the homeserver.
  #   --headless  no X server on the box
  #   --isolated  no persistent browser profile between sessions
  mcpServers = lib.mkIf (host == "homeserver") {
    playwright = {
      type = "stdio";
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [ "--headless" "--isolated" ];
    };
  };

  # Rendered to ~/.claude/settings.json. The module also exposes `agents`,
  # `commands`, `hooks`, `mcpServers` and `memory` (CLAUDE.md) if needed later.
  settings = {
    # Keep git history clean: no Co-Authored-By trailer / "Generated with
    # Claude Code" line on commits and PRs.
    includeCoAuthoredBy = false;

    permissions = {
      # Start every session in "auto" mode: a classifier decides per-action what
      # is safe to auto-approve (not a fixed allowlist), and gates anything it
      # judges risky. (Shift+Tab cycles modes per-session; this sets the default.)
      defaultMode = "auto";
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
