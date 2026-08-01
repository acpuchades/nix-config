{ config, ... }:
{
  sops = {
    defaultSopsFile = ./secrets/default.yml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {

      "mailjet/token" = { key = "mailjet/token"; };
      "mailjet/secret" = { key = "mailjet/secret"; };

      "nextcloud/admin" = {
        owner = config.users.users.nextcloud.name;
        group = config.users.users.nextcloud.group;
      };

      "cloudflare/account" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };

      "cloudflare/token" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };

      "caddy/adguard" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };

      "caddy/prefect" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };

      "umami/app-secret" = {
        key = "umami/app-secret";
        mode = "0400";
      };

      # Grafana DB encryption key (services.grafana.settings.security.secret_key).
      # Read at runtime via Grafana's $__file{} provider, so it must be owned by
      # the grafana user. Generate with: openssl rand -base64 24
      "grafana/secret-key" = {
        owner = "grafana";
        group = "grafana";
        mode = "0400";
      };

      # Shared token for grafana-image-renderer. Rendered into the
      # grafana/renderer-env template below in both AUTH_TOKEN /
      # GF_RENDERING_RENDERER_TOKEN forms. Generate with: openssl rand -hex 32
      "grafana/renderer-token" = {
        owner = "grafana";
        group = "grafana";
        mode = "0400";
      };

      # Registration token (or a PAT) for the acpuchades-site self-hosted
      # Actions runner, consumed by services.github-runners.acpuchades-site.
      # Only the root-run ExecStartPre reads it, so root:root 0400 is correct.
      # Get a registration token from the repo's Settings → Actions → Runners →
      # New self-hosted runner (it expires in ~1h, but is only needed at the
      # first registration; the module then persists the runner credentials).
      "github-runner/acpuchades-site" = { mode = "0400"; };

      "passwd/alex" = {
        key = "passwd/alex";
        neededForUsers = true;
      };

      "wireguard/private-key" = { key = "wireguard/private-key"; };

      "wireguard-client/wgproton" = { key = "wireguard-client/wgproton"; };

      "wireguard-client/wgproton-bt" = { key = "wireguard-client/wgproton-bt"; };

      # htpasswd hash for the torrent.acpuchades.com basic-auth (rendered into the
      # caddy/torrent-auth template). Generate with: caddy hash-password
      "caddy/torrent" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };

      # Per-peer preshared keys for wg0 (declarative peers in my.vpn-server.peers)
      "wireguard/psk/alex-laptop" = { mode = "0400"; };
      "wireguard/psk/alex-ipad" = { mode = "0400"; };
      "wireguard/psk/alex-phone-owner" = { mode = "0400"; };
      "wireguard/psk/alex-phone-personal" = { mode = "0400"; };
      "wireguard/psk/alex-phone-work" = { mode = "0400"; };
      "wireguard/psk/mubin-laptop-personal" = { mode = "0400"; };
      "wireguard/psk/mubin-laptop-work" = { mode = "0400"; };
      "wireguard/psk/mubin-phone-personal" = { mode = "0400"; };
      "wireguard/psk/mubin-phone-work" = { mode = "0400"; };

      "nut/monitor" = {
        mode = "0400";
      };

      "wifi/network" = { key = "wifi/network"; };
      "wifi/password" = { key = "wifi/password"; };

      # restic backup: repository password + Backblaze B2 credentials. Read at
      # runtime by the restic-backups-homeserver service, which runs as root, so
      # default ownership (root 0400) is correct. The repo password ALSO lives
      # off this server (it is the only thing that decrypts the snapshots).
      #   Generate the password with: head -c 36 /dev/urandom | base64
      "backup/restic-password" = { mode = "0400"; };
      # From the Backblaze B2 Application Key you create for the backup bucket.
      "backup/b2-account-id" = { mode = "0400"; };   # keyID
      "backup/b2-account-key" = { mode = "0400"; };  # applicationKey
      # Shared HOMESERVER ntfy publisher token (Bearer auth), reused by every
      # local alert source: the restic backup, my.ntfy-alert's unit-failure
      # notifier, and the UPS NOTIFYCMD. Rendered into ntfy/env below and injected
      # as NTFY_TOKEN. Topics are separated at the ACL/topic level, not by token.
      # Provision one ntfy user with write to the relevant topics:
      #   sudo <ntfy-sh>/bin/ntfy user add --role=user homeserver
      #   sudo <ntfy-sh>/bin/ntfy access homeserver "alerts-*" write-only
      #   sudo <ntfy-sh>/bin/ntfy token add homeserver
      "ntfy/token" = { mode = "0400"; };

      # One SMB password per user (nested samba/<user> branch). Add a line here
      # for each additional user, then store the value with:
      #   sops machines/homeserver/secrets/default.yml
      "samba/alex" = { mode = "0400"; };

      # Agent-IDENTITY secrets (the Telegram bot token + allowlisted ID) go under
      # openclaw/<agent>/ — each agent is its OWN bot, so a second agent is added
      # as a sibling openclaw/<name>/ subtree. The shared SERVICE API keys are NOT
      # under openclaw: they keep their own service namespaces (anthropic/,
      # elevenlabs/, google/, openweather/, 2captcha/), so any agent references the
      # same key. `/` in a name maps to a NESTED YAML key.
      #
      # ACCESS follows that same split, and NO shared key names an agent:
      #   * IDENTITY secrets are chowned to the single agent they belong to (or
      #     stay root-owned when systemd reads them as a credential);
      #   * SERVICE keys are `group = "agents"; mode = "0440";` — the group the
      #     openclaw module puts every agent user in — so adding a second agent
      #     grants it the same keys with no edit here. (Not the `openclaw` group:
      #     that one reads the state tree, i.e. each agent's memory and sessions.)

      # eva's Telegram identity, consumed as files by
      # my.openclaw.instances.eva.telegram.{tokenFile,allowedIdFile}. The token is
      # read by systemd LoadCredential (as root), so default ownership is fine; the
      # allowed-ID file is read by the ExecStartPre seed (runs AS eva), so it must
      # be eva-readable.
      "openclaw/eva/telegram-token" = { mode = "0400"; };
      "openclaw/eva/telegram-userid" = {
        owner = "eva";
        mode = "0400";
      };

      # ElevenLabs API key for reply TTS, rendered into openclaw/elevenlabs-env
      # below and read by the openclaw service as ELEVENLABS_API_KEY.
      "elevenlabs/token" = {
        group = "agents";
        mode = "0440";
      };

      # Anthropic API key. CURRENTLY UNUSED — the claude-cli runtime authenticates
      # via the Claude subscription login, not an API key — kept for an easy switch
      # back to native/API auth. Rendered into openclaw/anthropic-env below.
      "anthropic/token" = {
        group = "agents";
        mode = "0440";
      };

      # Gemini API key for the generate-image action
      # (my.openclaw.instances.<agent>.actions.generateImage.tokenFile), read at
      # RUNTIME by the generate-image wrapper (runs AS the agent).
      "google/gemini-token" = {
        group = "agents";
        mode = "0440";
      };

      # OpenWeatherMap API key for the check-weather action
      # (my.openclaw.instances.<agent>.actions.checkWeather.tokenFile), read at
      # RUNTIME by the check-weather wrapper (runs AS the agent).
      "openweather/token" = {
        group = "agents";
        mode = "0440";
      };

      # 2Captcha API key for the solve-captcha action
      # (my.openclaw.instances.<agent>.actions.solveCaptcha.tokenFile), read at
      # RUNTIME by the solve-captcha wrapper (runs AS the agent). This one bills per
      # solve, so it is also the account whose balance `solve-captcha balance`
      # reports — shared credit, so every agent on it spends the same pot.
      "2captcha/token" = {
        group = "agents";
        mode = "0440";
      };

      # Zotero API key for the zotero-add action
      # (my.openclaw.instances.<agent>.actions.zoteroAdd.tokenFile), read at RUNTIME
      # by the zotero-add wrapper (runs AS the agent). It must be a key with WRITE
      # access to the library; the library itself is resolved from this key, so it is
      # the only thing that has to be supplied. The same key is what an agent uses
      # for Zotero READS through request-trusted-url (`?key=` query param), so it
      # also belongs in that agent's TOOLS.md — reads and writes are the same
      # credential, reached two different ways. Create it at
      # https://www.zotero.org/settings/keys.
      "zotero/token" = {
        group = "agents";
        mode = "0440";
      };

    };

    templates = {

      "caddy/cloudflare-env" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
        content = ''
          CLOUDFLARE_API_TOKEN=${config.sops.placeholder."cloudflare/token"}
        '';
      };

      # ACME dns-01 for the mail-server's inbound TLS cert. lego reads
      # CLOUDFLARE_DNS_API_TOKEN (note: different var name than Caddy's above),
      # but it's the same underlying Cloudflare token.
      "acme/cloudflare-env" = {
        owner = "acme";
        group = "acme";
        mode = "0400";
        content = ''
          CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."cloudflare/token"}
        '';
      };

      "caddy/adguard-auth" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
        content = ''
          basic_auth {
            admin ${config.sops.placeholder."caddy/adguard"}
          }
        '';
      };

      "caddy/prefect-auth" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
        content = ''
          basic_auth {
            admin ${config.sops.placeholder."caddy/prefect"}
          }
        '';
      };

      "caddy/torrent-auth" = {
        owner = "caddy";
        group = "caddy";
        mode = "0400";
        content = ''
          basic_auth {
            admin ${config.sops.placeholder."caddy/torrent"}
          }
        '';
      };

      "ddclient/config".content = ''
          cache=/var/cache/ddclient/ddclient.cache
          usev4=webv4, webv4=checkip.amazonaws.com
          protocol=cloudflare
          zone=acpuchades.com
          ttl=120
          login=token
          password=${config.sops.placeholder."cloudflare/token"}
          acpuchades.com,analytics.acpuchades.com,blog.acpuchades.com,gps.acpuchades.com,mail.acpuchades.com,vpn.acpuchades.com,www.acpuchades.com
      '';

      "postfix/sasl_passwd" = {
        owner = "postfix";
        group = "postfix";
        mode = "0400";
        content = ''
          [in-v3.mailjet.com]:587 ${config.sops.placeholder."mailjet/token"}:${config.sops.placeholder."mailjet/secret"}
        '';
      };

      "wifi/secrets" = {
        owner = "wpa_supplicant";
        group = "wpa_supplicant";
        mode = "0400";
        content = ''
          home-wlan-psk=${config.sops.placeholder."wifi/password"}
        '';
      };

      # NTFY_TOKEN for the homeserver alert publishers (my.ntfy-alert failure
      # notifier + the UPS NOTIFYCMD). Loaded as a systemd EnvironmentFile as
      # root, then inherited by forked notify commands.
      "ntfy/env" = {
        mode = "0400";
        content = ''
          NTFY_TOKEN=${config.sops.placeholder."ntfy/token"}
        '';
      };

      # Environment file consumed by restic (services.restic.backups.homeserver
      # environmentFile). restic's native B2 backend reads these two variables.
      "backup/b2-env" = {
        mode = "0400";
        content = ''
          B2_ACCOUNT_ID=${config.sops.placeholder."backup/b2-account-id"}
          B2_ACCOUNT_KEY=${config.sops.placeholder."backup/b2-account-key"}
        '';
      };

      "grafana/renderer-env" = {
        owner = "grafana";
        group = "grafana";
        mode = "0400";
        content = ''
          AUTH_TOKEN=${config.sops.placeholder."grafana/renderer-token"}
        '';
      };

      # Env file for eva's native agent runtime (Anthropic API) — CURRENTLY UNUSED
      # (the subscription login is used instead), kept for a quick switch back.
      # Reads anthropic/token.
      "openclaw/anthropic-env" = {
        group = "agents";
        mode = "0440";
        content = ''
          ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic/token"}
        '';
      };

      # Env file for eva's reply TTS (ElevenLabs). Added as an EnvironmentFile on
      # eva's service; the elevenlabs provider reads ELEVENLABS_API_KEY. Reads
      # elevenlabs/token.
      "openclaw/elevenlabs-env" = {
        group = "agents";
        mode = "0440";
        content = ''
          ELEVENLABS_API_KEY=${config.sops.placeholder."elevenlabs/token"}
        '';
      };

    };
  };
}
