# `uplinkInterface` is a module argument set in ./default.nix (_module.args), so
# the physical NIC is named in exactly one place — see the comment there.
{ config, uplinkInterface, ... }:

let
  inherit (import ./networks.nix) lanNetwork;
in
{
  networking = {
    hostName = "homeserver"; # Define your hostname.

    # Pick only one of the below networking options.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    useNetworkd = true;
    networkmanager.enable = false;

    wireless = {
      enable = true;
      interfaces = [ uplinkInterface ];
      userControlled = false;
      secretsFile = config.sops.templates."wifi/secrets".path;
      networks."MIWIFI_5G_dehC" = {
        pskRaw = "ext:home-wlan-psk";
      };
    };

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Enable firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [
        8333 # bitcoin
      ];

      # NO blanket LAN accept, deliberately: it made every IoT device and every
      # WireGuard peer — several belonging to a second person — able to reach
      # every listening socket, turning loopback-vs-0.0.0.0 bind mistakes into
      # real exposures. Each service that LAN/VPN clients use directly declares
      # its own source-restricted accept via my.firewall-allow (samba 445, cups
      # 631, DNS 53, upsd 3493, jellyfin 8096, mDNS below); anything without one
      # is reachable only through nginx. iptables backend — nftables is not
      # enabled here (the egress modules rely on iptables).
    };
  };

  # mDNS answers (.local / AirPrint discovery) are the one host-level rule:
  # avahi is host plumbing, not a module. LAN only — multicast does not cross
  # the WireGuard tunnel anyway.
  my.firewall-allow.mdns = {
    networks = [ lanNetwork ];
    ports = [ 5353 ];
    protocols = [ "udp" ];
  };

  systemd.network.networks = {
    "10-${uplinkInterface}" = {
      matchConfig.Name = uplinkInterface;
      # Static LAN IP. The server's identity (192.168.2.2) is hardcoded
      # across AdGuard rewrites, the *.acpuchades.com vhosts,
      # homeServerLocalAddress and the router's 51820 port-forward, so it
      # must not float on DHCP (a lease change took the server down once).
      # Make sure 192.168.2.2 is outside the router's DHCP pool to avoid a
      # collision with a dynamically-assigned client.
      address = [ "192.168.2.2/24" ];
      gateway = [ "192.168.2.1" ];
      networkConfig = {
        DHCP = "no";
        DNS = [ "127.0.0.1" ];
      };
    };
  };
}
