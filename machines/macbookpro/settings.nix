{ pkgs, ... }:
{
  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Allow installation of not-free software
  nixpkgs.config.allowUnfree = true;

  # Enable the touch ID authentication for sudo.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Load settings without requiring a logout/login cycle.
  system.activationScripts.postUserActivation.text = ''
    # Following line should allow us to avoid a logout/login cycle
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  system.defaults.dock = {
    autohide = true;
    autohide-delay = 0.0;
    autohide-time-modifier = 0.5;
    expose-animation-duration = 0.5;

    show-recents = false;
    magnification = false;
    tilesize = 64;

    wvous-bl-corner = 11;
    wvous-br-corner = 13;

    persistent-apps = [
      { app = "/System/Applications/Safari.app"; }
      { app = "/System/Applications/Messages.app"; }
      { app = "/System/Applications/Mail.app"; }
      { app = "/Applications/WhatsApp.app"; }
      { app = "${pkgs.chatgpt}/Applications/ChatGPT.app"; }
      { app = "/System/Applications/Photos.app"; }
      { app = "/System/Applications/Calendar.app"; }
      { app = "/Applications/Things3.app"; }
      { app = "/System/Applications/Notes.app"; }
      { app = "/System/Applications/Music.app"; }
      { app = "/Applications/Keynote.app"; }
      { app = "/Applications/Numbers.app"; }
      { app = "/Applications/Pages.app"; }
      { app = "${pkgs.zed-editor}/Applications/Zed.app"; }
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
    ShowMountedServersOnDesktop = true;
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

  # Additional custom settings for macOS
  system.defaults.CustomUserPreferences = {
    NSGlobalDomain = {
      # Add a context menu item for showing the Web Inspector in web views
      WebKitDeveloperExtras = true;
    };
    "com.apple.desktopservices" = {
      # Avoid creating .DS_Store files on network or USB volumes
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
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
