# System-agnostic tiling WM configuration.
#
# Each per-WM module (aerospace.nix, hyprland.nix) imports this file and is
# responsible for: (a) resolving logical app names to native identifiers
# (macOS bundle IDs / Wayland app classes), and (b) translating the
# normalized key chord syntax to the WM's keybinding format.
#
# Key chord notation: modifiers and key separated by "+", lowercased.
# `super` is the primary modifier — cmd on macOS, mod4 on Linux.
#
# Workspaces come in two kinds:
#   - homes      : task-agnostic apps with a fixed home, keyed by a mnemonic
#                  letter (super+alt+<letter>). Every app here is auto-assigned
#                  to its workspace on launch.
#   - taskSpaces : numbered scratch workspaces (super+alt+<digit>) for ad-hoc
#                  work. Nothing is auto-assigned, so task-specific tools
#                  (office, pdf, claude, ghostty, …) open in whichever one is
#                  focused — the absence of an entry IS "open where I am".

{
  # key = the bare key for super+alt+<key>; name = the AeroSpace workspace id.
  homes = {
    d = { name = "design";    apps = [ "affinity" ]; };
    v = { name = "vms";       apps = [ "utm" ]; };
    e = { name = "email";     apps = [ "proton-mail" "apple-mail" "ms-outlook" ]; };
    r = { name = "reading";   apps = [ "obsidian" "reeder" ]; };
    b = { name = "browsing";  apps = [ "zen" "chromium" "safari" ]; };
    c = { name = "coding";    apps = [ "emacs" ]; };
    m = { name = "messaging"; apps = [ "signal" "whatsapp" "ms-teams" "zoom" ]; };
    n = { name = "music";     apps = [ "spotify" ]; };
  };

  taskSpaces = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "0" ];

  floats = [
    "system-preferences" "finder" "activity-monitor" "calculator"
    "raycast" "bartender" "cleanshot" "clop" "little-snitch"
    "micro-snitch" "dropover" "hand-mirror" "alcove" "text-edit"
    "ui-agent" "user-notification-center" "kaspersky-agent" "bitwarden"
    "nextcloud"
  ];

  shortcuts = {
    focus-left  = "super+alt+h";
    focus-down  = "super+alt+j";
    focus-up    = "super+alt+k";
    focus-right = "super+alt+l";

    move-left  = "super+alt+shift+h";
    move-down  = "super+alt+shift+j";
    move-up    = "super+alt+shift+k";
    move-right = "super+alt+shift+l";

    resize-shrink = "super+alt+minus";
    resize-grow   = "super+alt+equal";

    layout-tiles           = "super+alt+slash";
    layout-accordion       = "super+alt+comma";
    layout-fullscreen      = "super+alt+f";
    layout-floating-toggle = "super+alt+shift+space";

    workspace-back-and-forth  = "super+alt+tab";
    workspace-to-next-monitor = "super+alt+shift+tab";

    service-mode = "super+alt+shift+semicolon";
  };

  # Modifier prefixes applied to every workspace key (home letters and task
  # digits alike). Each per-WM module emits <prefix>+<key> for each workspace.
  workspaceKeys = {
    switch          = "super+alt";        # switch to the workspace
    move-window     = "super+alt+shift";  # move focused window to the workspace
    move-and-follow = "super+alt+ctrl";   # move window to the workspace and follow it
  };
}
