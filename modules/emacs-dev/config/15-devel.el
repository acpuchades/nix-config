;; Tree-sitter auto mode installation
(use-package treesit-auto
  :custom
    (treesit-font-lock-level 4) ; Maximum syntax highlighting
    (treesit-auto-install nil) ; Don't install grammars, use system ones
  :config
    (treesit-auto-add-to-auto-mode-alist 'all)
    (global-treesit-auto-mode))

;; LSP client (built-in)
(use-package eglot
  :ensure nil
  :hook
  (ess-r-mode     . eglot-ensure)
  :custom
  (eglot-sync-connect nil)
  (flymake-no-changes-timeout 0.8)
  (flymake-start-on-save-buffer t)
  (flymake-start-on-newline nil)
  :config
  (add-to-list 'eglot-server-programs
               '(ess-r-mode   . ("air" "language-server"))))

;; Git interface
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))
