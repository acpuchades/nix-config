# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  sops-nix,
  disko,
  emacs-overlay,
  fugazi-web,
  fugazi-web-testing,
  nix-caddy-withplugins,
  ...
}:

let

  # `lib` is a module argument, so it is in scope inside `configuration` below but
  # NOT out here — and pkgsUnstable's allowInsecurePredicate needs it. Taken from
  # the flake input, which is the same lib the module system passes in. The inner
  # function's own `lib` parameter shadows this one within its body, harmlessly:
  # they are equal.
  inherit (nixpkgs) lib;

  homeServerLocalAddress = "192.168.2.2";

  # The physical uplink, named ONCE. Interface names are derived from the
  # device's PCI/USB path, so they are a property of the hardware and not of
  # this configuration: the same config on another box calls its wireless NIC
  # something else, and every reference here silently stops matching. That is
  # three separate outages at once — no static LAN address (the networkd network
  # in ./networking.nix), no association (networking.wireless.interfaces), and no NAT for
  # WireGuard clients (my.vpn-server.upstreamInterface) — for a box whose only
  # uplink is this radio, so there is no second path to log in and fix it.
  # Exported through _module.args below so ./networking.nix and ./vpn.nix read
  # the same string; grep for it before moving hardware, and change it here only.
  uplinkInterface = "wlp3s0";
  adminEmailAddress = "admin@acpuchades.com";

  # nixpkgs-unstable, instantiated ONCE for the handful of packages this host
  # deliberately runs ahead of nixpkgs-26.05. Three consumers today: openclaw and
  # immich, each with its reason written at its use site (./apps.nix, ./eva.nix), plus claude-code —
  # that one via ../../modules/claude-code/system.nix, which both machines import
  # and which takes this set as an argument rather than importing unstable again.
  # Shared rather than imported per consumer because `import <nixpkgs>` is a full
  # evaluation of the package set: doing it twice doubles that cost to produce two
  # package sets that differ only in a config flag neither of them changes a
  # derivation with.
  #
  # Both permits below are predicates on the package NAME rather than blanket
  # flags, so each stays scoped to the one package that needs it and does not
  # quietly bless anything else pulled from here — immich included, which is the
  # whole point of taking it from unstable rather than permitting 26.05's.
  #
  # The insecure permit is openclaw's (upstream marks every release
  # knownVulnerabilities for LLM prompt injection).
  #
  # The unfree permit is claude-code's. Note this instance does NOT inherit the
  # host's `nixpkgs.config.allowUnfree` (settings.nix): that option configures the
  # module system's own `pkgs`, and this is a separate nixpkgs evaluation, so an
  # unfree package taken from here is refused unless permitted right here.
  pkgsUnstable = import nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowInsecurePredicate = p: lib.getName p == "openclaw";
      allowUnfreePredicate = p: lib.getName p == "claude-code";
    };
  };

  configuration =
    inputs@{
      config,
      options,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        # Include the results of the hardware scan.
        ./hardware-configuration.nix

        # Host files, imported as modules so they merge with full option
        # semantics (never `import … // { … }`: a shallow `//` silently drops
        # any top-level key both sides set).
        ./settings.nix
        ./services.nix
        ./networking.nix
        ./sops.nix
        ./users.nix

        # Service configuration, by area. Each file imports the modules it
        # configures.
        ./vpn.nix
        (import ./web.nix { inherit nix-caddy-withplugins; })
        ./apps.nix
        ./eva.nix
        ./monitoring.nix
        ./backup.nix

        # Library module used by several of the above.
        ../../modules/firewall-allow

        # Disk layout as provisioning metadata only — enableConfig = false in
        # ./disko.nix, so this changes nothing at runtime; see its header.
        disko.nixosModules.disko
        ./disko.nix

        # fugazi-web (testing.fugazitrade.com), in its own file: the service is
        # large enough that its policy helpers and instance configuration were
        # about half of this one. Curried over the flake inputs because its own
        # `imports` needs them — see the header there.
        (import ./fugazi.nix { inherit fugazi-web fugazi-web-testing; })
      ];

      # Host constants as module arguments, so the files imported above name
      # them without re-declaring them.
      _module.args = {
        inherit
          uplinkInterface
          adminEmailAddress
          homeServerLocalAddress
          pkgsUnstable
          ;
      };

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = import ./packages.nix inputs;

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
  modules =
    import ../common.nix {
      host = "homeserver";
      homeDirectory = "/home/alex";
      inherit sops-nix emacs-overlay pkgsUnstable;
    }
    ++ [
      configuration
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
    ];
}
