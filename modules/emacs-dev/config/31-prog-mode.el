;; Programming mode configuration

;; Multiple cursors
(use-package multiple-cursors
  :bind
  (("C->"     . mc/mark-next-like-this)
   ("C-<"     . mc/mark-previous-like-this)
   ("C-c C-<" . mc/mark-all-like-this)))

;; Project management (built-in). ~/GitHub only exists on the MacBook (on the
;; homeserver it is an unreadable symlink target), so guard the scan.
(use-package project
  :ensure nil
  :config
  (when (file-directory-p "~/GitHub")
    (project-remember-projects-under "~/GitHub")))

;; Rainbow delimiters
(use-package rainbow-delimiters
  :hook ((prog-mode conf-mode) . rainbow-delimiters-mode))

;; Rainbow mode — only where colour literals are the content: scanning every
;; prog buffer for them is font-lock work nearly all code never needs.
(use-package rainbow-mode
  :hook ((css-mode css-ts-mode html-mode conf-mode) . rainbow-mode)
  :custom (rainbow-x-colors nil)) ; avoid huge X11 name list in completions

;; Which-key help
(use-package which-key
  :init (which-key-mode))

;; Whitespace for programming modes
(use-package whitespace
  :ensure nil
  :hook
  (prog-mode . (lambda ()
                 (whitespace-mode 1)
                 (add-hook 'before-save-hook 'whitespace-cleanup nil t)))
  :custom
  (whitespace-style '(
                      empty
                      face
                      ;; no `spaces': a face on every space in every buffer
                      ;; is pure font-lock cost for an invisible result
                      space-before-tab
                      space-after-tab
                      tabs
                      tab-mark
                      trailing
                      )))

;; Programming mode hooks
(add-hook 'prog-mode-hook #'hl-line-mode)  ;; highlight line
(add-hook 'prog-mode-hook #'column-number-mode)  ;; column numbers
(setq display-line-numbers-type 'visual)  ;; offsets in screen rows from current line
(add-hook 'prog-mode-hook #'display-line-numbers-mode)  ;; line numbers

;; Fill column indicator
(setq display-fill-column-indicator-column 100)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)
