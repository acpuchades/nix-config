{ config, lib, pkgs, ... }:

{
  options.my.emacs-nix = {
    enable = lib.mkEnableOption "Emacs Nix development environment";
    
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for Nix development.";
    };

    tabWidth = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Tab width for Nix files.";
    };
  };

  config = lib.mkIf config.my.emacs-nix.enable {
    # Herramientas del sistema necesarias para Emacs
    home.packages = with pkgs; [
      nil  # Nix LSP server
    ];

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        nix-ts-mode
      ] ++ config.my.emacs-nix.extraPackages;
    };

    # Configuración de Nix para Emacs
    home.file.".emacs.d/config/18-nix.el".text = ''
      ;; Nix development configuration for Emacs

      ;; Nix mode with tree-sitter
      (use-package nix-ts-mode
        :mode ("\\.nix\\'" . nix-ts-mode)
        :config 
        (treesit-auto-add-to-auto-mode-alist 'nix)
        :hook 
        (nix-ts-mode . (lambda ()
          (setq-local indent-tabs-mode nil 
                      tab-width ${toString config.my.emacs-nix.tabWidth}
                      treesit-font-lock-level 4) ; Ensure maximum highlighting
          ;; Force font-lock refresh
          (when (fboundp 'treesit-font-lock-recompute-features)
            (treesit-font-lock-recompute-features))))
        (nix-ts-mode . eglot-ensure))

      ;; LSP configuration for Nix
      (with-eval-after-load 'eglot
        (add-to-list 'eglot-server-programs
                     '(nix-ts-mode . ("nil"))))
    '';
  };
}
