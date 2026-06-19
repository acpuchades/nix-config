{ config, pkgs, ... }:
{
  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Allow installation of not-free software
  nixpkgs.config.allowUnfree = true;

  # Enable the touch ID authentication for sudo.
  security.pam.services.sudo_local.touchIdAuth = true;

  system.activationScripts.postActivation.text = ''
    # Reload macOS settings and restart Dock so defaults take effect without a logout cycle.
    sudo -u ${config.system.primaryUser} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    sudo -u ${config.system.primaryUser} /usr/bin/killall Dock || true

    # LibreOffice's main cask overwrites translation files on every upgrade, so
    # re-run the language pack installer after homebrew activation.
    for script in /opt/homebrew/Caskroom/libreoffice-language-pack/*/SilentInstall.sh; do
      [ -x "$script" ] && /bin/bash "$script" || true
    done
  '';

  system.defaults.dock = {
    autohide = true;
    autohide-delay = 0.0;
    autohide-time-modifier = 0.5;
    expose-animation-duration = 0.5;
    expose-group-apps = false;

    show-recents = false;
    magnification = false;
    tilesize = 64;

    # Hot corners: 1 = Disabled (no action), 13 = Lock Screen.
    wvous-bl-corner = 1;
    wvous-br-corner = 13;

    persistent-apps = [
      { app = "/Applications/Zen.app"; }
      { app = "/Applications/Proton Mail.app"; }
      { app = "/System/Applications/Mail.app"; }
      { app = "/Applications/WhatsApp.app"; }
      { app = "/System/Applications/Photos.app"; }
      { app = "/Applications/Claude.app"; }
      { app = "/System/Applications/Reminders.app"; }
      { app = "/System/Applications/Calendar.app"; }
      { app = "/System/Applications/Notes.app"; }
      { app = "/Applications/Spotify.app"; }
      { app = "/Applications/Keynote Creator Studio.app"; }
      { app = "/System/Applications/App Store.app"; }
      { app = "/System/Applications/System Settings.app"; }
    ];
  };

  system.defaults.finder = {
    _FXShowPosixPathInTitle = false;
    _FXSortFoldersFirst = true;
    FXEnableExtensionChangeWarning = false;
    FXPreferredViewStyle = "icnv";
    FXRemoveOldTrashItems = true;
    AppleShowAllExtensions = true;
    FXDefaultSearchScope = "SCcf";
    NewWindowTarget = "Home";
    ShowHardDrivesOnDesktop = false;
    ShowExternalHardDrivesOnDesktop = true;
    ShowMountedServersOnDesktop = false;
    ShowPathbar = true;
    ShowRemovableMediaOnDesktop = true;
    ShowStatusBar = false;
  };

  system.defaults.screencapture = {
    location = "~/Desktop";
    type = "png";
  };

  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };

  system.defaults.trackpad = {
    Clicking = true;
    TrackpadRightClick = true;
  };

  system.defaults.loginwindow = {
    GuestEnabled = false;
  };

  system.defaults.NSGlobalDomain = {
    AppleShowAllExtensions = true;
    KeyRepeat = 2;
    InitialKeyRepeat = 15;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    # Two-finger swipe between pages.
    AppleEnableSwipeNavigateWithScrolls = true;
  };

  # Additional custom settings for macOS
  system.defaults.CustomUserPreferences = {
    NSGlobalDomain = {
      # Add a context menu item for showing the Web Inspector in web views
      WebKitDeveloperExtras = true;
      # Natural scrolling direction.
      "com.apple.swipescrolldirection" = true;
      # Disable Force Click; keep regular click+drag behavior.
      "com.apple.trackpad.forceClick" = false;
    };
    # Mission Control (3-finger swipe up), App Exposé (3-finger swipe down) and
    # switch between Spaces / full-screen apps (3-finger swipe left/right).
    # Horiz and four-finger are mutually exclusive, so four-finger horiz is off.
    # NB: enabling TrackpadThreeFingerDrag would disable the swipes above.
    "com.apple.AppleMultitouchTrackpad" = {
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadFourFingerHorizSwipeGesture = 0;
      TrackpadTwoFingerDoubleTapGesture = 1;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
    };
    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadFourFingerHorizSwipeGesture = 0;
      TrackpadTwoFingerDoubleTapGesture = 1;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
    };
    "com.apple.dock" = {
      showAppExposeGestureEnabled = true;
      showMissionControlGestureEnabled = true;
    };
    "com.apple.finder" = {
      # Open folders in tabs instead of new windows (not exposed as a typed
      # system.defaults.finder option in this nix-darwin version).
      FinderSpawnTab = true;
    };
    "com.apple.desktopservices" = {
      # Avoid creating .DS_Store files on network or USB volumes
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };
    "com.apple.loginwindow" = {
      # Don't reopen apps/windows after login. macOS saves the absolute
      # /nix/store path of running apps; every darwin-rebuild changes that
      # path, so resume relaunches a stale Emacs bundle whose packages no
      # longer load.
      TALLogoutSavesState = false;
    };
    "com.apple.Safari" = {
      # Privacy: don’t send search queries to Apple
      UniversalSearchEnabled = false;
      SuppressSearchSuggestions = true;
      # Press Tab to highlight each item on a web page
      WebKitTabToLinksPreferenceKey = true;
      ShowFullURLInSmartSearchField = true;
      # Prevent Safari from opening ‘safe’ files automatically after downloading
      AutoOpenSafeDownloads = false;
      ShowFavoritesBar = false;
      IncludeInternalDebugMenu = true;
      IncludeDevelopMenu = true;
      WebKitDeveloperExtrasEnabledPreferenceKey = true;
      WebContinuousSpellCheckingEnabled = true;
      WebAutomaticSpellingCorrectionEnabled = false;
      AutoFillFromAddressBook = false;
      AutoFillCreditCardData = false;
      AutoFillMiscellaneousForms = false;
      WarnAboutFraudulentWebsites = true;
      WebKitJavaEnabled = false;
      WebKitJavaScriptCanOpenWindowsAutomatically = false;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" = true;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = false;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" = false;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" = false;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" = false;
    };
    "com.apple.AdLib" = {
      allowApplePersonalizedAdvertising = false;
    };
    "com.apple.print.PrintingPrefs" = {
      # Automatically quit printer app once the print jobs complete
      "Quit When Finished" = true;
    };
    "com.apple.SoftwareUpdate" = {
      AutomaticCheckEnabled = true;
      # Check for software updates daily, not just once per week
      ScheduleFrequency = 1;
      # Download newly available updates in background
      AutomaticDownload = 1;
      # Install System data files & security updates
      CriticalUpdateInstall = 1;
    };
    "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
    # Prevent Photos from opening automatically when devices are plugged in
    "com.apple.ImageCapture".disableHotPlug = true;
    # Turn on app auto-update
    "com.apple.commerce".AutoUpdate = true;
  };
}
