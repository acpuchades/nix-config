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
  # Optional `layout` pins the workspace to a non-default sublayout, reapplied
  # whenever it gains focus (the global default-root-container-layout only seeds
  # fresh workspaces). One of: accordion-horizontal, accordion-vertical,
  # tiles-horizontal, tiles-vertical. Omit to inherit the global tiles default.
  homes = {
    d = { name = "design";    apps = [ "affinity" ]; layout = "accordion-horizontal"; };
    v = { name = "vms";       apps = [ "utm" ]; };
    m = { name = "email";     apps = [ "proton-mail" "apple-mail" "ms-outlook" ]; layout = "accordion-horizontal"; };
    r = { name = "reading";   apps = [ "obsidian" "reeder" ]; };
    b = { name = "browsing";  apps = [ "zen" "chromium" "safari" ]; layout = "accordion-horizontal"; };
    c = { name = "coding";    apps = [ "emacs" ]; };
    t = { name = "talk";      apps = [ "signal" "whatsapp" "ms-teams" "zoom" ]; layout = "accordion-horizontal"; };
    n = { name = "music";     apps = [ "spotify" ]; };
  };

  taskSpaces = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "0" ];

  # Home workspaces only ever hold their assigned apps; any other window opened
  # while a home is focused is evicted here (see homeGuardRules in aerospace.nix).
  unassignedSpace = "0";

  floats = [
    "system-preferences" "finder" "activity-monitor" "calculator"
    "raycast" "bartender" "cleanshot" "clop" "little-snitch"
    "micro-snitch" "dropover" "hand-mirror" "alcove" "text-edit"
    "ui-agent" "user-notification-center" "kaspersky-agent" "bitwarden"
    "nextcloud"
  ];

  # Float individual windows by title instead of by app — for apps whose
  # floating window shares its native identifier (bundle ID / app class) with
  # windows that should stay tiled, so `floats` (app-level) can't target it.
  # `title` is matched as a substring of the window title.
  #   e.g. Zotero's "add citation" search popup (insert references in Word) is
  #   the same app as the main library.
  # Zotero's citation dialog (used to add references in Word) shares the main
  # library's bundle ID, so it can't be floated app-wide via `floats`. The macOS
  # window title AeroSpace sees is "Diálogo de citas".
  titleFloats = [
    { app = "zotero"; title = "Diálogo de citas"; }
  ];

  shortcuts = {
    focus-left  = "super+alt+h";
    focus-down  = "super+alt+j";
    focus-up    = "super+alt+k";
    focus-right = "super+alt+l";

    # ctrl is the "transport" modifier (move the focused thing): cmd+opt+ctrl is a
    # comfortable bottom-left cluster, unlike the pinky-stretch cmd+opt+shift. Used
    # here and for move-and-follow below. This inverts the i3/AeroSpace "shift=move"
    # convention in favour of ergonomics; shift holds only the rarer ops.
    move-left  = "super+alt+ctrl+h";
    move-down  = "super+alt+ctrl+j";
    move-up    = "super+alt+ctrl+k";
    move-right = "super+alt+ctrl+l";

    resize-shrink = "super+alt+minus";
    resize-grow   = "super+alt+equal";

    # `slash` is a shifted key on the Spanish layout (shift+7), so super+alt+slash
    # collides with the move-window prefix (super+alt+shift) on task digit 7.
    # `period` pairs with `comma` (accordion) and is unshifted on both layouts.
    layout-tiles           = "super+alt+period";
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
    move-window     = "super+alt+shift";  # move focused window there, stay put (rarer → pinky shift)
    move-and-follow = "super+alt+ctrl";   # move focused window there and follow (frequent → comfy ctrl)
  };
}
