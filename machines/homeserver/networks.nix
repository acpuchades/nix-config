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
}
