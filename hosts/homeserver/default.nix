# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  self,
  nixpkgs,
  home-manager,
  sops-nix,
  ...
}:

let

  configuration =
    inputs@{ config, lib, pkgs, ... }:
    import ./settings.nix inputs
    // {

      imports = [
        # Include the results of the hardware scan.
        ./hardware-configuration.nix
      ];

      users = import ./users.nix inputs;

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = import ./packages.nix inputs;

      # List services that you want to enable:
      services = import ./services.nix inputs;

      # Networking configuration.
      networking = import ./networking.nix inputs;

      sops.defaultSopsFile = ./secrets/default.yml;
      sops.defaultSopsFormat = "yaml";
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      sops.secrets = {

        "passwd/alex" = {
          key = "passwd/alex";
          neededForUsers = true;
        };

        "ddclient/domain" = { key = "ddclient/domain"; };
        "ddclient/password" = { key = "ddclient/password"; };

        "wifi/ssid" = { key = "wifi/ssid"; };
        "wifi/password" = { key = "wifi/password"; };

        "prefect/htpasswd" = {
          owner = "nginx";
          group = "nginx";
          mode = "0400";
        };

        "wg/server/private-key" = { key = "wireguard/server/privatekey"; };
        "wg/peers/alex-iphone/psk" = { key = "wireguard/peers/alex-iphone/psk"; };
        "wg/peers/alex-ipad/psk" = { key = "wireguard/peers/alex-ipad/psk"; };
        "wg/peers/alex-macbookpro/psk" = { key = "wireguard/peers/alex-macbookpro/psk"; };
        "wg/peers/mubin-phone/psk" = { key = "wireguard/peers/mubin-phone/psk"; };
        "wg/peers/mubin-laptop/psk" = { key = "wireguard/peers/mubin-laptop/psk"; };
      };

      sops.templates."ddclient/config".content = ''
        use=web, web=dynamicdns.park-your-domain.com/getip
        protocol=namecheap
        ssl=yes
        server=dynamicdns.park-your-domain.com
        login=${config.sops.placeholder."ddclient/domain"}
        password=${config.sops.placeholder."ddclient/password"}
        www,bitwarden,home,prefect
      '';

      sops.templates."nm-profiles/home-wlan".content = ''
        [connection]
        id=home-wlan
        type=wifi
        autoconnect=true
        interface-name=wlan0

        [wifi]
        mode=infrastructure
        ssid=${config.sops.placeholder."wifi/ssid"}

        [wifi-security]
        auth-alg=open
        key-mgmt=wpa-psk
        psk=${config.sops.placeholder."wifi/password"}

        [ipv4]
        method=auto

        [ipv6]
        addr-gen-mode=default
        method=auto
      '';

      environment.etc."NetworkManager/system-connections/home-wlan.nmconnection".source =
        config.sops.templates."nm-profiles/home-wlan".path;

      # Copy the NixOS configuration file and link it from the resulting system
      # (/run/current-system/configuration.nix). This is useful in case you
      # accidentally delete configuration.nix.
      # system.copySystemConfiguration = true;

      # This option defines the first version of NixOS you have installed on this particular machine,
      # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
      #
      # Most users should NEVER change this value after the initial install, for any reason,
      # even if you've upgraded your system to a new NixOS release.
      #
      # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
      # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
      # to actually do that.
      #
      # This value being lower than the current NixOS release does NOT mean your system is
      # out of date, out of support, or vulnerable.
      #
      # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
      # and migrated your data accordingly.
      #
      # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
      system.stateVersion = "25.05"; # Did you read the comment?

    };

in

nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    configuration
    sops-nix.nixosModules.sops
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.alex = import ../../users/alex;
      home-manager.extraSpecialArgs = { host = "homeserver"; };
      home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];

      users.users.alex.home = "/home/alex";
    }
  ];
}
