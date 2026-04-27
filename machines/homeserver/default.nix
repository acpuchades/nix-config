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

  homeServerLocalAddress = "192.168.2.2";
  adminEmailAddress = "admin@acpuchades.com";

  configuration =
    inputs@{ config, lib, pkgs, ... }:
    import ./settings.nix inputs // {
      imports = [
        # Include the results of thpe hardware scan.
        ./hardware-configuration.nix

        # Custom modules
        ../../modules/vpn-server
        ../../modules/dns-filtering
        ../../modules/web-server
        ../../modules/postgresql-server
        ../../modules/cloud-suite
        ../../modules/mail-relay
        ../../modules/prefect-server
        ../../modules/home-assistant
      ];

      # SOPS-Nix configuration
      sops = import ./sops.nix inputs;

      # User configuration
      users = import ./users.nix inputs;

      systemd.network.networks = {
        "10-wlp3s0" = {
          matchConfig.Name = "wlp3s0";
          networkConfig = {
            DHCP = "yes";
            DNS = [ "127.0.0.1" ];
          };
        };
      };

      security.tpm2.enable = true;
      security.tpm2.pkcs11.enable = true;
      security.tpm2.tctiEnvironment.enable = true;

      environment.etc."crypttab".text = ''
        srv-encrypted /dev/disk/by-uuid/c5e7c042-5625-493f-9b8a-487ecdac277a - /tpm2-device=auto,discard
      '';

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = import ./packages.nix inputs;

      # Configure custom modules
      my.vpn-server = {
        enable = true;
        privateKeyFile = config.sops.secrets."wireguard/private-key".path;
        serverPublicKey = "dnwEk7CRGfzDFJruRiCzmGNURU6Ba/OLUDpQ5ImO7G4=";
        serverEndpoint = "vpn.acpuchades.com:51820";
        clientDns = "10.0.0.1";
        upstreamInterface = "wlp3s0";
      };

      my.dns-filtering = {
        enable = true;
        adguardPort = 3000;
        dnsPort = 53;
        dnsResolverPort = 5300;
        basicAuthFile = config.sops.templates."caddy/adguard-auth".path;
        virtualHost = "adguard.acpuchades.com";
        dnsRewrites = [
          { domain = "home.acpuchades.com";      answer = homeServerLocalAddress; }
          { domain = "adguard.acpuchades.com";   answer = homeServerLocalAddress; }
          { domain = "bitwarden.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "photos.acpuchades.com";    answer = homeServerLocalAddress; }
          { domain = "cloud.acpuchades.com";     answer = homeServerLocalAddress; }
          { domain = "collabora.acpuchades.com"; answer = homeServerLocalAddress; }
          { domain = "prefect.acpuchades.com";   answer = homeServerLocalAddress; }
        ];
      };

      my.web-server = {
        enable = true;
        adminEmail = adminEmailAddress;
        virtualHosts = {
          "prefect.acpuchades.com" = {
            proxyPass = "http://127.0.0.1:4200";
            proxyWebsockets = true;
            basicAuthFile = config.sops.templates."caddy/prefect-auth".path;
          };
          "www.acpuchades.com" = {
            root = "/var/www/acpuchades.com";
          };
        };
      };

      my.postgresql-server = {
        enable = true;
        dataDir = "/srv/encrypted/postgresql";
      };

      my.cloud-suite = {
        enable = true;
        bitwarden = {
          hostName = "bitwarden.acpuchades.com";
          signupsAllowed = false;
          dataDir = "/srv/encrypted/vaultwarden";
        };
        collabora = {
          hostName = "collabora.acpuchades.com";
          port = 9980;
        };
        email = {
          from = "noreply@acpuchades.com";
        };
        immich = {
          hostName = "photos.acpuchades.com";
          mediaLocation = "/srv/encrypted/immich";
        };
        nextcloud = {
          hostName = "cloud.acpuchades.com";
          adminPasswordFile = config.sops.secrets."nextcloud/admin-pass".path;
          maxUploadSize = "2G";
          phoneRegion = "ES";
          dataDir = "/srv/encrypted/nextcloud";
        };
      };

      my.mail-relay = {
        enable = true;
        origin = "acpuchades.com";
        hostname = "home.acpuchades.com";
        relayHost = "[in-v3.mailjet.com]:587";
        saslPasswordFile = config.sops.templates."postfix/sasl_passwd".path;
        destinations = ["localhost" "localhost.localdomain"];
      };

      my.home-assistant = {
        enable = true;
        hostName = "home.acpuchades.com";
        extraComponents = [
          "alexa_devices"
          "conversation"
          "hue"
          "met"
          "smartthings"
          "spotify"
          "stream"
        ];
        email.from = "noreply@acpuchades.com";
        email.recipient = adminEmailAddress;
      };

      my.prefect-server = {
        enable = true;
        host = "0.0.0.0";
        port = 4200;
        dataDir = "/srv/prefect";
        baseUrl = "https://prefect.acpuchades.com";
        workerPools.default.installPolicy = "if-not-present";
      };

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

    ../../modules/r-dev/system.nix

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
