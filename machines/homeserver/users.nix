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

        # Read-only inspection of the services alex administers, so the routine
        # "what is it doing?" checks don't cost a sudo password. The system
        # journal already needs nothing: journald ACLs /var/log/journal for
        # wheel, so `journalctl -u anything` works as-is.

        # The agent state tree (/var/lib/openclaw/<agent>, 0750 <agent>:openclaw).
        # modules/openclaw defines this group for exactly this: read an agent's
        # memory and sessions without becoming the agent.
        "openclaw"

        # /var/log/nginx (0750 nginx:nginx). Note this also covers the
        # /var/lib/acme/<domain> dirs that are group-nginx, so it grants read on
        # those certs' private keys too.
        "nginx"

        # The node's .cookie, so bitcoin-cli talks to bitcoind as alex. The
        # datadir is 0770, so this is read *and* write, not just the cookie.
        "bitcoind-main"
      ];

      hashedPasswordFile = config.sops.secrets."passwd/alex".path;
      shell = pkgs.zsh;
    };

    # eva's account is defined by modules/openclaw (which puts her in `agents`);
    # extraGroups merges with that. The journal files are 0640 root:systemd-journal,
    # so this is what lets her read the *system* journal rather than only her own
    # entries — enough to diagnose a unit-failure alert herself. It is a real
    # widening: that journal carries auth, mail and web activity for the whole box,
    # and she is a network-reachable LLM, so treat anything logged as readable by
    # her (and by whoever can talk to her).
    users.eva.extraGroups = [ "systemd-journal" ];

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
