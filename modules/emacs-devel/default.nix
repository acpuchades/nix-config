{ config, lib, pkgs, ... }:

{
  options.my.emacs-devel = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for development.";
    };
  };

  config = {
    # Configure Emacs with development packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [

        # Development tools
        aidermacs
        magit
        treesit-auto

        # Python
        blacken

        # Nix
        nix-ts-mode

      ] ++ config.my.emacs-devel.extraPackages;
    };

    # Install tree-sitter grammars at system level
    home.packages = with pkgs; [
      tree-sitter-grammars.tree-sitter-nix
    ];

    # Set environment variable for tree-sitter grammar location
    home.sessionVariables = {
      TREE_SITTER_GRAMMAR_PATH = "${pkgs.tree-sitter-grammars.tree-sitter-nix}/lib";
    };

    # Development configuration that will be loaded by init.el
    home.file.".emacs.d/config/15-devel.el".source = ./config/15-devel.el;
  };
}
