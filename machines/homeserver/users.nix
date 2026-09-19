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

      # Declared (not just in ~/.ssh/authorized_keys) because sshd now refuses
      # passwords: the key must survive a home-directory loss or a fresh
      # provision, or SSH is locked out entirely.
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINToP7vyGXG7vrxR8W3T3I2NalZkc1IPd0WaETssf1X5 acaravacapuchades@icloud.com"
      ];
    };

    # eva's account is defined by modules/openclaw (which puts her in `agents`).
    # She is deliberately NOT in systemd-journal any more: the whole-box journal
    # carries auth, mail and web activity, far more than a prompt-injectable
    # agent needs. Unit-failure diagnosis goes through her sudo-granted
    # eva-journal wrapper instead (users/alex/agents/eva.nix), which reads only
    # the managed units' journals, pager-free.

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
