# `uplinkInterface` is a module argument set in ./default.nix (_module.args), so
# the physical NIC is named in exactly one place — see the comment there.
{ config, uplinkInterface, ... }:
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

      # Trust the LAN: accept all inbound traffic sourced from the local subnet
      # (the uplink is on 192.168.2.0/24). Internet traffic routed in via the router
      # keeps its non-LAN source address and is unaffected. iptables backend —
      # nftables is not enabled here (the egress modules rely on iptables).
      extraCommands = ''
        iptables -A nixos-fw -s 192.168.2.0/24 -j nixos-fw-accept
      '';
      extraStopCommands = ''
        iptables -D nixos-fw -s 192.168.2.0/24 -j nixos-fw-accept || true
      '';
    };
  };
}
