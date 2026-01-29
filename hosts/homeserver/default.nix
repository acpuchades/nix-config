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
    import ./settings.nix inputs // {
      imports = [
        # Include the results of thpe hardware scan.
        ./hardware-configuration.nix
      ];

      # SOPS-Nix configuration.
      sops.defaultSopsFile = ./secrets/default.yml;
      sops.defaultSopsFormat = "yaml";
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      sops.secrets = {
        "ddclient/domain" = { key = "ddclient/domain"; };
        "ddclient/password" = { key = "ddclient/password"; };

        "mailjet/token" = { key = "mailjet/token"; };
        "mailjet/secret" = { key = "mailjet/secret"; };

        "passwd/alex" = {
          key = "passwd/alex";
          neededForUsers = true;
        };

        "nginx/htpasswd/adguard" = {
          owner = "nginx";
          group = "nginx";
          mode = "0400";
        };

        "nginx/htpasswd/prefect" = {
          owner = "nginx";
          group = "nginx";
          mode = "0400";
        };

        "vpn/in/wg-private-key" = { key = "vpn/in/wg-private-key"; };
        "vpn/in/wifi-password" = { key = "vpn/in/wifi-password"; };

        "wg/server/private-key" = { key = "wireguard/server/privatekey"; };
        "wg/peers/alex-iphone/psk" = { key = "wireguard/peers/alex-iphone/psk"; };
        "wg/peers/alex-ipad/psk" = { key = "wireguard/peers/alex-ipad/psk"; };
        "wg/peers/alex-macbookpro/psk" = { key = "wireguard/peers/alex-macbookpro/psk"; };
        "wg/peers/mubin-phone/psk" = { key = "wireguard/peers/mubin-phone/psk"; };
        "wg/peers/mubin-laptop/psk" = { key = "wireguard/peers/mubin-laptop/psk"; };

        "wifi/network" = { key = "wifi/network"; };
        "wifi/password" = { key = "wifi/password"; };
      };

      sops.templates."ddclient/config".content = ''
        use=web, web=checkip.amazonaws.com
        protocol=namecheap
        server=dynamicdns.park-your-domain.com
        login=${config.sops.placeholder."ddclient/domain"}
        password=${config.sops.placeholder."ddclient/password"}
        www,adguard,bitwarden,home,prefect
        '';

      sops.templates."postfix/sasl_passwd" = {
        owner = "postfix";
        group = "postfix";
        mode = "0400";
        content = ''
          [in-v3.mailjet.com]:587 ${config.sops.placeholder."mailjet/token"}:${config.sops.placeholder."mailjet/secret"}
        '';
      };

      sops.templates."wifi/secrets".content = ''
        home-wlan-psk=${config.sops.placeholder."wifi/password"}
      '';

      systemd.network.networks = {
        "10-wlp3s0" = {
          matchConfig.Name = "wlp3s0";
          networkConfig = {
            DHCP = "yes";
            DNS = [ "127.0.0.1" ];
          };
        };
      };

      users = import ./users.nix inputs;

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = import ./packages.nix inputs;

      # List configuration files to be stored under /etc.
      environment.etc."fugazi/config.toml" = {
        source = ./files/fugazi/config.toml;
        mode = "0440";
        user = "fugazi";
        group = "fugazi";

      };

      systemd.tmpfiles.rules = [
        "d /srv/fugazi 2770 fugazi fugazi -"
      ];

      # List services that you want to enable:
      services = import ./services.nix inputs;

      # Networking configuration.
      networking = import ./networking.nix inputs;

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
