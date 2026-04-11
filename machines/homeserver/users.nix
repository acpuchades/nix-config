{ config, pkgs, ... }:
let

  nitrokeySshPublicKey = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOsBCI8pMjSqQFPxJsyFWBrKxo2scz9zLhCyJKKiBJZFAAAABHNzaDo= acpuchades-nitrokey-20260225";

in {

  # Ensure users are managed by Nix
  mutableUsers = false;

  # Groups
  groups.fugazi = {};
  groups.prefect = {};

  # Disable root login
  users.root.hashedPassword = "!";

  # System accounts
  users.fugazi = {
    group = "fugazi";
    createHome = false;
    isSystemUser = true;
    home = "/srv/fugazi";
  };

  # User accounts
  users.alex = {
    isNormalUser = true;
    description = "Alejandro Caravaca Puchades";
    extraGroups = [
      "wheel"
      "networkmanager"
      "fugazi"
    ];

    hashedPasswordFile = config.sops.secrets."passwd/alex".path;
    shell = pkgs.zsh;

    openssh.authorizedKeys.keys = [
      nitrokeySshPublicKey
    ];
  };
}
