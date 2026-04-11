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

;; Python auto-formatter
(use-package blacken
  :hook
  (python-mode . blacken-mode)
  (python-ts-mode . blacken-mode)
  :custom (blacken-line-length 100))

;; LSP client (built-in)
(use-package eglot
  :ensure nil
  :hook
  (ess-r-mode     . eglot-ensure)
  (nix-ts-mode    . eglot-ensure)
  (python-ts-mode . eglot-ensure)
  :custom
  (eglot-sync-connect nil)
  (flymake-no-changes-timeout 0.8)
  (flymake-start-on-save-buffer t)
  (flymake-start-on-newline nil)
  :config
  (add-to-list 'eglot-server-programs
               '(nix-ts-mode  . ("nil")))
  (add-to-list 'eglot-server-programs
               '(ess-r-mode   . ("air" "language-server")))
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("pyright-langserver" "--stdio"))))

;; Git interface
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))

;; Nix
(use-package nix-ts-mode
  :mode ("\\.nix\\'" . nix-ts-mode)
  :config (treesit-auto-add-to-auto-mode-alist 'nix)
  :hook (nix-ts-mode . (lambda ()
    (setq-local indent-tabs-mode nil tab-width 2))))

;; Load ESS configuration if available
(when (file-exists-p "~/.emacs.d/ess-config.el")
  (load-file "~/.emacs.d/ess-config.el"))
