;; Emacs Speaks Statistics
;; R itself (rWrapper) and the `air` language server below (air-formatter)
;; both come from modules/r-dev.

;; LSP for R — hooks OUTSIDE with-eval-after-load (eglot is deferred; see
;; 30-devel.el), only the server entry inside it.
(add-hook 'ess-r-mode-hook #'eglot-ensure)
(add-hook 'ess-r-mode-hook #'my/eglot-format-on-save) ; air formatting
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(ess-r-mode . ("air" "language-server"))))

(use-package ess
  :mode
  (("\\.[Rr]\\'"     . ess-r-mode)
   ("\\.Rprofile\\'" . ess-r-mode))
  :preface
  (defun my/ess-add-sent-code-to-history (proc string &rest _args)
    "Mirror STRING sent by ESS into the inferior's comint history."
    (when (and (string-match-p "[^[:space:]]" string) ; ignore pure whitespace
               (process-live-p proc))
      (when-let ((buf (process-buffer proc)))
        (with-current-buffer buf
          (when (derived-mode-p 'inferior-ess-mode)
            ;; One history entry per send (region/line/etc. as a single item)
            (comint-add-to-input-history string))))))

  (defun my/ess-at-cmdline-p ()
    (when-let ((proc (get-buffer-process (current-buffer))))
      (>= (point) (marker-position (process-mark proc)))))
  (defun my/ess-goto-cmdline ()
    (interactive)
    (goto-char (marker-position (process-mark (get-buffer-process (current-buffer))))))
  (defun my/ess-up-or-prev-line ()
    (interactive)
    (if (my/ess-at-cmdline-p) (comint-previous-input 1) (previous-line 1)))
  (defun my/ess-down-or-next-line ()
    (interactive)
    (if (my/ess-at-cmdline-p) (comint-next-input 1) (next-line 1)))

  (defun my/ess-repl-setup ()
    (setq-local comint-prompt-read-only t
                comint-input-ignoredups t
                comint-buffer-maximum-size 5000)
    (add-hook 'comint-output-filter-functions #'comint-truncate-buffer nil t))

  (defun my/ess-setup-eval-keys ()
    (local-set-key (kbd "C-c C-r")    #'ess-eval-region)
    (local-set-key (kbd "C-c C-b")    #'ess-eval-buffer)
    (local-set-key (kbd "C-c C-n")    #'ess-eval-line)
    (local-set-key (kbd "C-<return>") #'ess-eval-region-or-function-or-paragraph-and-step))

  (defun my/ess-inf-setup-navigate-keys ()
    (local-set-key (kbd "C-a")        #'my/ess-goto-cmdline)
    (local-set-key (kbd "<up>")       #'my/ess-up-or-prev-line)
    (local-set-key (kbd "<down>")     #'my/ess-down-or-next-line))
  :hook
  (ess-mode          . my/ess-setup-eval-keys)
  (inferior-ess-mode . my/ess-repl-setup)
  (inferior-ess-mode . my/ess-inf-setup-navigate-keys)
  :config
  (advice-add 'ess-send-string :after #'my/ess-add-sent-code-to-history)
  :custom
  (ess-ask-for-ess-directory nil)
  (ess-default-style 'RStudio)
  (ess-use-flymake nil))

(use-package ess-r-mode
  :after ess
  :ensure nil
  :no-require t
  :preface
  (defun my/ess-r-insert-pipe ()
    "Insert the R pipe operator `|>` at point, with preceding space."
    (interactive)
    (just-one-space 1)
    (insert "|> "))
  (defun my/ess-r-insert-pipe-and-newline ()
    "Insert the R pipe operator `|>` at point, with preceding space and followed by newline."
    (interactive)
    (end-of-line)
    (just-one-space 1)
    (insert "|>")
    (newline-and-indent))
  ;; C-S-m, RStudio's pipe chord — NOT under C-c p: a local binding there
  ;; would shadow the global cape-prefix-map (local prefixes don't merge with
  ;; global ones), killing every C-c p completion command in R buffers.
  :bind
  (:map ess-r-mode-map
        ("C-S-m"        . my/ess-r-insert-pipe)
        ("C-S-<return>" . my/ess-r-insert-pipe-and-newline))
  (:map inferior-ess-r-mode-map
        ("C-S-m"        . my/ess-r-insert-pipe)
        ("C-S-<return>" . my/ess-r-insert-pipe-and-newline))
  :custom
  (inferior-R-args "--no-save --no-restore-data --quiet"))

(use-package ess-smart-equals
  :after ess
  :config (ess-smart-equals-activate))

(use-package ess-view-data
  :after ess
  :bind
  (:map ess-r-mode-map
        ("C-c v" . ess-view-data-print)))

;; R-Markdown support. Only .Rmd goes to polymode — claiming plain .md from
;; here would drag every markdown file in every repo into polymode just
;; because the statistics module is installed (.md is emacs-dev's).
;; All deferred: a bare (use-package poly-R) requires it at startup, which
;; drags in all of ESS and TRAMP (~0.8s). poly-markdown+r-mode lives in
;; poly-R, so the :mode goes there.
(use-package polymode :defer t)
(use-package poly-markdown :defer t)
(use-package poly-R
  :mode ("\\.Rmd\\'" . poly-markdown+r-mode))

;; Quarto support
(use-package quarto-mode
  :mode (("\\.qmd\\'" . poly-quarto-mode))
  :bind
  (:map poly-quarto-mode-map
        ("C-c C-c" . polymode-eval-chunk)))
