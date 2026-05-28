{ config, pkgs, lib, ... }:

# Stub. When a Linux desktop machine joins the flake, mirror aerospace.nix:
# import ./config.nix, build a logical-name → Wayland app-class lookup,
# translate the normalized chords (super → mod4), and configure wayland.windowManager.hyprland.

{
  config = lib.mkIf (config.my.tiling-wm.enable && !pkgs.stdenv.isDarwin) {
    assertions = [{
      assertion = false;
      message = "my.tiling-wm: Hyprland support is not implemented yet — populate modules/tiling-wm/hyprland.nix.";
    }];
  };
}
