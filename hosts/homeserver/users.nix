{ config, pkgs, ... }:
{
  # Ensure users are managed by Nix
  mutableUsers = false;

  # Disable root login
  users.root.hashedPassword = "!";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.alex = {
    isNormalUser = true;
    description = "Alejandro Caravaca Puchades";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "networkmanager"
    ];

    hashedPasswordFile = config.sops.secrets."user/password".path;
    shell = pkgs.zsh;

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINToP7vyGXG7vrxR8W3T3I2NalZkc1IPd0WaETssf1X5 alex@macbookpro"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGInkVDbDTNXoUs27tUFuU1sFRRKzZQh1hc0aFyW6xMtyK9olt0lgFGvi1TauS4twSPf4a5UeDLtrkNxSahIAqc= alex@iphone"
    ];
  };
}
