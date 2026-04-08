{ ... }:
{
  enable = true;
  onActivation.autoUpdate = true;
  onActivation.cleanup = "uninstall";
  onActivation.upgrade = true;

  taps = [ ];

  brews = [
    "mas"
  ];

  casks = [
    "adobe-acrobat-reader"
    "affinity"
    "alcove"
    "bartender"
    "bitwarden"
    "chromium"
    "claude"
    "cleanshot"
    "clop"
    "ledger-wallet"
    "libreoffice"
    "libreoffice-language-pack"
    "logi-options+"
    "macfuse"
    "microsoft-office"
    "microsoft-teams"
    "obsidian"
    "omnissa-horizon-client"
    "pdf-expert"
    "raycast"
    "telegram"
    "the-unarchiver"
    "transmission"
    "utm"
    "veracrypt"
    "whatsapp"
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
