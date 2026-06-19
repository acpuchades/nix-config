{ config, lib, pkgs, ... }:

{
  options.my.nix-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for Nix development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      nil           # Nix LSP server
      nixd          # Nix LSP server (alternative)
      nixfmt        # Nix formatter
      nix-direnv    # faster direnv integration for Nix shells

      # Secrets tooling used across this flake
      sops
      ssh-to-age
    ] ++ config.my.nix-dev.extraPackages;
  };
}
