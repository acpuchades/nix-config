;; Go development configuration for Emacs

;; Go mode with tree-sitter (built-in)
(use-package go-ts-mode
  :ensure nil
  :mode (("\\.go\\'"     . go-ts-mode)
         ("/go\\.mod\\'" . go-mod-ts-mode))
  :custom
  (go-ts-mode-indent-offset 4)
  :hook
  (go-ts-mode . eglot-ensure)
  (go-ts-mode . (lambda ()
                  ;; gofmt + organize imports on save (handled by gopls).
                  ;; Guarded: an error in before-save-hook ABORTS the save, so
                  ;; a buffer gopls isn't managing (no go.mod, server not up
                  ;; yet under eglot-sync-connect nil) must still be savable.
                  (add-hook 'before-save-hook
                            (lambda ()
                              (when (and (fboundp 'eglot-managed-p) (eglot-managed-p))
                                (ignore-errors
                                  (eglot-code-action-organize-imports (point-min) (point-max)))))
                            nil t)
                  (add-hook 'before-save-hook
                            (lambda ()
                              (when (and (fboundp 'eglot-managed-p) (eglot-managed-p))
                                (ignore-errors (eglot-format-buffer))))
                            nil t))))

;; LSP configuration for Go
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((go-ts-mode go-mod-ts-mode) . ("gopls"))))
