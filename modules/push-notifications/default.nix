{ config, lib, ... }:

#
# push-notifications — self-hosted push notifications (ntfy).
#
# Wraps the upstream `services.ntfy-sh` module. That module already binds to
# 127.0.0.1:2586 by default, so unlike Nominatim there is no vhost to wrestle
# away from ACME — Caddy just reverse-proxies it, same as Umami.
#
# Two details that are easy to get wrong and hard to debug afterwards:
#
#   - `behind-proxy`. Without it every request looks like it comes from
#     127.0.0.1, so ntfy's per-visitor rate limiting collapses into one global
#     bucket shared by every client. Caddy sets X-Forwarded-For, so this is
#     enabled by default here.
#   - `flush_interval -1` on the Caddy side. ntfy holds connections open for
#     subscriptions (SSE, JSON streaming, WebSocket). Caddy auto-detects
#     text/event-stream, but ntfy also streams application/x-ndjson, which it
#     does not — buffered, those subscriptions look like they simply hang.
#
# Access control is deny-all by default: an open ntfy server on a public
# hostname will be found and used as free infrastructure by others. Users and
# per-topic grants are created imperatively with the CLI, which reads
# /etc/ntfy/server.yml (installed by the upstream module):
#
#   sudo ntfy user add --role=admin alex
#   sudo ntfy user add --role=user homeassistant
#   sudo ntfy access homeassistant "alerts*" write-only
#   sudo ntfy token add homeassistant          # token for the HA integration
#
# The user database lives in /var/lib/ntfy-sh/user.db and survives rebuilds,
# but is NOT in this repo — back it up separately or expect to recreate it.
#
# iOS note: self-hosted servers cannot deliver background push to the App Store
# ntfy client on their own; the client polls via ntfy.sh's Firebase app. That
# is what `upstreamBaseUrl` is for — ntfy forwards a zero-content "poll
# request" to ntfy.sh so the phone knows to wake and fetch the real message
# from here. Message contents are not sent upstream, only the topic hash. Set
# it to null to keep even that local, at the cost of iOS background delivery.
#

let
  cfg = config.my.push-notifications;
in
{
  options.my.push-notifications = {
    enable = lib.mkEnableOption "Self-hosted push notifications (ntfy)";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for the ntfy server and web app";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "ntfy listen port (loopback only, fronted by Caddy)";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Restrict access to these CIDR ranges (empty = unrestricted).

        Leaving this empty is usually the right call even though it sounds
        wrong: the whole point of push notifications is reaching a phone that
        is off the LAN. Authentication, not network position, is what protects
        this service — see `defaultAccess`.
      '';
    };

    defaultAccess = lib.mkOption {
      type = lib.types.enum [ "read-write" "read-only" "write-only" "deny-all" ];
      default = "deny-all";
      description = ''
        Access granted to unauthenticated clients. `deny-all` means every
        publisher and subscriber needs credentials or a token.
      '';
    };

    behindProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Trust X-Forwarded-For, so rate limiting and visitor tracking see real
        client addresses rather than Caddy's loopback address.
      '';
    };

    upstreamBaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://ntfy.sh";
      description = ''
        Upstream server used to trigger iOS background push. null disables it
        (and with it, reliable iOS delivery). See the module header.
      '';
    };

    messageRetention = lib.mkOption {
      type = lib.types.str;
      default = "12h";
      description = ''
        How long delivered messages stay in the cache for clients that were
        offline. Longer means a phone that was off for a while still catches
        up, at the cost of disk.
      '';
    };

    attachmentRetention = lib.mkOption {
      type = lib.types.str;
      default = "24h";
      description = "How long uploaded attachments are kept before expiry.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://${cfg.hostName}";
        listen-http = "127.0.0.1:${toString cfg.port}";

        behind-proxy = cfg.behindProxy;
        auth-default-access = cfg.defaultAccess;

        cache-duration = cfg.messageRetention;
        attachment-expiry-duration = cfg.attachmentRetention;
      }
      // lib.optionalAttrs (cfg.upstreamBaseUrl != null) {
        upstream-base-url = cfg.upstreamBaseUrl;
      };
    };

    services.caddy.virtualHosts."${cfg.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
        # flush_interval -1 disables response buffering outright, which is what
        # ntfy's held-open subscription streams need. No `encode gzip` here for
        # the same reason: compressing a stream reintroduces buffering.
        ''
          reverse_proxy http://127.0.0.1:${toString cfg.port} {
            flush_interval -1
          }''
      ]);
  };
}
