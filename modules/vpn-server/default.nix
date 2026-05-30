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

      umask 077
      cat > "$PEER_SLUG.conf" <<EOF
      [Interface]
      PrivateKey = $PRIVATE_KEY
      Address = $PEER_IP/32
      DNS = ${cfg.clientDns}

      [Peer]
      PublicKey = ${cfg.serverPublicKey}
      PresharedKey = $PSK
      Endpoint = ${cfg.serverEndpoint}
      AllowedIPs = 0.0.0.0/0, ::/0
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
      ips = [ cfg.serverIp ];
      listenPort = cfg.listenPort;
      privateKeyFile = cfg.privateKeyFile;
      peers = lib.mapAttrsToList (_: peer: {
        inherit (peer) publicKey allowedIPs presharedKeyFile;
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
      # Hairpin NAT: allow wg0→wg0 forwarding and masquerade so that VPN peers
      # can reach each other and server services via the tunnel IP, with
      # responses routed back through WireGuard instead of bypassing it.
      extraCommands = ''
        iptables -A FORWARD -i ${cfg.interface} -o ${cfg.interface} -j ACCEPT
        iptables -t nat -A POSTROUTING -s ${cfg.tunnelSubnet} -o ${cfg.interface} -j MASQUERADE
      '';
      extraStopCommands = ''
        iptables -D FORWARD -i ${cfg.interface} -o ${cfg.interface} -j ACCEPT || true
        iptables -t nat -D POSTROUTING -s ${cfg.tunnelSubnet} -o ${cfg.interface} -j MASQUERADE || true
      '';
    };

    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];
    networking.firewall.trustedInterfaces = [ cfg.interface ];

    environment.systemPackages = [ wg-create-profile ];
  };
}
