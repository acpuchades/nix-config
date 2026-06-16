{
  description = "Alejandro's nix-darwin system flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Nix-Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Sops-Nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Impermanence (ephemeral root, persisted state)
    impermanence.url = "github:nix-community/impermanence";

    # Better Zen — Betterfox-derived privacy/security user.js for Zen browser
    better-zen.url = "github:Codextor/better-zen";
    better-zen.flake = false;
  };

  outputs =
    outputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      sops-nix,
      impermanence,
      better-zen
    }:
  {
    # Build darwin flake using:
    # $ sudo darwin-rebuild switch --flake .#MacBook-Pro-de-Alejandro
    darwinConfigurations."MacBook-Pro-de-Alejandro" = import ./machines/macbookpro outputs;
    nixosConfigurations."homeserver" = import ./machines/homeserver outputs;
  };
}
