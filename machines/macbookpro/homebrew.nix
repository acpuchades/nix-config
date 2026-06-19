{ ... }:
{
  enable = true;
  # Keep Homebrew updates out of the rebuild path: a `darwin-rebuild switch`
  # only installs missing casks, never updates Homebrew or upgrades existing
  # apps — so rebuilds stay deterministic. Upgrade deliberately instead:
  #   brew update && brew upgrade && brew cleanup
  onActivation.autoUpdate = false;
  onActivation.upgrade = false;
  onActivation.cleanup = "uninstall";
  # Homebrew ≥5.1 refuses `brew bundle --cleanup` non-interactively without an
  # explicit force flag; nix-darwin (pinned ~Feb 2026) doesn't pass one yet.
  # Drop this once the flake's nix-darwin input is new enough to handle it.
  onActivation.extraFlags = [ "--force-cleanup" ];

  taps = [ ];

  brews = [
    "mas"
  ];

  casks = [
    "adobe-acrobat-reader"
    "affinity"
    "alcove"
    "android-studio"
    "bartender"
    "bitwarden"
    "chromium"
    "claude"
    "cleanshot"
    "clop"
    "ledger-wallet"
    "libreoffice"
    "libreoffice-language-pack"
    "little-snitch"
    "localsend"
    "logi-options+"
    "macfuse"
    "micro-snitch"
    "microsoft-office"
    "microsoft-teams"
    "nextcloud"
    "obsidian"
    "pdf-expert"
    "proton-mail"
    "raycast"
    "signal"
    "spotify"
    "the-unarchiver"
    "utm"
    "veracrypt"
    "virtualbox"
    "whatsapp"
    "zen"
    "zoom"
    "zotero"
  ];

  masApps = {
    Amphetamine = 937984704;
    Dropover = 1355679052;
    HandMirror = 1502839586;
    Keynote = 361285480;
    Noir = 1592917505;
    Reeder = 6475002485;
    WireGuard = 1451685025;
  };
}
