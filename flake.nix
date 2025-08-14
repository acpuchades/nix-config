{
  description = "Alejandro's nix-darwin system flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Nix-Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
    }:
    {
      # Build darwin flake using:
      # $ sudo darwin-rebuild switch --flake .#MacBook-Pro-de-Alejandro
      darwinConfigurations."MacBook-Pro-de-Alejandro" = import ./hosts/macbookpro {
        inherit
          self
          nixpkgs
          nix-darwin
          home-manager
          ;
      };

      nixosConfigurations."homeserver" = import ./hosts/homeserver {
        inherit
          self
          nixpkgs
          home-manager
          ;
      };
    };
}
