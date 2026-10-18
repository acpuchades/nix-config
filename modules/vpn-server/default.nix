{ config, lib, pkgs, ... }:

let
  cfg = config.my.vpn-server;

  # Generates a new peer (keypair + preshared key) and a ready-to-import client
  # config, then prints the sops entry + the Nix block to add under
  # my.vpn-server.peers. Peers are declarative (managed by systemd-networkd via
  # networking.wireguard), so registering one is: paste the block, store the
  # PSK in sops, rebuild. The script touches nothing on the server itself.
  wg-create-profile = pkgs.writeShellApplication {
    name = "wg-create-profile";
    runtimeInputs = [ pkgs.wireguard-tools ];
    text = ''
      usage() {
        echo "Usage: wg-create-profile <peer-name> <peer-ip>"
        echo ""
        echo "Generates a WireGuard peer and writes <peer-name>.conf in the"
        echo "current directory (import that on the device). It then prints the"
        echo "preshared key to store in sops and the Nix block to add under"
        echo "my.vpn-server.peers. After adding both and rebuilding, the peer is live."
        exit 1
      }

      [ "$#" -ne 2 ] && usage
      case "''${1:-}" in -h|--help) usage ;; esac

      PEER_NAME="$1"
      PEER_IP="$2"
      PEER_SLUG="''${PEER_NAME// /-}"

      PRIVATE_KEY=$(wg genkey)
      PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
      PSK=$(wg genpsk)

      ${if cfg.ula6Prefix == null then ''
        # IPv4-only AllowedIPs: the server has no IPv6 address on the tunnel and
        # no IPv6 egress, so advertising ::/0 would install a default v6 route
        # into a tunnel that black-holes it.
        ADDRESS="$PEER_IP/32"
        ALLOWED="0.0.0.0/0"
      '' else ''
        # ::/0 too, so a dual-stack client cannot send IPv6 around the tunnel
        # (its real address to every v6 site). The client gets only a ULA, which
        # it ranks below IPv4 for global destinations (RFC 6724), and the server
        # REJECTs v6 forwarding — so v6 fails fast instead of leaking or stalling.
        IFS=. read -r _ _ net host <<<"$PEER_IP"
        ADDRESS="$PEER_IP/32, ${cfg.ula6Prefix}:$net::$host/128"
        ALLOWED="0.0.0.0/0, ::/0"
      ''}
      umask 077
      cat > "$PEER_SLUG.conf" <<EOF
      [Interface]
      PrivateKey = $PRIVATE_KEY
      Address = $ADDRESS
      DNS = ${cfg.clientDns}

      [Peer]
      PublicKey = ${cfg.serverPublicKey}
      PresharedKey = $PSK
      Endpoint = ${cfg.serverEndpoint}
      AllowedIPs = $ALLOWED
      PersistentKeepalive = 25
      EOF

      cat <<EOF

      Wrote $PEER_SLUG.conf — import this on the device.

      Register the peer on the server (declarative — two edits + rebuild):

      1) Store the preshared key in sops:
           sops machines/homeserver/secrets/default.yml
         add it under the wireguard/psk branch:
           wireguard:
               psk:
                   $PEER_SLUG: $PSK
         and declare it in machines/homeserver/sops.nix (secrets):
           "wireguard/psk/$PEER_SLUG" = { mode = "0400"; };

      2) Add the peer under my.vpn-server.peers in machines/homeserver/default.nix:
           $PEER_SLUG = {
             publicKey = "$PUBLIC_KEY";
             allowedIPs = [ "$PEER_IP/32" ];
             presharedKeyFile = config.sops.secrets."wireguard/psk/$PEER_SLUG".path;
           };

      Then rebuild: sudo nixos-rebuild switch --flake .#homeserver
      EOF
    '';
  };

  # 10.0.N.M/32 -> <ula6Prefix>:N::M/128, the peer's IPv6 twin.
  ula6Of = cidr:
    let
      octets = lib.splitString "." (lib.head (lib.splitString "/" cidr));
    in
    "${cfg.ula6Prefix}:${lib.elemAt octets 2}::${lib.elemAt octets 3}/128";

  # FORWARD policy for tunnel traffic, appended after the protonvpn kill-switch
  # jumps (which ACCEPT a steered peer's internet traffic first and RETURN its
  # local traffic here). Replies are always let through; new connections INTO
  # peers are not; peer->peer and peer->LAN only from the listed sources.
  fwdIn = "vpn-forward-in";
  fwdOut = "vpn-forward-out";
  forwardStart = ''
    iptables -N ${fwdIn} 2>/dev/null || iptables -F ${fwdIn}
    iptables -A ${fwdIn} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ${lib.concatMapStrings (src: ''
      iptables -A ${fwdIn} -s ${src} -o ${cfg.interface} -j ACCEPT
    '') cfg.peerToPeerFrom}
    iptables -A ${fwdIn} -o ${cfg.interface} -j DROP
    ${lib.concatMapStrings (dst: lib.concatMapStrings (src: ''
      iptables -A ${fwdIn} -s ${src} -d ${dst} -j ACCEPT
    '') cfg.lanAccessFrom + ''
      iptables -A ${fwdIn} -d ${dst} -j DROP
    '') cfg.lanNetworks}
    iptables -A ${fwdIn} -j ACCEPT

    iptables -N ${fwdOut} 2>/dev/null || iptables -F ${fwdOut}
    iptables -A ${fwdOut} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A ${fwdOut} -j DROP

    iptables -D FORWARD -i ${cfg.interface} -j ${fwdIn} 2>/dev/null || true
    iptables -A FORWARD -i ${cfg.interface} -j ${fwdIn}
    iptables -D FORWARD -o ${cfg.interface} -j ${fwdOut} 2>/dev/null || true
    iptables -A FORWARD -o ${cfg.interface} -j ${fwdOut}
  '';
  forwardStop = ''
    iptables -D FORWARD -i ${cfg.interface} -j ${fwdIn} 2>/dev/null || true
    iptables -D FORWARD -o ${cfg.interface} -j ${fwdOut} 2>/dev/null || true
    iptables -F ${fwdIn} 2>/dev/null || true
    iptables -X ${fwdIn} 2>/dev/null || true
    iptables -F ${fwdOut} 2>/dev/null || true
    iptables -X ${fwdOut} 2>/dev/null || true
  '';
in
{
  options.my.vpn-server = {
    enable = lib.mkEnableOption "WireGuard VPN server";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
      description = "WireGuard interface name";
    };

    serverIp = lib.mkOption {
      type = lib.types.str;
      default = "10.0.0.1/24";
      description = "WireGuard server tunnel IP in CIDR notation";
    };

    tunnelSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.0.0.0/24";
      description = "WireGuard tunnel subnet used for hairpin NAT (must match serverIp prefix)";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "WireGuard listen port";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the WireGuard server private key file";
    };

    serverPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard server public key (shown by: wg show <interface> public-key)";
    };

    serverEndpoint = lib.mkOption {
      type = lib.types.str;
      description = "External endpoint for peers to connect to, e.g. vpn.example.com:51820";
    };

    clientDns = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = "DNS server written into generated peer configs";
    };

    ula6Prefix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "fd7a:9c0e:2b1d";
      description = ''
        A /48 ULA prefix (without the trailing `::`). When set, wg0 gets
        `<prefix>::1/48`, every peer address 10.0.N.M also gets
        `<prefix>:N::M/128`, and generated profiles route ::/0 into the tunnel —
        where IPv6 is rejected, not forwarded — so a client's IPv6 cannot bypass
        the VPN. Existing profiles need the same two edits by hand.
      '';
    };

    lanNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.1.0/24" ];
      description = "Networks behind upstreamInterface that peers reach only from lanAccessFrom.";
    };

    lanAccessFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Peer sources that may open connections into lanNetworks (the router,
        printers, IoT). Everyone else reaches the internet and this host's own
        services, not the LAN.
      '';
    };

    peerToPeerFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Peer sources that may open connections to other peers. Default: none.";
    };

    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      description = "Interface client traffic is masqueraded onto (e.g. eth0, wlp3s0)";
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "The peer's WireGuard public key.";
          };
          allowedIPs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = ''
              Tunnel addresses routed to this peer, e.g. [ "10.0.0.2/32" ].
            '';
          };
          presharedKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to this peer's preshared-key file (typically a sops secret).
              Null for no preshared key.
            '';
          };
        };
      });
      default = { };
      description = ''
        Declarative WireGuard peers, keyed by a label. These are managed by
        systemd-networkd, so they survive interface restarts/rebuilds. Generate
        a peer's keys, client config, and the block to paste here with
        `wg-create-profile`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.wireguard.interfaces.${cfg.interface} = {
      ips = [ cfg.serverIp ] ++ lib.optional (cfg.ula6Prefix != null) "${cfg.ula6Prefix}::1/48";
      listenPort = cfg.listenPort;
      privateKeyFile = cfg.privateKeyFile;
      peers = lib.mapAttrsToList (_: peer: {
        inherit (peer) publicKey presharedKeyFile;
        allowedIPs = peer.allowedIPs ++ lib.optionals (cfg.ula6Prefix != null) (map ula6Of peer.allowedIPs);
      }) cfg.peers;
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    networking.nat = {
      enable = true;
      externalInterface = cfg.upstreamInterface;
      internalInterfaces = [ cfg.interface ];
      # Hairpin NAT: masquerade wg0→wg0 so that peers allowed to reach each
      # other (peerToPeerFrom) get responses routed back through WireGuard
      # instead of bypassing it. What may be forwarded at all: forwardStart.
      #
      # MSS clamping: peer profiles carry no explicit MTU, so clients sit at
      # WireGuard's 1420 default, which needs 1480 bytes on the outer path. Plenty
      # of client uplinks (LTE, PPPoE at 1492, hotel WiFi) are below that, and
      # without clamping the oversized segments are silently dropped -- the tunnel
      # handshakes and small requests work while large transfers stall. Rewriting
      # the MSS on both legs of the handshake (SYN and SYN-ACK, hence the
      # SYN,RST SYN flag match rather than --syn) makes TCP negotiate a size that
      # fits the discovered path MTU instead of black-holing.
      extraCommands = forwardStart + ''
        iptables -t nat -A POSTROUTING -s ${cfg.tunnelSubnet} -o ${cfg.interface} -j MASQUERADE
        iptables -t mangle -A FORWARD -o ${cfg.interface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        iptables -t mangle -A FORWARD -i ${cfg.interface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
      '';
      extraStopCommands = forwardStop + ''
        iptables -t nat -D POSTROUTING -s ${cfg.tunnelSubnet} -o ${cfg.interface} -j MASQUERADE || true
        iptables -t mangle -D FORWARD -o ${cfg.interface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
        iptables -t mangle -D FORWARD -i ${cfg.interface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
      '';
    };

    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];
    # The tunnel interface is deliberately NOT in trustedInterfaces: peers are
    # authenticated, not trusted with every listening socket. Services meant
    # for them accept by SOURCE prefix instead — each module's allowed-networks
    # rules include the wg prefixes (privateNetworks), and a source rule
    # matches wg peers regardless of which interface the packet arrived on.
    # The NixOS firewall does not filter FORWARD (filterForward is
    # nftables-only), so forwarded tunnel traffic is policed by the chains in
    # forwardStart instead.

    environment.systemPackages = [ wg-create-profile ];
  };
}
