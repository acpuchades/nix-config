# Declarative browser configuration (Zen).
#
# Zen (a Firefox fork, installed as a Homebrew cask) reads a user.js from each profile
# folder on startup and applies it over the GUI prefs. This module symlinks the
# Betterfox-derived better-zen user.js into each listed profile to harden privacy and
# security. Zen still owns profiles.ini and its own runtime state (workspaces/"Spaces"
# live in places.sqlite and are not declaratively manageable).
#
# `better-zen` is the flake input (refresh with `nix flake update better-zen`).
{ better-zen }:
{ lib, ... }:

let
  zenDir = "Library/Application Support/zen";
  userJs = "${better-zen}/better-zen/user.js";

  # Profile folders (relative to the zen config dir) to harden. Find a profile's path
  # in about:profiles; the prefix is randomised per profile. Edits to user.js prefs
  # made in the browser are overwritten on restart — change them upstream in better-zen.
  profilePaths = [
    "Profiles/h38enw8g.Default (release)"
  ];
in
{
  home.file = builtins.listToAttrs (map
    (p: lib.nameValuePair "${zenDir}/${p}/user.js" { source = userJs; })
    profilePaths);
}
