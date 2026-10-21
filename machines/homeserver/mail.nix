# Outbound mail: every service on this host (Nextcloud, Immich, Vaultwarden,
# Home Assistant, titan, fugazi) and eva's broker wrappers hand mail to the
# local Postfix, which relays it through Migadu. Nothing is received here:
# m.acpuchades.com's MX is Migadu, and eva reads her mailbox over IMAP.
{ config, ... }:
{
  imports = [ ../../modules/mail-server ];

  # Loopback STARTTLS uses the *.acpuchades.com wildcard my.web-server issues
  # (./web.nix). Postfix loads the key as root, so its group does not matter.
  security.acme.certs."acpuchades.com".reloadServices = [ "postfix.service" ];

  my.mail-server = {
    enable = true;
    # The name fugazi's backend STARTTLSes to (mapped to 127.0.0.1 there,
    # matched against the wildcard).
    hostname = "m.acpuchades.com";
    origin = "acpuchades.com";
    acmeCertName = "acpuchades.com";

    # Migadu hosts m.acpuchades.com's sending (SPF/DKIM) and relays only a
    # From that the logged-in mailbox owns, so Postfix logs in per sender:
    # noreply@ for the services, eva@ for eva (postfix/sasl_passwd in
    # ./sops.nix). Everything local sends as @m.acpuchades.com; the apex is
    # Proton's and Migadu cannot sign for it.
    relayHost = "[smtp.migadu.com]:587";
    senderDependentAuth = true;
    saslPasswordFile = config.sops.templates."postfix/sasl_passwd".path;

    # eva cannot submit mail herself — only through her broker wrappers, which
    # run as openclaw-secrets, are pinned to her address, and hold mail for
    # anyone but the owner.
    deniedSubmitUsers = [ "eva" ];
    pinnedSenders.openclaw-secrets = [ config.my.openclaw.instances.eva.mail.fromAddress ];
  };
}
