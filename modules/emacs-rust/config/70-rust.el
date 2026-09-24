;; Rust development configuration for Emacs

;; Rust mode with tree-sitter (built-in)
(use-package rust-ts-mode
  :ensure nil
  :mode ("\\.rs\\'" . rust-ts-mode)
  :custom
  (rust-ts-mode-indent-offset 4)
  :hook
  (rust-ts-mode . eglot-ensure)
  (rust-ts-mode . my/eglot-format-on-save)) ; rustfmt via rust-analyzer

;; Cargo command integration
(use-package cargo-mode
  :hook (rust-ts-mode . cargo-minor-mode))

;; LSP configuration for Rust
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(rust-ts-mode . ("rust-analyzer"))))
