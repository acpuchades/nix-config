# System-agnostic tiling WM configuration.
#
# Each per-WM module (aerospace.nix, hyprland.nix) imports this file and is
# responsible for: (a) resolving logical app names to native identifiers
# (macOS bundle IDs / Wayland app classes), and (b) translating the
# normalized key chord syntax to the WM's keybinding format.
#
# Key chord notation: modifiers and key separated by "+", lowercased.
# `super` is the primary modifier — cmd on macOS, mod4 on Linux.

{
  workspaces = {
    "1"  = { name = "design";       apps = [ "affinity" ]; };
    "2"  = { name = "vms-remote";   apps = [ "utm" "horizon-client" ]; };
    "3"  = { name = "transfers";    apps = [ "localsend" "transmission" "nextcloud" ]; };
    "4"  = { name = "reading-docs"; apps = [
      "obsidian" "reeder" "pdf-expert" "acrobat-pro" "zotero"
      "libreoffice" "ms-word" "ms-excel" "ms-powerpoint" "ms-outlook"
      "keynote" "notes" "preview"
    ]; };
    # workspace 5 intentionally unassigned — free for ad-hoc work
    "6"  = { name = "browsers";     apps = [ "zen-browser" "chromium" "safari" ]; };
    "7"  = { name = "terminal";     apps = [ "ghostty" ]; };
    "8"  = { name = "dev";          apps = [ "emacs" "claude-desktop" ]; };
    "9"  = { name = "comms";        apps = [
      "signal" "whatsapp" "ms-teams" "zoom" "proton-mail" "apple-mail"
    ]; };
    "10" = { name = "music";        apps = [ "spotify" ]; };
  };

  floats = [
    "system-preferences" "finder" "activity-monitor" "calculator"
    "raycast" "bartender" "cleanshot" "clop" "little-snitch"
    "micro-snitch" "dropover" "hand-mirror" "alcove" "text-edit"
    "ui-agent" "user-notification-center" "kaspersky-agent" "bitwarden"
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

  # Modifier prefixes for the 1..10 number row. Each per-WM module generates
  # one binding per workspace: <prefix>+<N> with workspace 10 on key "0".
  workspaceKeys = {
    switch          = "super+alt";        # switch to workspace N
    move-window     = "super+alt+shift";  # move focused window to workspace N
    move-and-follow = "super+alt+ctrl";   # move window to workspace N and follow it
  };
}
