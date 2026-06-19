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
                  ;; gofmt + organize imports on save (handled by gopls)
                  (add-hook 'before-save-hook
                            (lambda ()
                              (call-interactively #'eglot-code-action-organize-imports))
                            nil t)
                  (add-hook 'before-save-hook #'eglot-format-buffer nil t))))

;; LSP configuration for Go
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((go-ts-mode go-mod-ts-mode) . ("gopls"))))
