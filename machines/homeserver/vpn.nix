# VPN, egress and relays: the WireGuard server and its peers, ProtonVPN egress
# (with the P2P namespace Transmission lives in), and the obfs4 Tor bridge.
# Router port-forwards these depend on: 51820/udp (WireGuard) and the bridge's
# two ports.
{
  config,
  lib,
  uplinkInterface,
  adminEmailAddress,
  ...
}:

let
  inherit (import ./networks.nix) lanNetwork privateNetworks;
in
{
  imports = [
    ../../modules/vpn-server
    ../../modules/wireguard-client
    ../../modules/protonvpn
    ../../modules/transmission-server
    ../../modules/tor-bridge
  ];

  my.vpn-server =
    let
      # alex's own peers (named alex-*): the ones trusted past the internet
      # and this host — into the LAN and to each other.
      alexPeerAddresses = lib.concatLists (
        lib.mapAttrsToList (
          name: peer: lib.optionals (lib.hasPrefix "alex-" name) peer.allowedIPs
        ) config.my.vpn-server.peers
      );
    in
    {
      enable = true;
      privateKeyFile = config.sops.secrets."wireguard/private-key".path;
      serverPublicKey = "dnwEk7CRGfzDFJruRiCzmGNURU6Ba/OLUDpQ5ImO7G4=";
      serverEndpoint = "vpn.acpuchades.com:51820";
      clientDns = "10.0.0.1";
      upstreamInterface = uplinkInterface;
      # Every peer's IPv6 goes into the tunnel (and is refused there) instead
      # of around it.
      ula6Prefix = "fd7a:9c0e:2b1d";
      # Peers reach the internet and this host's services; only alex's own
      # devices reach the LAN (router, printer, IoT) and each other.
      lanNetworks = [ lanNetwork ];
      lanAccessFrom = alexPeerAddresses;
      peerToPeerFrom = alexPeerAddresses;
      peers = {
        alex-laptop = {
          publicKey = "96LNh5CjJQZuWpqquXlmc9cNU5sJzalzKcTcnMhqWSI=";
          allowedIPs = [ "10.0.1.2/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/alex-laptop".path;
        };
        alex-ipad = {
          publicKey = "qek70rKtZ2KpDk5JvEJrc3HDP9E0i+uwyv8BJpFi4GQ=";
          allowedIPs = [ "10.0.1.3/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/alex-ipad".path;
        };
        alex-phone-owner = {
          publicKey = "jzXucrFLPLL0og1QXP75R+oYUyTqNCRnD6gw3SMPI0M=";
          allowedIPs = [ "10.0.1.4/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-owner".path;
        };
        alex-phone-personal = {
          publicKey = "ayIoJHS1QIvbyixoVTRMuDB+RMoh6N7mgscfP7RY7wY=";
          allowedIPs = [ "10.0.1.5/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-personal".path;
        };
        alex-phone-work = {
          publicKey = "r/0vQN5JOLlWWOBwIi9SRJj8F06FrMP9xywO+PMs6Rc=";
          allowedIPs = [ "10.0.1.6/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/alex-phone-work".path;
        };
        mubin-laptop-personal = {
          publicKey = "Wk0VWDe0KNjrG8fDDTfFXpuNfZ8BNxLxhYiF1LFyCA4=";
          allowedIPs = [ "10.0.1.10/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-personal".path;
        };
        mubin-laptop-work = {
          publicKey = "3jUISZl3AQAScASjxNnoGPvayi1/3jbLUzVS+6Kzfmo=";
          allowedIPs = [ "10.0.1.11/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-laptop-work".path;
        };
        mubin-phone-personal = {
          publicKey = "y5XFrY1BT+lG25DM+0se9GBTiGcAv69Ag2twUbcWugE=";
          allowedIPs = [ "10.0.1.12/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-personal".path;
        };
        mubin-phone-work = {
          publicKey = "efhtt7/eRYIvoyda7u+0GUA7y6WOxZtbPjIUNwdOsF4=";
          allowedIPs = [ "10.0.1.13/32" ];
          presharedKeyFile = config.sops.secrets."wireguard/psk/mubin-phone-work".path;
        };
      };
    };

  # ProtonVPN egress. Everything about how this is wired — policy routing,
  # the fail-closed chains, the P2P namespace, NAT-PMP, the watchdog — lives
  # in modules/protonvpn; what is host-specific is only the topology below.
  #
  # The two tunnels are on DIFFERENT Proton servers on purpose. Sharing one
  # would give browsing traffic and BitTorrent traffic the same exit address,
  # which is the one correlation this whole arrangement exists to prevent.
  my.protonvpn = {
    enable = true;

    wgInterface = config.my.vpn-server.interface;

    # One prefix per exit, allocated out of 10.0.N.0/24. A peer's exit is
    # decided by which prefix its address came from and by nothing else, so
    # moving a device between exits is an address change in its profile plus
    # the matching allowedIPs here — the keys never move.
    #
    #   10.0.0.0/24  untunneled (straight out the ISP)
    #   10.0.1.0/24  es      ← every peer today
    #   10.0.2.0/24  in
    #   10.0.3.0/24  us
    #
    # 10.0.0.0/24 is deliberately kept and deliberately empty. It is the
    # fallback: a device that needs the residential Spanish address (a bank,
    # a streaming licence) or that must keep working while Proton is down
    # gets a SECOND profile on it and switches in the WireGuard app. Nothing
    # about that path depends on Proton, which is exactly why it is worth a
    # reserved prefix rather than being reclaimed.
    #
    # Note what moving every peer to es costs, because it is not nothing:
    # the kill switch is fail-closed, so ES#124 going down now takes every
    # peer's internet with it rather than a subset. The watchdog rotates
    # endpoints on the first failed probe and resets the interface after
    # two, but the window is real and the fallback is manual — hence the
    # paragraph above.
    #
    # Every locally-reachable prefix, so traffic between them is never
    # tunneled — including between two tunneled prefixes, which must stay on
    # wg0 rather than hairpin out through Proton and back. Identical to
    # privateNetworks by construction: a peer that can be reached locally is
    # exactly a peer that is trusted locally, and keeping two lists in step
    # by hand is how one of them goes stale. The transmission RPC veth
    # (10.200.0.0/30) is deliberately absent from both: tunneled clients have
    # no business reaching the daemon's RPC directly, they reach the web UI
    # through Caddy like everything else.
    localPrefixes = privateNetworks;

    clientTunnels = {
      es = {
        server = "ES#95";
        table = 42;
        sourcePrefixes = [ "10.0.1.0/24" ];
        gateway = "10.0.1.1/24";
        privateKeyFile = config.sops.secrets."wireguard-client/wgproton-es".path;
        address = [ "10.2.0.2/32" ];
        peer = {
          publicKey = "tEz96jcHEtBtZOmwMK7Derw0AOih8usKFM+n4Svhr1E=";
          endpoint = "130.195.250.66:51820";
          # A different machine AND network: ES#89/#108 are the same box as
          # ES#95, and ES#33/#37 are the P2P tunnel's server.
          fallbacks = [
            {
              server = "ES#161";
              publicKey = "cFQgn6VKZphGOdOGHux2xUf/QBWSExfg6koDuU68k28=";
              endpoint = "79.127.139.129:51820";
            }
          ];
        };
      };

      # India and the United States. Tables 42/43/44 are taken
      # (es, p2p, resolver), hence 45 and 46.
      "in" = {
        # quoted: `in` is a Nix keyword
        server = "IN#13";
        table = 45;
        sourcePrefixes = [ "10.0.2.0/24" ];
        gateway = "10.0.2.1/24";
        privateKeyFile = config.sops.secrets."wireguard-client/wgproton-in".path;
        address = [ "10.2.0.2/32" ];
        peer = {
          publicKey = "QnqJI0C2xQZrKfZLrBaCHa2h3TZ9CBt6sCuzg3ue4X4=";
          endpoint = "146.70.142.18:51820";
        };
      };

      us = {
        server = "US-NY#608";
        table = 46;
        sourcePrefixes = [ "10.0.3.0/24" ];
        gateway = "10.0.3.1/24";
        privateKeyFile = config.sops.secrets."wireguard-client/wgproton-us".path;
        address = [ "10.2.0.2/32" ];
        peer = {
          publicKey = "R8Of+lrl8DgOQmO6kcjlX7SchP4ncvbY90MB7ZUNmD8=";
          endpoint = "193.148.18.82:51820";
        };
      };
    };

    # Upstream DNS leaves through one exit, not per-client: the resolver is
    # a single host-wide service shared by the LAN and by every peer
    # whatever exit that peer uses, so there is no per-query country to
    # honour. Spain is chosen to match where this line actually is.
    resolver.viaTunnel = "es";

    # Failover, outage and recovery alerts from every tunnel's watchdog.
    watchdog.notify = {
      command = config.my.ntfy-alert.notifyCommand;
      environmentFile = config.sops.templates."ntfy/env".path;
    };

    p2pTunnel = {
      server = "ES#33 (P2P-flagged, NAT-PMP enabled)";
      privateKeyFile = config.sops.secrets."wireguard-client/wgproton-p2p".path;
      address = [ "10.2.0.2/32" ];
      # The same 10.2.0.2 as the client tunnel, which is what Proton hands
      # every config. Harmless here: this one lives in its own network
      # namespace, so the two addresses never share a routing table.
      peer = {
        publicKey = "roOsz9dJeKKVt6E3EIEKXQfZsmhSfsqOceZWiuGLIgg=";
        endpoint = "185.76.11.17:51820";
      };
    };
  };

  my.transmission-server = {
    enable = true;
    hostName = "torrent.acpuchades.com";
    downloadDir = "/srv/shared/Downloads";
    allowedNetworks = privateNetworks;
    basicAuthFile = config.sops.templates."caddy/torrent-auth".path;
    # Bumped above the module defaults (8000/1500 full, 2000/500 turtle) so
    # slow torrents aren't ceilinged — schedule unchanged (turtle 08:00–23:00,
    # full speed overnight). A cap is a ceiling not a floor: this only helps
    # torrents that actually have the peers to saturate it.
    maxDownKBps = 15000; # ~120 Mbit/s full speed (overnight 23:00–08:00)
    maxUpKBps = 2500;
    altDownKBps = 4000; # ~32 Mbit/s turtle (active 08:00–23:00)
    altUpKBps = 1000;
  };

  # obfs4 Tor bridge. Both ports below still need forwarding on the router,
  # same as 51820 for WireGuard.
  my.tor-bridge = {
    enable = true;
    nickname = "acpuchades";
    contactInfo = adminEmailAddress;
    bandwidth = {
      rate = "10 MBytes";
      burst = "20 MBytes";
    };
  };
}
