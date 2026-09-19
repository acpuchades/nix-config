{ config, lib, pkgs, ... }:

{
  options.my.emacs-nix = {
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

  config = {
    # The `nil` LSP binary comes from modules/nix-dev — the *-dev modules own
    # toolchains, the emacs-* modules own elisp.

    # Paquetes de Emacs
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        nix-ts-mode
      ] ++ config.my.emacs-nix.extraPackages;
    };

    # Configuración de Nix para Emacs
    home.file.".emacs.d/config/65-nix.el".text = ''
      ;; Nix mode with tree-sitter (:mode alone claims .nix; treesit-auto in
      ;; 30-devel.el already covers the grammar side)
      (use-package nix-ts-mode
        :mode ("\\.nix\\'" . nix-ts-mode)
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
        (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nil"))))
    '';
  };
}
