{ lib, ... }:

{
  imports = [ ./aerospace.nix ./hyprland.nix ];

  options.my.tiling-wm.enable =
    lib.mkEnableOption "tiling window manager (AeroSpace on macOS, Hyprland on Linux)";
}
