{ config, lib, pkgs, ... }:

{
  options.my.rust-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for Rust development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      rustc
      cargo
      clippy
      rustfmt
      rust-analyzer
      cargo-edit
      cargo-watch
    ] ++ config.my.rust-dev.extraPackages;

    home.sessionPath = [ "$HOME/.cargo/bin" ];
  };
}
