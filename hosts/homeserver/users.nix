{ config, pkgs, ... }:
{
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

  users.prefect = {
    group = "prefect";
    createHome = false;
    isSystemUser = true;
    home = "/var/lib/prefect-server";
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINToP7vyGXG7vrxR8W3T3I2NalZkc1IPd0WaETssf1X5 alex@macbookpro"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGInkVDbDTNXoUs27tUFuU1sFRRKzZQh1hc0aFyW6xMtyK9olt0lgFGvi1TauS4twSPf4a5UeDLtrkNxSahIAqc= alex@iphone"
    ];
  };
}
