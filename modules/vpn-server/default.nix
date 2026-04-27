{ config, lib, pkgs, ... }:

let
  cfg = config.my.vpn-server;

  wg-create-profile = pkgs.writeShellApplication {
    name = "wg-create-profile";
    runtimeInputs = [ pkgs.wireguard-tools ];
    text = ''
      usage() {
        echo "Usage: wg-create-profile <peer-name> <peer-ip>"
        echo ""
        echo "Creates a directory in the current folder (spaces in name become dashes) containing:"
        echo "  <peer_name>-private.key        — peer private key"
        echo "  <peer_name>-public.key         — peer public key"
        echo "  <peer_name>-psk               — preshared key"
        echo "  <peer_name>-client.conf        — ready-to-import client config"
        echo "  <peer_name>-server.conf        — server-side profile config"
        echo ""
        echo "File base names use underscores in place of spaces and dashes."
        exit 1
      }

      [ $# -ne 2 ] && usage

      PEER_NAME="$1"
      PEER_IP="$2"
      FOLDER_NAME="''${PEER_NAME// /-}"
      FILE_BASE="''${PEER_NAME//[ -]/_}"
      PROFILE_DIR="$(pwd)/$FOLDER_NAME"

      mkdir -p "$PROFILE_DIR"

      PRIVATE_KEY=$(wg genkey)
      PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
      PSK=$(wg genpsk)

      echo "$PRIVATE_KEY" > "$PROFILE_DIR/$FILE_BASE-private.key"
      echo "$PUBLIC_KEY"  > "$PROFILE_DIR/$FILE_BASE-public.key"
      echo "$PSK"         > "$PROFILE_DIR/$FILE_BASE-psk"
      chmod 600 "$PROFILE_DIR/$FILE_BASE-private.key" "$PROFILE_DIR/$FILE_BASE-psk"

      cat > "$PROFILE_DIR/$FILE_BASE-client.conf" <<EOF
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
      chmod 600 "$PROFILE_DIR/$FILE_BASE-client.conf"

      cat > "$PROFILE_DIR/$FILE_BASE-server.conf" <<EOF
      [Peer]
      PublicKey = $PUBLIC_KEY
      PresharedKey = $PSK
      AllowedIPs = $PEER_IP/32
      EOF
      chmod 600 "$PROFILE_DIR/$FILE_BASE-server.conf"

      echo "Profile created in $PROFILE_DIR"
      echo "Peer public key: $PUBLIC_KEY"
      echo ""
      echo "To register on the server:"
      echo "  sudo cp $PROFILE_DIR/$FILE_BASE-server.conf ${cfg.profilesDir}/ && \\"
      echo "  sudo wg addconf ${cfg.interface} ${cfg.profilesDir}/$FILE_BASE-server.conf"
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

    profilesDir = lib.mkOption {
      type = lib.types.path;
      default = "/etc/wireguard/profiles.d";
      description = "Directory of profile config files loaded at interface startup";
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
  };

  config = lib.mkIf cfg.enable {
    networking.wireguard.interfaces.${cfg.interface} = {
      ips = [ cfg.serverIp ];
      listenPort = cfg.listenPort;
      privateKeyFile = cfg.privateKeyFile;
    };

    systemd.services."wg-load-profiles-${cfg.interface}" = {
      description = "Load WireGuard profiles for ${cfg.interface}";
      after = [ "sys-subsystem-net-devices-${cfg.interface}.device" ];
      bindsTo = [ "sys-subsystem-net-devices-${cfg.interface}.device" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.wireguard-tools ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        shopt -s nullglob
        for f in ${cfg.profilesDir}/*.conf; do
          wg addconf ${cfg.interface} "$f"
        done
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.profilesDir} 0700 root root -"
    ];

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
