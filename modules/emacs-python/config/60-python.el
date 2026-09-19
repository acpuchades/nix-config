;; Python development configuration for Emacs

;; Python auto-formatter
(use-package blacken
  :hook
  (python-mode . blacken-mode)
  (python-ts-mode . blacken-mode)
  :custom
  (blacken-line-length 100))

;; LSP for Python. The hooks live OUTSIDE with-eval-after-load: eglot is
;; deferred (30-devel.el loads it via :hook), so hooks registered only after
;; eglot loads would never install — nothing would ever trigger the load.
(add-hook 'python-ts-mode-hook #'eglot-ensure)
(add-hook 'python-mode-hook #'eglot-ensure)

(with-eval-after-load 'eglot
  ;; (MODES...) . CONTACT — a malformed entry here makes eglot read part of
  ;; the mode list as the server command (cf. 75-go.el for the same shape).
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio"))))
