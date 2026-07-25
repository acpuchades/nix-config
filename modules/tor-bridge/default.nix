{ config, lib, ... }:

#
# tor-bridge — an obfs4 Tor bridge, plus a local SOCKS proxy.
#
# A bridge is a relay that is deliberately kept out of the public relay
# directory and wrapped in obfs4, so a censor cannot simply download the relay
# list and block it. A residential IP is much more useful in that role than as
# a public relay: bridges only work while they are unlisted, and being listed
# publicly as Tor infrastructure gets the host's IP blocked by a fair number of
# ordinary sites.
#
# `services.tor.relay.role` is a single enum — a daemon is a relay OR a bridge,
# never both. Running both would mean two Tor daemons in separate namespaces,
# which the NixOS module does not support out of the box.
#
# The SOCKS client shares this daemon. The Tor Project discourages mixing your
# own traffic with relayed traffic on one instance; for a home server the
# practical risk is small, but it is the reason `client.enable` is a separate
# knob here rather than being implied.
#
# Two things this module cannot do for you:
#
#   1. Port forwarding. Both `orPort` and `obfs4Port` must be forwarded from
#      the router to this host, or the bridge is unreachable and will never be
#      distributed to users. The firewall rules below only cover the host.
#   2. Reachability. After the first start, check the journal for
#      "Self-testing indicates your ORPort is reachable from the outside".
#      Until that line appears the bridge publishes nothing.
#
# The bridge line users need (for manual sharing) is written by the daemon to
#   /var/lib/tor/pt_state/obfs4_bridgeline.txt
# and the fingerprint to /var/lib/tor/fingerprint.
#

let
  cfg = config.my.tor-bridge;
in
{
  options.my.tor-bridge = {
    enable = lib.mkEnableOption "obfs4 Tor bridge";

    nickname = lib.mkOption {
      type = lib.types.str;
      description = ''
        Public nickname for the bridge, 1-19 alphanumeric characters. Appears
        in bridge statistics; it does not need to relate to this host.
      '';
    };

    contactInfo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tor-bridge <admin@example.com>";
      description = ''
        Contact address published with the bridge descriptor, so the Tor
        Project can reach you about problems. Optional, and it is published —
        use an address you are willing to make public.
      '';
    };

    orPort = lib.mkOption {
      type = lib.types.port;
      default = 9001;
      description = ''
        ORPort, the main Tor protocol port. Must be forwarded from the router.
      '';
    };

    obfs4Port = lib.mkOption {
      type = lib.types.port;
      default = 9002;
      description = ''
        Port for the obfs4 pluggable transport, which is what censored clients
        actually connect to. Must be forwarded from the router.

        Well-known ports (443, 80) are harder for a censor to block wholesale,
        but both are already taken by Caddy on this host, so this defaults to a
        high port instead.
      '';
    };

    bandwidth = {
      rate = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10 MBytes";
        description = ''
          Sustained relayed-traffic rate (RelayBandwidthRate). null leaves the
          bridge uncapped, which on a home connection will compete with
          everything else on this host.
        '';
      };

      burst = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "20 MBytes";
        description = "Burst allowance above `rate` (RelayBandwidthBurst).";
      };

      monthlyMax = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "1 TBytes";
        description = ''
          Monthly transfer cap (AccountingMax). Tor hibernates once it is hit
          and wakes at the start of the next accounting period. Counted
          separately for read and write, so the real total is up to double
          this. Useful if the ISP meters traffic.
        '';
      };

      accountingStart = lib.mkOption {
        type = lib.types.str;
        default = "month 1 00:00";
        description = "Start of each accounting period (AccountingStart).";
      };
    };

    client = {
      enable = lib.mkEnableOption "local SOCKS proxy on the same daemon" // {
        default = true;
      };

      socksPort = lib.mkOption {
        type = lib.types.port;
        default = 9050;
        description = ''
          SOCKS port, bound to loopback only. Not opened in the firewall — an
          open SOCKS proxy would be an open relay for anyone on the network.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.tor = {
      enable = true;

      # Opens ORPort (and DirPort, unused here). It does NOT open the obfs4
      # transport port — that is handled explicitly below.
      openFirewall = true;

      relay = {
        enable = true;
        # "bridge" implies BridgeRelay, ExtORPort and the obfs4
        # ServerTransportPlugin upstream; "private-bridge" would additionally
        # stop publishing the descriptor, making the bridge useless to anyone
        # who was not handed its address directly.
        role = "bridge";
      };

      client = {
        enable = cfg.client.enable;
        socksListenAddress = {
          addr = "127.0.0.1";
          port = cfg.client.socksPort;
        };
      };

      settings = {
        Nickname = cfg.nickname;
        ORPort = [ cfg.orPort ];

        # obfs4proxy would otherwise pick an ephemeral port on every start,
        # which cannot be port-forwarded. Pinning it keeps the bridge line
        # stable across restarts.
        ServerTransportListenAddr = [ "obfs4 0.0.0.0:${toString cfg.obfs4Port}" ];
      }
      // lib.optionalAttrs (cfg.contactInfo != null) {
        ContactInfo = cfg.contactInfo;
      }
      // lib.optionalAttrs (cfg.bandwidth.rate != null) {
        RelayBandwidthRate = cfg.bandwidth.rate;
      }
      // lib.optionalAttrs (cfg.bandwidth.burst != null) {
        RelayBandwidthBurst = cfg.bandwidth.burst;
      }
      // lib.optionalAttrs (cfg.bandwidth.monthlyMax != null) {
        AccountingMax = cfg.bandwidth.monthlyMax;
        AccountingStart = cfg.bandwidth.accountingStart;
      };
    };

    # services.tor.openFirewall only covers ORPort/DirPort. Without this the
    # bridge appears healthy in the journal but no client can ever reach the
    # transport.
    networking.firewall.allowedTCPPorts = [ cfg.obfs4Port ];
  };
}
