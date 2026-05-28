{ config, osConfig, lib, pkgs, ... }:

let
  ghosttyPackage =
    if pkgs.stdenv.isDarwin then pkgs.ghostty-bin
    else pkgs.ghostty;

  # Native NSWindow tabs conflict with AeroSpace tiling: each cmd-t briefly
  # creates a real window that AeroSpace tiles before it merges into the tab
  # group, leaving the original window stuck at half-size.
  tilingWmEnabled = osConfig.my.tiling-wm-macos.enable or false;
in
{
  enable = true;
  package = ghosttyPackage;
  enableZshIntegration = true;
  installBatSyntax = true;
  settings = {
    copy-on-select = true;
    env = "LC_CTYPE=es_ES.UTF-8";
    font-family = "FiraCode Nerd Font Mono Light";
    font-family-bold = "FiraCode Nerd Font Mono Med";
    font-feature = "liga,clig,calt";
    font-size = 13;
    term = "xterm-256color";
    theme = "Catppuccin Mocha";
    keybind = lib.optionals tilingWmEnabled [ "cmd+t=unbind" ];
  };
}
