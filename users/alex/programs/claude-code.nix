{ pkgs, host, lib, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # Plugin name is load-bearing: Claude Code derives MCP tool names from it
  # (`mcp__plugin_<plugin>_<server>__<tool>`), and those names appear in
  # permission rules and allowlists. It matches the name home-manager used for
  # its own generated plugin, so renaming it here would silently invalidate any
  # rule that mentions the playwright tools.
  pluginName = "claude-code-home-manager";
  marketplaceName = "home-manager";

  # Playwright browser-automation MCP server, homeserver-only. The nixpkgs
  # `playwright-mcp` wraps its binary with PLAYWRIGHT_BROWSERS_PATH already set
  # to the matching nix-built browsers (playwright-driver.browsers) — the npm
  # driver's own download won't run on NixOS, so this is the only version-aligned
  # way to get it. Referenced by full store path so it needs nothing on PATH.
  # Darwin is excluded: playwright-driver.browsers targets Linux and the user
  # only asked for the homeserver.
  #   --headless  no X server on the box
  #   --isolated  no persistent browser profile between sessions
  mcpServers = {
    playwright = {
      type = "stdio";
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [ "--headless" "--isolated" ];
    };
  };

  # A single-plugin marketplace carrying the MCP server definitions.
  #
  # WHY NOT `programs.claude-code.mcpServers`: that option makes home-manager
  # build an equivalent plugin dir and then *wrap* the claude binary with
  # `--plugin-dir <store path>` prepended to every invocation. `claude
  # remote-control` does not parse its flags with commander — it hand-rolls an
  # argv scanner that accepts only its own options — so the injected flag value
  # falls through to it and every invocation dies with
  # "Error: Unknown argument: /nix/store/...-claude-code-hm-plugin".
  # Registering the same plugin through a marketplace instead needs no CLI flag,
  # so `finalPackage` stays the unwrapped package and remote-control works.
  #
  # Claude Code reads the plugin straight from these store paths — verified on
  # 2.1.223 that a fresh config dir with no `installed_plugins.json` and no
  # plugin cache still resolves the server, and that a changed store path is
  # picked up without any `claude plugin install`/`marketplace update` step.
  marketplace = pkgs.runCommand "claude-code-hm-marketplace" { } ''
    install -Dm444 ${
      jsonFormat.generate "marketplace.json" {
        name = marketplaceName;
        owner.name = "home-manager";
        description = "MCP servers declared by this flake's home-manager config";
        plugins = [
          {
            name = pluginName;
            source = "./${pluginName}";
            description = "MCP servers declared by this flake's home-manager config";
          }
        ];
      }
    } $out/.claude-plugin/marketplace.json

    install -Dm444 ${
      jsonFormat.generate "plugin.json" {
        name = pluginName;
        version = "1.0.0";
        description = "MCP servers declared by this flake's home-manager config";
      }
    } $out/${pluginName}/.claude-plugin/plugin.json

    install -Dm444 ${jsonFormat.generate "mcp.json" { inherit mcpServers; }} \
      $out/${pluginName}/.mcp.json
  '';

  # `settings` is a freeform JSON type, so `lib.mkIf` inside it would be
  # serialised rather than evaluated — gate with plain Nix instead.
  onHomeserver = host == "homeserver";
in
{
  enable = true;

  # Writes `extraKnownMarketplaces` into settings.json and
  # ~/.claude/plugins/known_marketplaces.json. Both are read-only store symlinks;
  # Claude Code only reads them.
  marketplaces = lib.optionalAttrs onHomeserver { ${marketplaceName} = marketplace; };

  # Rendered to ~/.claude/settings.json. The module also exposes `agents`,
  # `commands`, `hooks`, `mcpServers` and `memory` (CLAUDE.md) if needed later —
  # but see the note on `marketplace` above before reaching for `mcpServers`.
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
  }
  # Registering the marketplace only makes the plugin *available*; this is what
  # turns it on.
  // lib.optionalAttrs onHomeserver {
    enabledPlugins = { "${pluginName}@${marketplaceName}" = true; };
  };
}
