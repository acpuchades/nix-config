{ pkgs, ... } :

{
	enable = true;
	onActivation.autoUpdate = true;
	onActivation.cleanup = "uninstall";
	onActivation.upgrade = true;

	taps = [];

	brews = [
		"gh"
		"mas"
	];

	casks = [
		"adobe-acrobat-reader"
		"affinity-designer"
		"affinity-photo"
		"affinity-publisher"
		"alcove"
		"bartender"
		"bitwarden"
		"blender"
		"chatgpt"
		"cleanshot"
		"clop"
		"ghostty"
		"google-chrome"
		"latest"
		"ledger-live"
		"logi-options+"
		"microsoft-office"
		"microsoft-teams"
		"notion"
		"obsidian"
		"pdf-expert"
		"raspberry-pi-imager"
		"raycast"
		"rectangle"
		"telegram"
		"the-unarchiver"
		"transmission"
		"unclack"
		"visual-studio-code"
		"whatsapp"
		"wireshark"
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
