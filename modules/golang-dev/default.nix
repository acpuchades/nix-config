{ config, lib, pkgs, ... }:

{
  options.my.golang-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for Go development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      go
      gopls
      gotools       # goimports, godoc, etc.
      go-tools      # staticcheck
      delve         # debugger (dlv)
      golangci-lint
    ] ++ config.my.golang-dev.extraPackages;
  };
}
