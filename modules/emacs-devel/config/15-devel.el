;; Tree-sitter auto mode installation
(use-package treesit-auto
  :custom
    (treesit-font-lock-level 4) ; Maximum syntax highlighting
    (treesit-auto-install nil) ; Don't install grammars, use system ones
  :config
    (treesit-auto-add-to-auto-mode-alist 'all)
    (global-treesit-auto-mode))

;; Aider integration
(use-package aidermacs
  :bind (("C-c A" . aidermacs-transient-menu))
  :init
  (add-to-list 'display-buffer-alist
               '("\\*Aider\\*"
                 (display-buffer-in-side-window)
                 (side              . right)
                 (window-width      .   0.4)
                 (window-parameters . ((no-other-window . t)
                                       (no-delete-other-windows . t)))))
  :custom
  (aidermacs-default-model "sonnet"))

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
