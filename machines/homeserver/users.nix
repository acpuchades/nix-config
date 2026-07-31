{ config, pkgs, ... }:
{
  users = {

    # Ensure users are managed by Nix
    mutableUsers = false;

    # Groups
    groups.prefect = {};
    groups.share = {}; # members get read/write on the Samba file share

    # Owns /var/www/acpuchades.com. The site's GitHub Actions runner
    # (services.github-runners.acpuchades-site) runs as this user and rsyncs the
    # built tree into the web root; alex is a member so a manual `make deploy`
    # over ssh still works against the same directory.
    groups.acpuchades-site = {};

    # Disable root login
    users.root.hashedPassword = "!";

    # User accounts
    users.alex = {
      isNormalUser = true;
      description = "Alejandro Caravaca Puchades";
      extraGroups = [
        "wheel"
        "networkmanager"
        "share"
        "acpuchades-site"
      ];

      hashedPasswordFile = config.sops.secrets."passwd/alex".path;
      shell = pkgs.zsh;
    };

    # Service account for the site's GitHub Actions runner. Pinned rather than
    # left to the module's DynamicUser because the web root needs a stable owner
    # that both the runner and (via the group) alex can write to.
    users.acpuchades-site = {
      isSystemUser = true;
      group = "acpuchades-site";
      description = "GitHub Actions runner for acpuchades-site";
    };
  };
}
