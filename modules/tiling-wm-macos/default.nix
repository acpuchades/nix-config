{ config, lib, ... }:

{
  options.my.tiling-wm-macos.enable =
    lib.mkEnableOption "AeroSpace tiling window manager + JankyBorders focus indicator";

  config = lib.mkIf config.my.tiling-wm-macos.enable {

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

        mode.main.binding = {
          # Focus windows
          cmd-alt-h = "focus left";
          cmd-alt-j = "focus down";
          cmd-alt-k = "focus up";
          cmd-alt-l = "focus right";

          # Move windows
          cmd-alt-shift-h = "move left";
          cmd-alt-shift-j = "move down";
          cmd-alt-shift-k = "move up";
          cmd-alt-shift-l = "move right";

          # Resize
          cmd-alt-minus = "resize smart -50";
          cmd-alt-equal = "resize smart +50";

          # Layouts
          cmd-alt-slash = "layout tiles horizontal vertical";
          cmd-alt-comma = "layout accordion horizontal vertical";
          cmd-alt-f = "fullscreen";
          cmd-alt-shift-space = "layout floating tiling";

          # Workspaces
          cmd-alt-1 = "workspace 1";
          cmd-alt-2 = "workspace 2";
          cmd-alt-3 = "workspace 3";
          cmd-alt-4 = "workspace 4";
          cmd-alt-5 = "workspace 5";
          cmd-alt-6 = "workspace 6";
          cmd-alt-7 = "workspace 7";
          cmd-alt-8 = "workspace 8";
          cmd-alt-9 = "workspace 9";
          cmd-alt-0 = "workspace 10";

          # Move window to workspace
          cmd-alt-shift-1 = "move-node-to-workspace 1";
          cmd-alt-shift-2 = "move-node-to-workspace 2";
          cmd-alt-shift-3 = "move-node-to-workspace 3";
          cmd-alt-shift-4 = "move-node-to-workspace 4";
          cmd-alt-shift-5 = "move-node-to-workspace 5";
          cmd-alt-shift-6 = "move-node-to-workspace 6";
          cmd-alt-shift-7 = "move-node-to-workspace 7";
          cmd-alt-shift-8 = "move-node-to-workspace 8";
          cmd-alt-shift-9 = "move-node-to-workspace 9";
          cmd-alt-shift-0 = "move-node-to-workspace 10";

          # Move window to workspace and follow it
          cmd-alt-ctrl-1 = "move-node-to-workspace --focus-follows-window 1";
          cmd-alt-ctrl-2 = "move-node-to-workspace --focus-follows-window 2";
          cmd-alt-ctrl-3 = "move-node-to-workspace --focus-follows-window 3";
          cmd-alt-ctrl-4 = "move-node-to-workspace --focus-follows-window 4";
          cmd-alt-ctrl-5 = "move-node-to-workspace --focus-follows-window 5";
          cmd-alt-ctrl-6 = "move-node-to-workspace --focus-follows-window 6";
          cmd-alt-ctrl-7 = "move-node-to-workspace --focus-follows-window 7";
          cmd-alt-ctrl-8 = "move-node-to-workspace --focus-follows-window 8";
          cmd-alt-ctrl-9 = "move-node-to-workspace --focus-follows-window 9";
          cmd-alt-ctrl-0 = "move-node-to-workspace --focus-follows-window 10";

          # Workspace navigation
          cmd-alt-tab = "workspace-back-and-forth";
          cmd-alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

          # Service mode (reload, reset)
          cmd-alt-shift-semicolon = "mode service";
        };

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

        # NOTE: verify exact app-id values with `aerospace list-apps` after first run
        on-window-detected = [
          # --- floats ---
          { "if".app-id = "com.apple.systempreferences";   run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.finder";              run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.ActivityMonitor";     run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.calculator";          run = [ "layout floating" ]; }
          { "if".app-id = "com.raycast.macos";             run = [ "layout floating" ]; }
          { "if".app-id = "com.surteesstudios.Bartender";  run = [ "layout floating" ]; }
          { "if".app-id = "pl.maketheweb.cleanshotx";      run = [ "layout floating" ]; }
          { "if".app-id = "com.lowtechguys.Clop";          run = [ "layout floating" ]; }
          { "if".app-id = "at.obdev.LittleSnitch";         run = [ "layout floating" ]; }
          { "if".app-id = "at.obdev.MicroSnitch";          run = [ "layout floating" ]; }
          { "if".app-id = "me.damir.dropover-mac";         run = [ "layout floating" ]; }
          { "if".app-id = "com.rocketshipapps.handmirror"; run = [ "layout floating" ]; }
          { "if".app-id = "com.alcoveapp.alcove";          run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.TextEdit";            run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.coreservices.uiagent"; run = [ "layout floating" ]; }
          { "if".app-id = "com.apple.UserNotificationCenter"; run = [ "layout floating" ]; }
          { "if".app-id = "com.kaspersky.kav_agent";       run = [ "layout floating" ]; }
          { "if".app-id = "com.bitwarden.desktop";         run = [ "layout floating" ]; }

          # --- workspace 1: design ---
          { "if".app-id = "com.canva.affinity"; run = [ "move-node-to-workspace 1" ]; }

          # --- workspace 2: VMs / remote ---
          { "if".app-id = "com.utmapp.UTM";                 run = [ "move-node-to-workspace 2" ]; }
          { "if".app-id = "com.omnissa.horizon.client.mac"; run = [ "move-node-to-workspace 2" ]; }

          # --- workspace 3: transfers / utils ---
          { "if".app-id = "org.localsend.localsend_app"; run = [ "move-node-to-workspace 3" ]; }
          { "if".app-id = "org.m0k.transmission";        run = [ "move-node-to-workspace 3" ]; }
          { "if".app-id = "com.nextcloud.desktopclient"; run = [ "move-node-to-workspace 3" ]; }

          # --- workspace 4: reading / notes / docs ---
          { "if".app-id = "md.obsidian";               run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "app.reeder";                run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.readdle.PDFExpert-Mac"; run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.adobe.Acrobat.Pro";     run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "org.zotero.zotero";         run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "org.libreoffice.script";    run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.microsoft.Word";        run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.microsoft.Excel";       run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.microsoft.Powerpoint";  run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.microsoft.Outlook";     run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.apple.Keynote";         run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.apple.Notes";           run = [ "move-node-to-workspace 4" ]; }
          { "if".app-id = "com.apple.Preview";         run = [ "move-node-to-workspace 4" ]; }

          # --- workspace 6: browsers ---
          { "if".app-id = "app.zen-browser.zen"; run = [ "move-node-to-workspace 6" ]; }
          { "if".app-id = "org.chromium.Chromium";             run = [ "move-node-to-workspace 6" ]; }
          { "if".app-id = "com.apple.Safari";                  run = [ "move-node-to-workspace 6" ]; }

          # --- workspace 7: terminal ---
          { "if".app-id = "com.mitchellh.ghostty"; run = [ "move-node-to-workspace 7" ]; }

          # --- workspace 8: dev ---
          { "if".app-id = "org.gnu.Emacs";                  run = [ "move-node-to-workspace 8" ]; }
          { "if".app-id = "com.anthropic.claudefordesktop"; run = [ "move-node-to-workspace 8" ]; }

          # --- workspace 9: comms ---
          { "if".app-id = "org.whispersystems.signal-desktop"; run = [ "move-node-to-workspace 9" ]; }
          { "if".app-id = "net.whatsapp.WhatsApp";             run = [ "move-node-to-workspace 9" ]; }
          { "if".app-id = "com.microsoft.teams2";              run = [ "move-node-to-workspace 9" ]; }
          { "if".app-id = "us.zoom.xos";                       run = [ "move-node-to-workspace 9" ]; }
          { "if".app-id = "ch.protonmail.desktop";             run = [ "move-node-to-workspace 9" ]; }
          { "if".app-id = "com.apple.mail";                    run = [ "move-node-to-workspace 9" ]; }

          # --- workspace 10: music ---
          { "if".app-id = "com.spotify.client"; run = [ "move-node-to-workspace 10" ]; }
        ];
      };
    };
  };
}
