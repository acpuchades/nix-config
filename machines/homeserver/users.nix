{ config, pkgs, ... }:
{

  # Ensure users are managed by Nix
  mutableUsers = false;

  # Groups
  groups.prefect = {};

  # Disable root login
  users.root.hashedPassword = "!";

  # User accounts
  users.alex = {
    isNormalUser = true;
    description = "Alejandro Caravaca Puchades";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];

    hashedPasswordFile = config.sops.secrets."passwd/alex".path;
    shell = pkgs.zsh;
  };
}
