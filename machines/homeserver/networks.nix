# Network constants shared by default.nix and fugazi.nix (both curried files
# of this same host — a plain attrset import, not a module, so either can use
# these in any position).
rec {
  lanNetwork = "192.168.2.0/24";

  # Every prefix of the WireGuard server's address space — one per exit, plus
  # the untunneled one. They are ALL equally trusted, and that is the point: a
  # peer is authenticated by its key and preshared key before it has an address
  # at all, so which prefix it was allocated out of decides where its traffic
  # EXITS and nothing about what it may reach. Leaving a prefix out of this list
  # does not harden anything — it silently costs those peers AdGuard, the file
  # shares, Transmission and the dashboards, with no error anywhere to say so.
  wgNetworks = [
    "10.0.0.0/24" # untunneled — straight out the ISP
    "10.0.1.0/24" # es
    "10.0.2.0/24" # in
    "10.0.3.0/24" # us
  ];

  privateNetworks = [ lanNetwork ] ++ wgNetworks;

  # Cloudflare's published edge ranges (cloudflare.com/ips-v4 + ips-v6, fetched
  # 2026-08-18). Every public web name on this host is proxied through
  # Cloudflare, so these — not the visitor — are the peers Caddy sees. Two jobs:
  # the hops trustedProxies skips to find the real caller (Caddy and fugazi),
  # and the only public sources the 80/443 firewall accepts (my.web-server
  # .allowedNetworks), so scanners never see the origin's certs on this IP.
  # Cloudflare changes the list rarely and announces it; a missing range shows
  # up as 52x errors for some visitors and as callers sharing a rate-limit
  # bucket — re-fetch then.
  cloudflareNetworks = [
    "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
    "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
    "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
    "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
    "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
    "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32"
  ];
}
