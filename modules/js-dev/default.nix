{ config, lib, pkgs, ... }:

{
  options.my.js-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for JavaScript/TypeScript development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      nodejs                          # node, npm, npx, corepack
      pnpm                            # fast, disk-efficient package manager
      yarn                            # classic package manager
      typescript                      # tsc
      typescript-language-server      # LSP for JS/TS
      vscode-langservers-extracted    # html/css/json/eslint language servers
      eslint                          # linter
      prettier                        # formatter
      deno                            # all-in-one runtime/formatter/linter
      bun                             # fast runtime + package manager + bundler
    ] ++ config.my.js-dev.extraPackages;

    # npm/pnpm global installs land in ~/.npm-global; keep their bins on PATH.
    home.sessionPath = [ "$HOME/.npm-global/bin" ];
    home.sessionVariables.NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };
}
