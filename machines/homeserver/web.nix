# The public edge: nginx (wildcard certs, origin cloaking, login rate limits),
# AdGuard's split-horizon rewrites that send LAN/VPN clients straight to it, and
# the service dashboard that links every vhost.
{
  config,
  homeServerLocalAddress,
  adminEmailAddress,
  ...
}:

let
  inherit (import ./networks.nix) privateNetworks cloudflareNetworks;
in
{
  imports = [
    ../../modules/web-server
    ../../modules/dns-filtering
    ../../modules/service-dashboard
  ];

  my.web-server = {
    enable = true;
    adminEmail = adminEmailAddress;
    # One wildcard per zone, via lego + Cloudflare DNS-01. Postfix's STARTTLS
    # (./eva.nix) uses the acpuchades.com one too.
    certificates = {
      "acpuchades.com".environmentFile = config.sops.templates."acme/cloudflare-env".path;
      "fugazitrade.com".environmentFile = config.sops.templates."acme/cloudflare-env".path;
    };
    # Origin cloaking: every public name is orange-clouded, so the only
    # strangers with a reason to reach 80/443 are Cloudflare's edges; LAN
    # and VPN clients reach the private vhosts directly via AdGuard's
    # rewrites. Anyone else (Censys, Shodan) gets no TLS handshake, so the
    # certs can't tie acpuchades.com / fugazitrade.com to this IP. Certs
    # are DNS-01, so nothing needs inbound 80 from the ACME CA.
    allowedNetworks = cloudflareNetworks ++ privateNetworks;
    virtualHosts = {
      "acpuchades.com" = {
        redirect = "https://www.acpuchades.com";
      };
      "www.acpuchades.com" = {
        root = "/var/www/acpuchades.com";
      };
      "blog.acpuchades.com" = {
        redirect = "https://www.acpuchades.com/blog";
      };
    };
  };

  # Public logins with no lockout of their own (ntfy has one; Prefect is
  # LAN/VPN-only). Immich's mobile app logs in once per device, Umami's
  # admin rarely — 10/min per client never touches a real user.
  my.web-server.loginRateLimits = {
    ${config.my.cloud-suite.immich.hostName}.paths = [
      "/api/auth/login"
      "/api/auth/change-password"
    ];
    ${config.my.web-analytics.hostName}.paths = [ "/api/auth/login" ];
  };

  my.dns-filtering = {
    enable = true;
    adguardPort = 3000;
    dnsPort = 53;
    dnsResolverPort = 5300;
    basicAuthFile = config.sops.templates."nginx/adguard-htpasswd".path;
    virtualHost = "adguard.acpuchades.com";
    allowedNetworks = privateNetworks;
    # Plain DNS is for the LAN and the VPN only, never the public internet.
    # The wg prefixes must be listed: wg0 is not a trusted interface, so
    # peers reach :53 only through these source rules.
    allowedClientNetworks = privateNetworks;
    dnsRewrites = [
      # vpn.acpuchades.com is intentionally NOT rewritten here: it must
      # always resolve to the public IP (via DDNS) so the WireGuard endpoint
      # stays reachable. The router handles NAT hairpin for on-LAN clients,
      # which avoids the split-horizon blip a global AdGuard rewrite caused
      # for remote clients re-resolving the endpoint through the tunnel when
      # switching networks while connected.
      {
        domain = "acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "www.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "blog.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "home.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "adguard.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "bitwarden.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "photos.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "media.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "cloud.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "collabora.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "prefect.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "status.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "analytics.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "dashboard.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "torrent.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "nominatim.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "titan.acpuchades.com";
        answer = homeServerLocalAddress;
      }
      # fugazitrade.com is public AND proxied through Cloudflare, so these
      # rewrites do more than save a hairpin: a client resolving through
      # AdGuard reaches nginx directly instead of going out to the CF edge and
      # back. Same app, same certificate, one less party in the path.
      #
      # The apex and www are kept here even though NOTHING serves them right
      # now — there is no vhost for either, so a request gets a TLS handshake
      # failure (the catch-all's ssl_reject_handshake) rather than a page, which is what "reserved for launch" should
      # look like. www stays in ddclient too, so its record is current on the
      # day `prod` takes it rather than dating from whenever the box last
      # moved. The apex does NOT: it is a CNAME to www in Cloudflare and
      # follows it on its own (see the ddclient block in sops.nix). It is
      # rewritten here anyway, because a CNAME would otherwise send a LAN
      # client out to the CF edge and back for a name this resolver can answer
      # directly.
      {
        domain = "fugazitrade.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "www.fugazitrade.com";
        answer = homeServerLocalAddress;
      }
      {
        domain = "testing.fugazitrade.com";
        answer = homeServerLocalAddress;
      }
      # ntfy is reachable from off-LAN by design; this rewrite only affects
      # clients resolving through AdGuard, and just saves them a NAT hairpin.
      {
        domain = "ntfy.acpuchades.com";
        answer = homeServerLocalAddress;
      }
    ];
  };

  my.service-dashboard = {
    enable = true;
    hostName = "dashboard.acpuchades.com";
    allowedNetworks = privateNetworks;
    # Tiles reference each service's own hostName option, so they track
    # renames automatically — no second copy of the addresses to drift.
    groups = [
      {
        name = "Cloud";
        services = [
          {
            name = "Nextcloud";
            icon = "nextcloud.png";
            description = "Files, calendar, contacts & notes";
            href = "https://${config.my.cloud-suite.nextcloud.hostName}";
          }
          {
            name = "Immich";
            icon = "immich.png";
            description = "Photo & video backup";
            href = "https://${config.my.cloud-suite.immich.hostName}";
          }
          {
            name = "Vaultwarden";
            icon = "vaultwarden.png";
            description = "Password manager";
            href = "https://${config.my.cloud-suite.bitwarden.hostName}";
          }
          {
            name = "Collabora";
            icon = "collabora-online.png";
            description = "Online office suite";
            href = "https://${config.my.cloud-suite.collabora.hostName}";
          }
        ];
      }
      {
        name = "Media";
        services = [
          {
            name = "Jellyfin";
            icon = "jellyfin.png";
            description = "Movies, shows & music";
            href = "https://${config.my.media-server.hostName}";
          }
        ];
      }
      {
        name = "Smart Home";
        services = [
          {
            name = "Home Assistant";
            icon = "home-assistant.png";
            description = "Home automation";
            href = "https://${config.my.home-assistant.hostName}";
          }
        ];
      }
      {
        name = "Health";
        services = [
          {
            name = "titan";
            icon = "mdi-heart-pulse";
            description = "Body, nutrition, recovery & training";
            href = config.services.titan.publicUrl;
          }
        ];
      }
      {
        name = "Network";
        services = [
          {
            name = "AdGuard Home";
            icon = "adguard-home.png";
            description = "DNS filtering";
            href = "https://${config.my.dns-filtering.virtualHost}";
          }
          {
            name = "Transmission";
            icon = "transmission.png";
            description = "BitTorrent client";
            href = "https://${config.my.transmission-server.hostName}";
          }
        ];
      }
      {
        name = "Workflows & Analytics";
        services = [
          {
            name = "Prefect";
            icon = "https://avatars.githubusercontent.com/u/39270919?s=200&v=4";
            description = "Workflow orchestration";
            href = "https://${config.my.prefect-server.virtualHost}";
          }
          {
            name = "Umami";
            icon = "umami.png";
            description = "Web analytics";
            href = "https://${config.my.web-analytics.hostName}";
          }
          {
            name = "Nominatim";
            icon = "mdi-map-search";
            description = "OSM geocoding & reverse geocoding";
            href = "https://${config.my.geocoding.hostName}";
          }
        ];
      }
      {
        name = "Monitoring";
        services = [
          {
            name = "Grafana";
            icon = "grafana.png";
            description = "Metrics & dashboards";
            href = "https://${config.my.server-stats.hostName}";
          }
          {
            name = "ntfy";
            icon = "mdi-bell-ring";
            description = "Push notifications";
            href = "https://${config.my.push-notifications.hostName}";
          }
        ];
      }
    ];
  };
}
