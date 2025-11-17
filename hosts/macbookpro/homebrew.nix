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
    "chatgpt-atlas"
    "cleanshot"
    "clop"
    "ghostty"
    "ledger-wallet"
    "logi-options+"
    "macfuse"
    "microsoft-office"
    "microsoft-teams"
    "obsidian"
    "omnissa-horizon-client"
    "pdf-expert"
    "telegram"
    "the-unarchiver"
    "transmission"
    "unclack"
    "veracrypt"
    "whatsapp"
    "zoom"
    "zotero"
  ];

  masApps = {
    Amphetamine = 937984704;
    Dropover = 1355679052;
    HandMirror = 1502839586;
    Meeter = 1510445899;
    Noir = 1592917505;
    Reeder = 6475002485;
    Things3 = 904280696;
    WireGuard = 1451685025;
  };
}
