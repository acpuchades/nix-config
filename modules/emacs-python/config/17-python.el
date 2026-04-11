;; Python development configuration for Emacs

;; Python auto-formatter
(use-package blacken
  :hook
  (python-mode . blacken-mode)
  (python-ts-mode . blacken-mode)
  :custom 
  (blacken-line-length 100))

;; LSP configuration for Python
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("pyright-langserver" "--stdio")))
  
  ;; Enable eglot for Python modes
  (add-hook 'python-ts-mode-hook #'eglot-ensure)
  (add-hook 'python-mode-hook #'eglot-ensure))
