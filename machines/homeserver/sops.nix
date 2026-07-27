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

      # One SMB password per user (nested samba/<user> branch). Add a line here
      # for each additional user, then store the value with:
      #   sops machines/homeserver/secrets/default.yml
      "samba/alex" = { mode = "0400"; };

      # OpenClaw (eva) Telegram identity, consumed as files by my.openclaw.
      # telegram.{tokenFile,allowedIdFile}. The token is read by systemd
      # LoadCredential (as root, then handed to the service), so default
      # ownership is fine. The allowed-ID file is read by the service's
      # ExecStartPre seed script, which runs AS eva, so it must be eva-readable.
      "openclaw/telegram-token" = { mode = "0400"; };
      "openclaw/telegram-userid" = {
        owner = "eva";
        mode = "0400";
      };

      # ElevenLabs API key for eva's reply TTS, rendered into the env file below
      # and read by the openclaw service as ELEVENLABS_API_KEY. Populate with:
      #   sops machines/homeserver/secrets/default.yml   (openclaw/elevenlabs-token)
      "openclaw/elevenlabs-token" = {
        owner = "eva";
        mode = "0400";
      };

      # Anthropic API key for eva's native agent runtime (my.openclaw.agentRuntime
      # = null). Rendered into the env file below and read by the openclaw service
      # as ANTHROPIC_API_KEY. Populate with:
      #   sops machines/homeserver/secrets/default.yml   (openclaw/anthropic-token)
      "openclaw/anthropic-token" = {
        owner = "eva";
        mode = "0400";
      };

      # Gemini API key for eva's generate-image action
      # (my.openclaw.actions.generateImage.tokenFile). Read at RUNTIME by the
      # generate-image wrapper, which runs AS eva, so it must be eva-readable.
      # Populate/rotate with:
      #   sops machines/homeserver/secrets/default.yml   (openclaw/gemini-token)
      "openclaw/gemini-token" = {
        owner = "eva";
        mode = "0400";
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

      "grafana/renderer-env" = {
        owner = "grafana";
        group = "grafana";
        mode = "0400";
        content = ''
          AUTH_TOKEN=${config.sops.placeholder."grafana/renderer-token"}
        '';
      };

      # Env file for eva's native agent runtime (Anthropic API). Added as an
      # EnvironmentFile on the openclaw service; the anthropic provider reads
      # ANTHROPIC_API_KEY.
      "openclaw/anthropic-env" = {
        owner = "eva";
        mode = "0400";
        content = ''
          ANTHROPIC_API_KEY=${config.sops.placeholder."openclaw/anthropic-token"}
        '';
      };

      # Env file for eva's reply TTS (ElevenLabs). Added as an EnvironmentFile on
      # the openclaw service; the elevenlabs provider reads ELEVENLABS_API_KEY.
      "openclaw/elevenlabs-env" = {
        owner = "eva";
        mode = "0400";
        content = ''
          ELEVENLABS_API_KEY=${config.sops.placeholder."openclaw/elevenlabs-token"}
        '';
      };

    };
  };
}
