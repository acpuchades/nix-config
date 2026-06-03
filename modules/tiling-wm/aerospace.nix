{ config, pkgs, lib, ... }:

let
  shared = import ./config.nix;

  # Logical app name → macOS bundle ID. Verify with `aerospace list-apps`.
  appIds = {
    affinity            = "com.canva.affinity";
    utm                 = "com.utmapp.UTM";
    localsend           = "org.localsend.localsend_app";
    transmission        = "org.m0k.transmission";
    nextcloud           = "com.nextcloud.desktopclient";
    obsidian            = "md.obsidian";
    reeder              = "app.reeder";
    pdf-expert          = "com.readdle.PDFExpert-Mac";
    acrobat-pro         = "com.adobe.Acrobat.Pro";
    zotero              = "org.zotero.zotero";
    libreoffice         = "org.libreoffice.script";
    ms-word             = "com.microsoft.Word";
    ms-excel            = "com.microsoft.Excel";
    ms-powerpoint       = "com.microsoft.Powerpoint";
    ms-outlook          = "com.microsoft.Outlook";
    keynote             = "com.apple.Keynote";
    notes               = "com.apple.Notes";
    preview             = "com.apple.Preview";
    zen                 = "app.zen-browser.zen";
    chromium            = "org.chromium.Chromium";
    safari              = "com.apple.Safari";
    ghostty             = "com.mitchellh.ghostty";
    emacs               = "org.gnu.Emacs";
    claude-desktop      = "com.anthropic.claudefordesktop";
    signal              = "org.whispersystems.signal-desktop";
    whatsapp            = "net.whatsapp.WhatsApp";
    ms-teams            = "com.microsoft.teams2";
    zoom                = "us.zoom.xos";
    proton-mail         = "ch.protonmail.desktop";
    apple-mail          = "com.apple.mail";
    spotify             = "com.spotify.client";

    system-preferences        = "com.apple.systempreferences";
    finder                    = "com.apple.finder";
    activity-monitor          = "com.apple.ActivityMonitor";
    calculator                = "com.apple.calculator";
    raycast                   = "com.raycast.macos";
    bartender                 = "com.surteesstudios.Bartender";
    cleanshot                 = "pl.maketheweb.cleanshotx";
    clop                      = "com.lowtechguys.Clop";
    little-snitch             = "at.obdev.LittleSnitch";
    micro-snitch              = "at.obdev.MicroSnitch";
    dropover                  = "me.damir.dropover-mac";
    hand-mirror               = "com.rocketshipapps.handmirror";
    alcove                    = "com.alcoveapp.alcove";
    text-edit                 = "com.apple.TextEdit";
    ui-agent                  = "com.apple.coreservices.uiagent";
    user-notification-center  = "com.apple.UserNotificationCenter";
    kaspersky-agent           = "com.kaspersky.kav_agent";
    bitwarden                 = "com.bitwarden.desktop";
  };

  # Normalized chord ("super+alt+h") → aerospace format ("cmd-alt-h").
  toKey = chord:
    let
      modMap = { super = "cmd"; alt = "alt"; shift = "shift"; ctrl = "ctrl"; };
      parts = lib.splitString "+" chord;
    in lib.concatMapStringsSep "-" (p: modMap.${p} or p) parts;

  # Logical action → aerospace command.
  actionMap = {
    focus-left  = "focus left";
    focus-down  = "focus down";
    focus-up    = "focus up";
    focus-right = "focus right";

    move-left  = "move left";
    move-down  = "move down";
    move-up    = "move up";
    move-right = "move right";

    resize-shrink = "resize smart -50";
    resize-grow   = "resize smart +50";

    layout-tiles           = "layout tiles horizontal vertical";
    layout-accordion       = "layout accordion horizontal vertical";
    layout-fullscreen      = "fullscreen";
    layout-floating-toggle = "layout floating tiling";

    workspace-back-and-forth  = "workspace-back-and-forth";
    workspace-to-next-monitor = "move-workspace-to-monitor --wrap-around next";

    service-mode = "mode service";
  };

  actionBindings = lib.mapAttrs'
    (action: chord: lib.nameValuePair (toKey chord) actionMap.${action})
    shared.shortcuts;

  # Every workspace as a {key, ws} target: letter homes + numbered task spaces.
  wsTargets =
    lib.mapAttrsToList (key: h: { inherit key; ws = h.name; }) shared.homes
    ++ map (digit: { key = digit; ws = digit; }) shared.taskSpaces;

  mkWsBindings = prefix: cmdTemplate:
    lib.listToAttrs (map (t:
      lib.nameValuePair (toKey "${prefix}+${t.key}") (cmdTemplate t.ws)
    ) wsTargets);

  switchBindings = mkWsBindings shared.workspaceKeys.switch          (ws: "workspace ${ws}");
  moveBindings   = mkWsBindings shared.workspaceKeys.move-window     (ws: "move-node-to-workspace ${ws}");
  followBindings = mkWsBindings shared.workspaceKeys.move-and-follow (ws: "move-node-to-workspace --focus-follows-window ${ws}");

  floatRules = map (app: {
    "if".app-id = appIds.${app};
    run = [ "layout floating" ];
  }) shared.floats;

  # Float only specific windows of an app by title — needed when the window we
  # want floating shares its bundle ID with windows we want tiled (see
  # shared.titleFloats). Matched before workspaceRules/homeGuardRules so the
  # window floats in place rather than being assigned/evicted.
  titleFloatRules = map (f: {
    "if" = {
      app-id = appIds.${f.app};
      window-title-regex-substring = f.title;
    };
    run = [ "layout floating" ];
  }) shared.titleFloats;

  workspaceRules = lib.concatLists (lib.mapAttrsToList
    (_key: h: map (app: {
      "if".app-id = appIds.${app};
      run = [ "move-node-to-workspace ${h.name}" ];
    }) h.apps)
    shared.homes);

  # Guard: evict any window not pinned to a home by the app-id rules above out of
  # that home workspace, keeping homes limited to their apps. Ordered AFTER
  # floatRules/workspaceRules so assigned + floating apps match their specific
  # rule first (first-match-wins); only unmatched windows reach the guard.
  homeGuardRules = lib.mapAttrsToList (_key: h: {
    "if".workspace = h.name;
    run = [ "move-node-to-workspace --focus-follows-window ${shared.unassignedSpace}" ];
  }) shared.homes;
in
{
  config = lib.mkIf (config.my.tiling-wm.enable && pkgs.stdenv.isDarwin) {

    # These merge per-key with the system.defaults.dock block in settings.nix.
    system.defaults.dock = {
      # AeroSpace "hides" inactive-workspace windows by parking them off-screen in
      # the bottom-right corner. App Exposé / Mission Control then scale their
      # layout over a bounding box that includes those parked windows, rendering
      # everything tiny. Grouping windows by application keeps Exposé legible.
      # mkForce overrides the `false` default kept in settings.nix.
      expose-group-apps = lib.mkForce true;

      # Keep Spaces in a fixed order so workspace bindings don't break when macOS
      # reorders them by recent use.
      mru-spaces = false;
    };

    # Native NSWindow tabs conflict with AeroSpace tiling: each cmd-t briefly
    # creates a real window that AeroSpace tiles before it merges into the tab
    # group, leaving the original window stuck at half-size. Unbind it here so the
    # workaround travels with the module instead of living in ghostty.nix.
    home-manager.users.${config.system.primaryUser}.programs.ghostty.settings.keybind =
      [ "cmd+t=unbind" ];

    services.jankyborders = {
      enable = true;

      # AeroSpace doesn't move macOS's notion of key window; use accessibility
      # focus so borders track the actually-focused tiled window.
      ax_focus = true;

      width = 4.0;
      hidpi = true;
      style = "round";

      active_color = "0xff89b4fa";   # soft blue
      inactive_color = "0x00000000"; # transparent
    };

    services.aerospace = {
      enable = true;

      settings = {
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";

        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;

        accordion-padding = 30;

        on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

        gaps = {
          inner.horizontal = 8;
          inner.vertical = 8;
          outer.left = 8;
          outer.right = 8;
          outer.top = 8;
          outer.bottom = 8;
        };

        workspace-to-monitor-force-assignment = { };

        mode.main.binding = actionBindings // switchBindings // moveBindings // followBindings;

        mode.service.binding = {
          esc = [ "reload-config" "mode main" ];
          r = [ "flatten-workspace-tree" "mode main" ];
          f = [ "layout floating tiling" "mode main" ];
          backspace = [ "close-all-windows-but-current" "mode main" ];

          cmd-alt-shift-h = [ "join-with left" "mode main" ];
          cmd-alt-shift-j = [ "join-with down" "mode main" ];
          cmd-alt-shift-k = [ "join-with up" "mode main" ];
          cmd-alt-shift-l = [ "join-with right" "mode main" ];
        };

        on-window-detected = floatRules ++ titleFloatRules ++ workspaceRules ++ homeGuardRules;
      };
    };
  };
}
