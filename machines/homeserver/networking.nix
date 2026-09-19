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
        8333  # bitcoin
      ];

      # NO blanket LAN accept, deliberately (dropped 2026-09-19): "everything
      # from 192.168.2.0/24" made every IoT device and every WireGuard peer —
      # several belonging to a second person — able to reach every listening
      # socket, which is exactly what turned loopback-vs-0.0.0.0 bind mistakes
      # into real exposures. Each service that LAN/VPN clients use directly now
      # carries its own source-restricted accept (samba 445, cups 631, DNS 53,
      # upsd 3493, jellyfin 8096, mDNS below); anything without a rule is
      # reachable only through Caddy. iptables backend — nftables is not
      # enabled here (the egress modules rely on iptables).
      #
      # mDNS answers (.local / AirPrint discovery) are the one host-level rule:
      # avahi is host plumbing, not a module. LAN only — multicast does not
      # cross the WireGuard tunnel anyway.
      extraCommands = ''
        iptables -I nixos-fw -p udp -s ${lanNetwork} --dport 5353 -j nixos-fw-accept
      '';
      extraStopCommands = ''
        iptables -D nixos-fw -p udp -s ${lanNetwork} --dport 5353 -j nixos-fw-accept || true
      '';
    };
  };
}
