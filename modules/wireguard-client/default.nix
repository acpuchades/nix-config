{ config, lib, ... }:

let
  cfg = config.my.wireguard-client;

  # One submodule per outbound WireGuard client profile. The profile's
  # [Interface] PrivateKey/Address go on the interface; its [Peer] block
  # becomes the single peer.
  interfaceModule = lib.types.submodule {
    options = {
      privateKeyFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          Path to the file holding this profile's WireGuard private key
          (the `PrivateKey` from the provider's .conf). Typically a
          sops-nix secret path so the key never lands in the Nix store.
        '';
      };

      address = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          Tunnel-local address(es) for this interface (the profile's
          `Address` field), in CIDR notation.
        '';
        example = [ "10.2.0.2/32" ];
      };

      listenPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Optional fixed listen port. Leave null to let the kernel pick a
          random source port, which is the normal case for a client.
        '';
      };

      peer = {
        publicKey = lib.mkOption {
          type = lib.types.str;
          description = "Remote peer's public key (the peer `PublicKey`).";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          description = ''
            Remote endpoint as host:port (the peer `Endpoint`).
          '';
          example = "192.0.2.10:51820";
        };

        presharedKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Optional path to a preshared-key file. Set only if the profile
            includes a `PresharedKey` (many providers don't).
          '';
        };

        allowedIPs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0/0" "::/0" ];
          description = ''
            Traffic the peer is allowed to carry (crypto-routing).
            Full-tunnel by default; whether these also become kernel
            routes is governed by `allowedIPsAsRoutes`/`table` below.
          '';
        };

        persistentKeepalive = lib.mkOption {
          type = lib.types.int;
          default = 25;
          description = ''
            Seconds between keepalive packets, to keep the NAT mapping to
            the remote peer alive.
          '';
        };
      };

      allowedIPsAsRoutes = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to install this interface's allowedIPs as routes.

          Defaults to false so simply bringing the tunnel up never
          hijacks the host's default route — that would break inbound
          services and reply-path symmetry. Egress steering for this
          tunnel is expected to be done by a separate policy-routing
          layer. Set true (usually together with a dedicated `table`)
          only if you want WireGuard itself to manage the routes.
        '';
      };

      table = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Routing table that allowedIPs routes are added to when
          `allowedIPsAsRoutes` is true. Use a dedicated table to keep
          these routes out of `main` for policy routing; "off" suppresses
          route creation entirely. Ignored when `allowedIPsAsRoutes` is
          false.
        '';
      };
    };
  };
in
{
  options.my.wireguard-client = {
    enable = lib.mkEnableOption "outbound WireGuard client interfaces";

    interfaces = lib.mkOption {
      type = lib.types.attrsOf interfaceModule;
      default = { };
      description = ''
        Outbound WireGuard client tunnels to create, keyed by the
        interface name. Each entry corresponds to one WireGuard client
        profile (.conf), regardless of provider.

        This module only creates the interfaces and associates them with
        their profiles — it intentionally does not configure NAT, routing
        policy, or DNS. Those concerns belong to whatever consumes these
        tunnels.
      '';
      example = lib.literalExpression ''
        {
          wgproton = {
            privateKeyFile = config.sops.secrets."wireguard-client/wgproton".path;
            address = [ "10.2.0.2/32" ];
            peer = {
              publicKey = "abc...=";
              endpoint = "192.0.2.10:51820";
            };
          };
        }
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.interfaces != { }) {
    networking.wireguard.interfaces = lib.mapAttrs (_: ifc: {
      ips = ifc.address;
      privateKeyFile = ifc.privateKeyFile;
      listenPort = ifc.listenPort;
      allowedIPsAsRoutes = ifc.allowedIPsAsRoutes;
      table = lib.mkIf (ifc.table != null) ifc.table;
      peers = [
        {
          publicKey = ifc.peer.publicKey;
          endpoint = ifc.peer.endpoint;
          presharedKeyFile = ifc.peer.presharedKeyFile;
          allowedIPs = ifc.peer.allowedIPs;
          persistentKeepalive = ifc.peer.persistentKeepalive;
        }
      ];
    }) cfg.interfaces;
  };
}
