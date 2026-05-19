{
  description = "Alejandro's nix-darwin system flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    # Nix-Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Sops-Nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Impermanence (ephemeral root, persisted state)
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    outputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      sops-nix,
      impermanence
    }:
  {
    # Build darwin flake using:
    # $ sudo darwin-rebuild switch --flake .#MacBook-Pro-de-Alejandro
    darwinConfigurations."MacBook-Pro-de-Alejandro" = import ./machines/macbookpro outputs;
    nixosConfigurations."homeserver" = import ./machines/homeserver outputs;
  };
}
