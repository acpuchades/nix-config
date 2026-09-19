;; Tree-sitter auto mode installation
(use-package treesit-auto
  :custom
    (treesit-font-lock-level 4) ; Maximum syntax highlighting
    (treesit-auto-install nil) ; Don't install grammars, use system ones
  :config
    (treesit-auto-add-to-auto-mode-alist 'all)
    (global-treesit-auto-mode))

;; LSP client (built-in). Language wiring lives in each language's own module
;; (60-python, 65-nix, 70-rust, 75-go, 80-ess): its eglot-ensure hooks go
;; DIRECTLY on the mode hook — never inside with-eval-after-load 'eglot, which
;; only runs once something else loads eglot — and only its
;; eglot-server-programs entry goes inside with-eval-after-load.
(use-package eglot
  :ensure nil
  :custom
  (eglot-sync-connect nil)
  (flymake-no-changes-timeout 0.8)
  (flymake-start-on-save-buffer t)
  (flymake-start-on-newline nil))

;; Git interface
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))
