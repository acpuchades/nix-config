{ config, lib, pkgs, ... }:

let
  cfg = config.my.mail-server;

  # Custom rspamd rule (loaded via rspamd.local.lua) that stamps
  # `X-Trusted-Sender: yes` on inbound mail whose visible From is on
  # cfg.trustedSenders AND passes DMARC (so the From is cryptographically
  # authenticated, not spoofed). Any inbound copy of the header is stripped first
  # so a sender cannot forge it. It only MARKS mail — it never rejects or filters
  # delivery. See the trustedSenders option.
  trustedSenderLua = pkgs.writeText "rspamd-trusted-sender.lua" ''
    local lua_mime = require "lua_mime"

    local trusted = {
    ${lib.concatMapStrings (a: ''  ["${lib.toLower a}"] = true,
    '') cfg.trustedSenders}}

    rspamd_config:register_symbol({
      name = 'STAMP_X_TRUSTED_SENDER',
      type = 'postfilter',
      priority = 5,
      callback = function(task)
        local hdr = 'X-Trusted-Sender'
        local ok = false
        local from = task:get_from('mime')
        if from and from[1] and from[1].addr then
          local addr = tostring(from[1].addr):lower()
          if trusted[addr] and task:has_symbol('DMARC_POLICY_ALLOW') then
            ok = true
          end
        end
        -- Always strip any inbound copy of the header (anti-forgery); add ours
        -- only when the From is trusted AND DMARC-authenticated.
        if ok then
          lua_mime.modify_headers(task, {
            remove = { [hdr] = 0 },
            add = { [hdr] = { value = 'yes', order = 1 } },
          })
        else
          lua_mime.modify_headers(task, {
            remove = { [hdr] = 0 },
          })
        end
      end
    })
  '';
in
{
  options.my.mail-server = {
    enable = lib.mkEnableOption "self-hosted mail: inbound receive + Mailjet relay";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = ''
        Mail hostname / MX target. Also the CN of the inbound STARTTLS cert, so
        it must have a public A record (see ddclient) that tracks the dynamic IP.
      '';
      example = "mail.acpuchades.com";
    };

    origin = lib.mkOption {
      type = lib.types.str;
      description = "Mail origin domain ($myorigin), used for outbound envelope.";
      example = "acpuchades.com";
    };

    mailDomain = lib.mkOption {
      type = lib.types.str;
      description = ''
        Local mail domain. It's added to mydestination, so `<user>@mailDomain`
        delivers straight to the matching system user's ~/Maildir. Kept distinct
        from `origin` so the apex stays on Cloudflare Email Routing. Unknown
        local parts are rejected at SMTP time (no catch-all, no backscatter).
      '';
      example = "mail.acpuchades.com";
    };

    trustedSenders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "boss@example.com" ];
      description = ''
        Inbound senders to mark as VERIFIED-trusted. For each message whose visible
        `From:` is on this list AND that passes DMARC (so the `From:` is
        cryptographically authenticated — DKIM survives the Cloudflare forward for
        DKIM-signing providers), rspamd stamps an `X-Trusted-Sender: yes` header;
        any inbound copy of that header is stripped first, so a sender cannot forge
        it. This does NOT reject or filter delivery — every message is still
        delivered. It only MARKS who is verified, for a downstream consumer (e.g. an
        agent reading the mailbox) to decide whom it may act on. Matching is
        case-insensitive, exact address. A trusted address on a domain that does not
        pass DMARC is simply not stamped (treated as untrusted downstream —
        fail-safe). Empty (default) installs no rule.
      '';
    };

    relayHost = lib.mkOption {
      type = lib.types.str;
      description = "Outbound smarthost, e.g. [in-v3.mailjet.com]:587";
    };

    saslPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "texthash password file for the relay host (SASL).";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      default = "admin@acpuchades.com";
      description = "Contact email for the inbound-TLS ACME cert.";
    };

    acmeEnvironmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Environment file for the ACME dns-01 challenge, containing
        CLOUDFLARE_DNS_API_TOKEN=<token> (lego's var name — note it differs from
        Caddy's CLOUDFLARE_API_TOKEN).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Inbound STARTTLS certificate for the MX hostname, via Cloudflare dns-01.
    # security.acme drops a self-signed placeholder in place immediately, so
    # Postfix can start before the real cert is issued, then gets reloaded when
    # it arrives. Group is postfix so the smtpd can read the key.
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
      certs.${cfg.hostname} = {
        dnsProvider = "cloudflare";
        environmentFile = cfg.acmeEnvironmentFile;
        group = "postfix";
        reloadServices = [ "postfix.service" ];
      };
    };

    services.postfix = {
      enable = true;

      settings.main = {
        myhostname = cfg.hostname;
        myorigin = cfg.origin;
        mydomain = cfg.origin;

        # Receive on all interfaces (the router forwards WAN:25 here). IPv4 only:
        # no AAAA is published for the MX, so senders reach us over v4.
        inet_interfaces = "all";
        inet_protocols = "ipv4";

        # mailDomain is local: <user>@mailDomain delivers to that system user.
        # (mailDomain must NOT also be a virtual domain, or Postfix rewrites the
        # bare username to <user>@myorigin and relays it out — the apex isn't
        # local, so it would leave via the smarthost instead of being delivered.)
        mydestination = "localhost, localhost.localdomain, $myhostname, ${cfg.mailDomain}, ${config.networking.hostName}";
        home_mailbox = "Maildir/";

        # --- inbound TLS (opportunistic STARTTLS on :25) ---
        smtpd_tls_cert_file = "/var/lib/acme/${cfg.hostname}/fullchain.pem";
        smtpd_tls_key_file = "/var/lib/acme/${cfg.hostname}/key.pem";
        smtpd_tls_security_level = "may";
        smtpd_tls_loglevel = "1";

        # --- never an open relay; basic recipient hygiene ---
        smtpd_helo_required = "yes";
        smtpd_relay_restrictions =
          "permit_mynetworks permit_sasl_authenticated reject_unauth_destination";
        smtpd_recipient_restrictions =
          "permit_mynetworks reject_unauth_destination reject_unknown_recipient_domain reject_non_fqdn_recipient";

        # --- rspamd milter (inbound spam scoring) ---
        smtpd_milters = "inet:127.0.0.1:11332";
        non_smtpd_milters = "inet:127.0.0.1:11332";
        milter_default_action = "accept";
        milter_protocol = "6";

        # --- outbound: relay everything through the Mailjet smarthost ---
        # (this is what the old mail-relay module did; Mailjet signs DKIM.)
        relayhost = [ cfg.relayHost ];
        smtp_address_preference = "ipv4";
        smtp_tls_security_level = "encrypt";
        smtp_tls_loglevel = "1";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_password_maps = "texthash:${cfg.saslPasswordFile}";
        smtp_sasl_security_options = "noanonymous";
      };
    };

    # Inbound spam scoring. Minimal self-scanning milter proxy; no redis yet
    # (bayes/ratelimit can be added later by pointing rspamd at a redis).
    services.rspamd = {
      enable = true;
      # Load the trusted-sender stamping rule (only when a list is configured).
      localLuaRules = lib.mkIf (cfg.trustedSenders != [ ]) trustedSenderLua;
      workers.rspamd_proxy = {
        type = "rspamd_proxy";
        bindSockets = [ "127.0.0.1:11332" ];
        extraConfig = ''
          milter = yes;
          timeout = 120s;
          upstream "local" {
            default = yes;
            self_scan = yes;
          }
        '';
      };
      workers.controller = {
        type = "controller";
        bindSockets = [ "127.0.0.1:11334" ];
      };
    };

    # The router forwards external :25 here; open it on the host firewall.
    # Submission/IMAP stay off the network — eva is local and posts via sendmail.
    networking.firewall.allowedTCPPorts = [ 25 ];
  };
}
