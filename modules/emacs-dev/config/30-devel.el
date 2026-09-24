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
  :defer t ; :custom alone doesn't defer — without this eglot loads at startup
  :custom
  (eglot-sync-connect nil)
  (flymake-no-changes-timeout 0.8)
  (flymake-start-on-save-buffer t)
  (flymake-start-on-newline nil))

(defun my/eglot-format-on-save (&optional organize-imports)
  "Format the buffer through eglot before each save, in this buffer only.
With ORGANIZE-IMPORTS, run the server's organize-imports action first.
Meant for a language's mode hook (60+ files). Guarded: an error in
`before-save-hook' ABORTS the save, so a buffer the server isn't managing
\(no project, server not up yet under `eglot-sync-connect' nil) must still
be savable."
  (add-hook 'before-save-hook
            (lambda ()
              (when (and (fboundp 'eglot-managed-p) (eglot-managed-p))
                (when organize-imports
                  (ignore-errors
                    (eglot-code-action-organize-imports (point-min) (point-max))))
                (ignore-errors (eglot-format-buffer))))
            nil t))

;; Markdown (plain .md; .Rmd/.qmd belong to polymode in 80-ess.el)
(use-package markdown-mode
  :mode "\\.md\\'")

;; Git interface
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))
