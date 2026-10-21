{
  config,
  lib,
  ...
}:

# Local mail submission, relayed out through an authenticated smarthost.
#
# Send-only: nothing is received from the network. Mailboxes live at the
# provider (the agent reads its own over IMAP, see modules/openclaw), so
# Postfix listens on loopback alone — where the host's services hand it mail
# over SMTP, with STARTTLS for those that insist on a verified certificate —
# and delivers everything to `relayHost`.
let
  cfg = config.my.mail-server;
in
{
  options.my.mail-server = {
    enable = lib.mkEnableOption "local mail submission relayed through a smarthost";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = ''
        $myhostname, and the name local clients STARTTLS to: it must match the
        certificate (see acmeCertName), so map it to 127.0.0.1 for clients that
        verify it.
      '';
      example = "m.acpuchades.com";
    };

    origin = lib.mkOption {
      type = lib.types.str;
      description = "Mail origin domain ($myorigin), for bare local senders.";
      example = "acpuchades.com";
    };

    deniedSubmitUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "eva" ];
      description = ''
        Local accounts refused mail submission through sendmail(1)/postdrop
        (authorized_submit_users). With SMTP to localhost blocked for them too,
        such an account can only send through whatever wrapper runs as another
        user — an agent's recipient-checking broker wrappers, for instance.
      '';
    };

    pinnedSenders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        openclaw-secrets = [ "agent@example.com" ];
      };
      description = ''
        Envelope senders each local login may use with sendmail(1) -f
        (local_login_sender_maps). Logins not listed keep the default of any
        sender. Stops a compromised local user from relaying through the
        smarthost as another address.
      '';
    };

    relayHost = lib.mkOption {
      type = lib.types.str;
      description = "Outbound smarthost, e.g. [smtp.migadu.com]:587 (STARTTLS required).";
    };

    saslPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        texthash SASL password map for the smarthost. With senderDependentAuth,
        keyed by envelope sender (`addr login:password`) with a `relayHost`
        line as the fallback.
      '';
    };

    senderDependentAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Log in to the smarthost as a different account per envelope sender
        (smtp_sender_dependent_authentication), for providers that only relay
        a From the logged-in mailbox owns.
      '';
    };

    acmeCertName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Existing security.acme.certs entry used for the loopback STARTTLS. It
        must cover `hostname` and include postfix.service in reloadServices
        (its group does not matter: Postfix reads the key as root).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.postfix = {
      enable = true;

      settings.main = {
        myhostname = cfg.hostname;
        myorigin = cfg.origin;
        mydomain = cfg.origin;

        # Loopback only: there is nothing to receive from the network.
        inet_interfaces = "loopback-only";
        inet_protocols = "ipv4";
        mynetworks = [ "127.0.0.0/8" ];
        # Nothing is local but root's own mail: every address, the hostname's
        # included, goes out through the smarthost.
        mydestination = "localhost, localhost.localdomain";

        # Loopback STARTTLS, for local clients that require it.
        smtpd_tls_cert_file = "/var/lib/acme/${cfg.acmeCertName}/fullchain.pem";
        smtpd_tls_key_file = "/var/lib/acme/${cfg.acmeCertName}/key.pem";
        smtpd_tls_security_level = "may";
        smtpd_relay_restrictions = "permit_mynetworks reject";

        # Everything out through the smarthost, encrypted and authenticated.
        relayhost = [ cfg.relayHost ];
        smtp_tls_security_level = "encrypt";
        smtp_tls_loglevel = "1";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_password_maps = "texthash:${cfg.saslPasswordFile}";
        smtp_sasl_security_options = "noanonymous";
      }
      // lib.optionalAttrs cfg.senderDependentAuth {
        smtp_sender_dependent_authentication = "yes";
      }
      // lib.optionalAttrs (cfg.deniedSubmitUsers != [ ]) {
        authorized_submit_users =
          lib.concatMapStringsSep ", " (u: "!${u}") cfg.deniedSubmitUsers + ", static:all";
      }
      // lib.optionalAttrs (cfg.pinnedSenders != { }) {
        local_login_sender_maps = "inline:{ ${
          lib.concatStringsSep ", " (
            lib.mapAttrsToList (u: ss: "${u}=${lib.concatStringsSep " " ss}") cfg.pinnedSenders
          )
        } }, static:*";
      };
    };
  };
}
