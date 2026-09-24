;; Nix mode with tree-sitter (:mode alone claims .nix; treesit-auto in
;; 30-devel.el already covers the grammar side)
(use-package nix-ts-mode
  :mode ("\\.nix\\'" . nix-ts-mode)
  :hook
  (nix-ts-mode . (lambda ()
                   (setq-local indent-tabs-mode nil
                               tab-width 2
                               treesit-font-lock-level 4) ; Ensure maximum highlighting
                   ;; Force font-lock refresh
                   (when (fboundp 'treesit-font-lock-recompute-features)
                     (treesit-font-lock-recompute-features))))
  (nix-ts-mode . eglot-ensure))

;; LSP configuration for Nix
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nil"))))
