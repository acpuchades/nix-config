{ config, lib, pkgs, ... }:

let
  cfg = config.my.mail-server;

  # Custom rspamd rule (loaded via rspamd.local.lua) that stamps
  # `X-Trusted-Sender: yes` on inbound mail whose visible From is on
  # cfg.trustedSenders (or the trustedSendersFile map) AND carries a passing DKIM
  # signature aligned with the From domain. Any inbound copy of the header is
  # stripped first so a sender cannot forge it. It only MARKS mail — it never
  # rejects or filters delivery. See the trustedSenders option.
  #
  # DKIM, not "any DMARC pass": DMARC also passes on SPF alignment, and several
  # trusted domains authorise shared senders in SPF (Microsoft 365, newsletter
  # services), so anyone with an account there could pass as the owner. Legit
  # mail reaches eva through the Cloudflare forward, where SPF cannot align
  # anyway, so it already depends on DKIM.
  trustedSenderLua = pkgs.writeText "rspamd-trusted-sender.lua" ''
    local lua_mime = require "lua_mime"

    local trusted = {
    ${lib.concatMapStrings (a: ''  ["${lib.toLower a}"] = true,
    '') cfg.trustedSenders}}
    ${lib.optionalString (cfg.trustedSendersFile != null) ''
    local trusted_map = rspamd_config:add_map({
      type = 'set',
      url = '${cfg.trustedSendersFile}',
      description = 'trusted senders',
    })
    ''}
    local function is_trusted(addr)
      if trusted[addr] then return true end
      ${lib.optionalString (cfg.trustedSendersFile != null)
        "if trusted_map and trusted_map:get_key(addr) then return true end"}
      return false
    end

    -- Relaxed alignment: the signing domain is the From domain, a parent of
    -- it, or a subdomain of it.
    local function dkim_aligned(task, from_dom)
      for _, r in ipairs(task:get_dkim_results() or {}) do
        if r.result == 'allow' and r.domain then
          local d = r.domain:lower()
          if d == from_dom
            or from_dom:sub(-(#d + 1)) == '.' .. d
            or d:sub(-(#from_dom + 1)) == '.' .. from_dom then
            return true
          end
        end
      end
      return false
    end

    rspamd_config:register_symbol({
      name = 'STAMP_X_TRUSTED_SENDER',
      type = 'postfilter',
      priority = 5,
      callback = function(task)
        local hdr = 'X-Trusted-Sender'
        local ok = false
        local from = task:get_from('mime')
        if from and from[1] and from[1].addr and from[1].domain then
          local addr = tostring(from[1].addr):lower()
          local dom = tostring(from[1].domain):lower()
          if is_trusted(addr) and task:has_symbol('DMARC_POLICY_ALLOW')
            and dkim_aligned(task, dom) then
            ok = true
          end
        end
        -- Always strip any inbound copy of the header (anti-forgery); add ours
        -- only when the From is trusted AND DKIM-authenticated.
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
        `From:` is on this list AND that passes DMARC with an aligned DKIM signature
        (so the `From:` is cryptographically authenticated — DKIM survives the
        Cloudflare forward), rspamd stamps an `X-Trusted-Sender: yes` header;
        any inbound copy of that header is stripped first, so a sender cannot forge
        it. This does NOT reject or filter delivery — every message is still
        delivered. It only MARKS who is verified, for a downstream consumer (e.g. an
        agent reading the mailbox) to decide whom it may act on. Matching is
        case-insensitive, exact address. A trusted address on a domain that does not
        pass DMARC is simply not stamped (treated as untrusted downstream —
        fail-safe). Empty (default) installs no rule.
      '';
    };

    trustedSendersFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/rspamd/trusted-senders";
      description = ''
        Runtime file adding to trustedSenders, one lowercase address per line
        (rspamd `set` map, re-read on change), so the addresses stay out of the
        store and the repo. Must be readable by the rspamd user.
      '';
    };

    localRecipients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "eva" ];
      description = ''
        Local parts accepted from the network (plus the alias table). Empty keeps
        Postfix's default of every account in passwd, which makes every service
        user a mailbox that anyone on the internet can fill.
      '';
    };

    deniedSubmitUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "eva" ];
      description = ''
        Local accounts refused mail submission through sendmail(1)/postdrop
        (authorized_submit_users). With SMTP to localhost blocked for them too,
        such an account can only send through whatever wrapper runs as another
        user — an agent's recipient-checking submit account, for instance.
      '';
    };

    pinnedSenders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = { eva = [ "e.nebot@example.com" ]; };
      description = ''
        Envelope senders each local login may use with sendmail(1) -f
        (local_login_sender_maps). Logins not listed keep the default of any
        sender. Stops a compromised local user from relaying through the
        smarthost as another address of the domain.
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
      description = "Contact email for the inbound-TLS ACME cert (unused when acmeCertName is set).";
    };

    acmeEnvironmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file for the ACME dns-01 challenge, containing
        CLOUDFLARE_DNS_API_TOKEN=<token> (lego's var name — note it differs from
        Caddy's CLOUDFLARE_API_TOKEN). Required when acmeCertName is null.
      '';
    };

    acmeCertName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of an existing security.acme.certs entry to use for Postfix STARTTLS.
        When set, the module will not request its own ACME certificate; the named
        entry must already configure group = "postfix" and include postfix.service
        in reloadServices. When null (default), the module manages its own cert
        for cfg.hostname using acmeEnvironmentFile.
      '';
    };
  };

  config =
    let
      certName = if cfg.acmeCertName != null then cfg.acmeCertName else cfg.hostname;
    in
    lib.mkIf cfg.enable {
    # Inbound STARTTLS certificate — managed here only when acmeCertName is not set.
    # When acmeCertName points to an existing security.acme.certs entry (e.g. a
    # wildcard cert), that entry must already grant group = "postfix" and reload
    # postfix.service on renewal.
    security.acme = lib.mkIf (cfg.acmeCertName == null) {
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
      } // lib.optionalAttrs (cfg.localRecipients != [ ]) {
        local_recipient_maps = "inline:{ ${lib.concatMapStringsSep ", " (u: "${u}=ok") cfg.localRecipients} } $alias_maps";
      } // lib.optionalAttrs (cfg.deniedSubmitUsers != [ ]) {
        authorized_submit_users = lib.concatMapStringsSep ", " (u: "!${u}") cfg.deniedSubmitUsers + ", static:all";
      } // lib.optionalAttrs (cfg.pinnedSenders != { }) {
        local_login_sender_maps = "inline:{ ${lib.concatStringsSep ", " (lib.mapAttrsToList (u: ss: "${u}=${lib.concatStringsSep " " ss}") cfg.pinnedSenders)} }, static:*";
      } // {

        # --- inbound TLS (opportunistic STARTTLS on :25) ---
        smtpd_tls_cert_file = "/var/lib/acme/${certName}/fullchain.pem";
        smtpd_tls_key_file = "/var/lib/acme/${certName}/key.pem";
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
        # tempfail, not accept: rspamd is what strips a forged X-Trusted-Sender,
        # so while it is down (every restart) mail must wait, not bypass it.
        milter_default_action = "tempfail";
        milter_protocol = "6";
        # And strip it here too, independently of rspamd: cleanup drops the
        # client's copy, while the one rspamd adds afterwards is not re-checked.
        header_checks = "regexp:${pkgs.writeText "header_checks" "/^X-Trusted-Sender:/ IGNORE\n"}";

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
      localLuaRules = lib.mkIf (cfg.trustedSenders != [ ] || cfg.trustedSendersFile != null) trustedSenderLua;
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
