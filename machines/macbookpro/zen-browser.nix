{ pkgs, lib, ... }:

let
  extensionsOverlay = pkgs.writeText "zen-browser-extensions-overlay.json" (builtins.toJSON {
    policies = {
      ExtensionSettings = {
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "force_installed";
        };
        "zotero@chnm.gmu.edu" = {
          install_url = "https://www.zotero.org/download/connector/dl?browser=firefox";
          installation_mode = "force_installed";
        };
        "addon@simplelogin" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/simplelogin/latest.xpi";
          installation_mode = "force_installed";
        };
        "floccus@handmadeideas.org" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/floccus/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };
  });
in
{
  homebrew.casks = [ "zen-browser" ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    app="/Applications/Zen.app"
    if [ ! -d "$app" ]; then
      exit 0
    fi

    /usr/bin/xattr -cr "$app" 2>/dev/null || true

    distDir="$app/Contents/Resources/distribution"
    policies="$distDir/policies.json"
    upstream="$distDir/policies.upstream.json"

    /bin/mkdir -p "$distDir"

    # Refresh the upstream backup if the live file looks like a fresh cask
    # install (i.e. doesn't carry our overlay's marker extension).
    if [ -f "$policies" ] && ! /usr/bin/grep -q '446900e4-71c2-419f-a6a7-df9c091e268b' "$policies"; then
      /bin/cp "$policies" "$upstream"
    fi

    if [ ! -f "$upstream" ]; then
      echo '{}' > "$upstream"
    fi

    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$upstream" ${extensionsOverlay} > "$policies.tmp"
    /bin/mv "$policies.tmp" "$policies"
  '';
}
