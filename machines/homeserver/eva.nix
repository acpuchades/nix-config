# eva — the OpenClaw agent (agents/eva) and the mail server that is her inbox,
# with the wildcard certificate Postfix uses for STARTTLS.
{ config, pkgsUnstable, ... }:
{
  imports = [
    ../../agents/eva
    ../../modules/mail-server
  ];

  # OpenClaw agent — Telegram-only, loopback gateway, but NOT confined on
  # the host side (no sandbox/grants; see the module header).
  # Needs these two SOPS secrets populated (declared in sops.nix):
  #   sops machines/homeserver/secrets/default.yml
  #     openclaw/eva/telegram-token, openclaw/eva/telegram-userid
  # Auth is the Claude subscription via the Claude CLI runtime — log in once:
  #   sudo -u eva -H claude            # /login, then quit
  # OpenClaw from nixpkgs-unstable (2026.6.33), NOT nixpkgs-26.05's 2026.5.7.
  # Why: 2026.5.7's claude-cli runtime has no handler for Claude Code's
  # permission protocol (control_request/can_use_tool), so a non-allowlisted
  # command hangs ~180s then dies with no Telegram prompt. 2026.6.33 adds the
  # responder (claude-live-session answers can_use_tool → allow under YOLO
  # else a clean deny) AND fixes the bundled-surface hardlink guard upstream
  # (plugin loaders now pass rejectHardlinks:false). Taken from the shared
  # `pkgsUnstable` instance in ./default.nix, whose insecure permit is
  # this package's (openclaw is marked knownVulnerabilities upstream) and is
  # version-agnostic, so it survives unstable's openclaw bumps without
  # editing a version string.
  my.openclaw = {
    # SHARED across all agent instances — the one OpenClaw build they all run.
    package = pkgsUnstable.openclaw;

    # Agents deployed on this host: each is its own module under agents/,
    # imported above (eva: Telegram bot eva_lebbot, own OS user, home,
    # state dir /var/lib/openclaw/eva and openclaw-eva.service). Only
    # `package` is shared between them.
  };

  # Wildcard cert for *.acpuchades.com, shared by Postfix (mail STARTTLS) and
  # any other service that needs a NixOS-managed cert for this domain.
  # Caddy manages its own certs independently via the acme-cloudflare module.
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@acpuchades.com";
    certs."acpuchades.com" = {
      extraDomainNames = [ "*.acpuchades.com" ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme/cloudflare-env".path;
      group = "postfix";
      reloadServices = [ "postfix.service" ];
      # This host's own resolver (AdGuard, 127.0.0.1) split-horizons
      # acpuchades.com to the LAN IP and returns no SOA for the apex, which
      # breaks lego's DNS-01 zone-walk ("cloudflare: failed to find zone com.").
      # Point lego at a public resolver so zone detection + propagation checks
      # see the real Cloudflare SOA instead of the local rewrite.
      dnsResolver = "1.1.1.1:53";
    };
  };

  my.mail-server = {
    enable = true;
    hostname = "m.acpuchades.com";
    origin = "acpuchades.com";
    # eva's public address is eva@m.acpuchades.com itself (no apex alias in
    # front): mailDomain being local, it delivers straight to the eva system
    # user's ~/Maildir.
    mailDomain = "m.acpuchades.com";
    # rspamd stamps `X-Trusted-Sender: yes` on inbound mail whose From is one
    # of these AND carries an aligned DKIM signature (spoof-proof). eva keys
    # "may act on this mail" off that header, not the raw From. The SAME sops
    # value as eva's trusted-recipient list (agents/eva), so trust stays
    # symmetric in both directions without a second copy to drift.
    trustedSendersFile = config.sops.secrets."rspamd/trusted-senders".path;
    # eva is the only mailbox; everything else at mailDomain is refused at
    # SMTP time. She cannot submit mail herself — only through her send
    # wrappers, which run as eva-mail (pinned to her address) and hold mail
    # for anyone but the owner.
    localRecipients = [ "eva" ];
    deniedSubmitUsers = [ "eva" ];
    pinnedSenders.eva-mail = [ config.my.openclaw.instances.eva.mail.fromAddress ];
    relayHost = "[in-v3.mailjet.com]:587";
    saslPasswordFile = config.sops.templates."postfix/sasl_passwd".path;
    # Use the shared wildcard cert instead of managing a per-hostname cert.
    acmeCertName = "acpuchades.com";
  };
}
