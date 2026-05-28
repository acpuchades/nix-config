{ config, pkgs, lib, ... }:

let
  shared = import ./config.nix;

  # Logical app name → macOS bundle ID. Verify with `aerospace list-apps`.
  appIds = {
    affinity            = "com.canva.affinity";
    utm                 = "com.utmapp.UTM";
    horizon-client      = "com.omnissa.horizon.client.mac";
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

  # Aerospace puts workspace 10 on the "0" key.
  numberKey = n: if n == 10 then "0" else toString n;

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

  mkWsBindings = prefix: cmdTemplate:
    lib.listToAttrs (lib.genList (i:
      let
        n = i + 1;
        key = toKey "${prefix}+${numberKey n}";
      in lib.nameValuePair key (cmdTemplate (toString n))
    ) 10);

  switchBindings = mkWsBindings shared.workspaceKeys.switch          (n: "workspace ${n}");
  moveBindings   = mkWsBindings shared.workspaceKeys.move-window     (n: "move-node-to-workspace ${n}");
  followBindings = mkWsBindings shared.workspaceKeys.move-and-follow (n: "move-node-to-workspace --focus-follows-window ${n}");

  floatRules = map (app: {
    "if".app-id = appIds.${app};
    run = [ "layout floating" ];
  }) shared.floats;

  workspaceRules = lib.concatLists (lib.mapAttrsToList
    (wsNum: ws: map (app: {
      "if".app-id = appIds.${app};
      run = [ "move-node-to-workspace ${wsNum}" ];
    }) ws.apps)
    shared.workspaces);
in
{
  config = lib.mkIf (config.my.tiling-wm.enable && pkgs.stdenv.isDarwin) {

    # Disable macOS trackpad Exposé/Spaces gestures that conflict with
    # AeroSpace's workspace model. mkForce overrides values set in settings.nix.
    system.defaults.CustomUserPreferences = {
      "com.apple.AppleMultitouchTrackpad" = {
        TrackpadThreeFingerVertSwipeGesture = lib.mkForce 0;
        TrackpadThreeFingerHorizSwipeGesture = 0;
      };
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        TrackpadThreeFingerVertSwipeGesture = lib.mkForce 0;
        TrackpadThreeFingerHorizSwipeGesture = 0;
      };
      "com.apple.dock" = {
        showAppExposeGestureEnabled = lib.mkForce false;
        showMissionControlGestureEnabled = lib.mkForce false;
      };
    };

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
        on-focus-changed = [ "move-mouse window-lazy-center" ];

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

        on-window-detected = floatRules ++ workspaceRules;
      };
    };
  };
}
