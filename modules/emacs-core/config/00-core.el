;; FUNCTION DEFINITIONS

(defun my/set-cursor-type ()
  "Change cursor shape depending on overwrite-mode."
  (setq cursor-type (if overwrite-mode 'box 'bar)))

;; PERFORMANCE TWEAKS

;; Larger buffer for subprocess I/O (faster LSP, git, etc.)
(setq read-process-output-max (* 4 1024 1024))

;; Faster redisplay
(setq fast-but-imprecise-scrolling          t
      redisplay-skip-fontification-on-input t
      inhibit-compacting-font-caches        t)

;; Speed up large/minified files
(global-so-long-mode 1)

;; Disable bidirectional text processing for speed
(setq bidi-paragraph-direction 'left-to-right
      bidi-inhibit-bpa                      t)

;; Line numbers: reserve width once to avoid reflow flicker
(setq display-line-numbers-width-start t)

;; Smoother scrolling (Emacs 29+)
(when (fboundp 'pixel-scroll-precision-mode)
  (pixel-scroll-precision-mode 1))

;; Smooth frame resizing
(setq frame-resize-pixelwise t)

;; PACKAGE CONFIG

(require 'package)
(package-initialize)

;; Bootstrap use-package if missing
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;; Global defaults for use-package
(eval-and-compile
  (setq use-package-always-ensure    t
        use-package-expand-minimally t))

;; Keep Emacs directories clean
(use-package no-littering
  :init
  ;; Store customization settings separately
  (setq custom-file
        (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file) (load custom-file :noerror))
  ;; Redirect backups/autosaves
  (setq backup-directory-alist
        `(("."  . ,(no-littering-expand-var-file-name "backup/"))))
  (setq auto-save-file-name-transforms
        `((".*"   ,(no-littering-expand-var-file-name "auto-save/") t)))
  (setq auto-save-list-file-prefix
        (no-littering-expand-var-file-name "auto-save/sessions/"))

  ;; Redirect histories & caches
  (setq recentf-save-file           (no-littering-expand-var-file-name   "recentf.el")
        savehist-file               (no-littering-expand-var-file-name  "savehist.el")
        save-place-file             (no-littering-expand-var-file-name "saveplace.el")
        bookmark-default-file       (no-littering-expand-var-file-name    "bookmarks")
        tramp-persistency-file-name (no-littering-expand-var-file-name        "tramp")
        url-history-file            (no-littering-expand-var-file-name  "url/history"))

  ;; Redirect Eshell history
  (setq eshell-history-file-name (no-littering-expand-var-file-name  "eshell/history")))


;; Direnv
(use-package direnv
  :config
  (direnv-mode 1)
  (setq direnv-always-show-summary t))

;; EditorConfig support
(use-package editorconfig
  :config (editorconfig-mode 1))


;; Envrc support
(use-package envrc
  :config
  (setq envrc-remote t)
  :hook
  (after-init . envrc-global-mode))

;; Eshell
(use-package eshell
  :bind ("C-x e" . eshell))

;; Eshell Toggle
(use-package eshell-toggle
  :bind ("C-c e" . eshell-toggle)
  :preface
  (defun my/eshell-toggle-close-window-on-exit ()
    "Close the window showing Eshell when exiting."
    (when (eq major-mode 'eshell-mode)
      ;; Only delete if there is more than one window in the frame
      (unless (one-window-p t)
        (delete-window))))
  :custom
  (eshell-toggle-size-fraction 3)
  (eshell-toggle-default-directory "~")
  (eshell-toggle-find-project-root-package 'project)
  (eshell-toggle-init-function #'eshell-toggle-init-eshell)
  :hook
  (eshell-exit . my/eshell-toggle-close-window-on-exit))

;; Fix PATH in GUI Emacs (macOS)
(use-package exec-path-from-shell
  :if (memq window-system '(mac ns x))
  :init
  (setq exec-path-from-shell-variables '("ANTHROPIC_API_KEY" "MANPATH" "PATH"))
  :config (exec-path-from-shell-initialize))

;; Smarter GC management
(use-package gcmh
  :preface
  ;; Defer GC while the minibuffer is active (snappier M-x etc.)
  (defun my/gc-minibuffer-setup ()
    (setq gc-cons-threshold most-positive-fixnum))
  ;; Restore a sane GC after minibuffer exits
  (defun my/gc-minibuffer-exit ()
    (setq gc-cons-threshold (* 128 1024 1024)
          gc-cons-percentage 0.1))
  :init
  (gcmh-mode 1)
  :custom
  (gcmh-idle-delay 2)
  (gcmh-high-cons-threshold (* 64 1024 1024))
  :hook
  (focus-out . #'garbage-collect)
  (minibuffer-setup . my/gc-minibuffer-setup)
  (minibuffer-exit  . my/gc-minibuffer-exit))



;; Auto-save files when idle
(use-package super-save
  :init (super-save-mode 1)
  :custom (super-save-auto-save-when-idle t))

;; TRAMP
(use-package tramp
  :defer t
  :config
  ;; Make TRAMP also use the remote user's own PATH
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))


;; Indentation & whitespace
(use-package whitespace
  :ensure nil
  :custom
  (require-final-newline t))

(use-package yasnippet
  :preface
  (defun my/yas-alias-tree-sitter-modes ()
    "Alias tree-sitter modes to their non-ts counterparts for yasnippet"
    (when (boundp 'yas-extra-modes)
      (pcase major-mode
        ('bash-ts-mode       (add-to-list 'yas-extra-modes 'sh-mode))
        ('c-ts-mode          (add-to-list 'yas-extra-modes 'c-mode))
        ('c++-ts-mode        (add-to-list 'yas-extra-modes 'c++-mode))
        ('css-ts-mode        (add-to-list 'yas-extra-modes 'css-mode))
        ('javascript-ts-mode (add-to-list 'yas-extra-modes 'js-mode))
        ('python-ts-mode     (add-to-list 'yas-extra-modes 'python-mode))
        ('typescript-ts-mode (add-to-list 'yas-extra-modes 'typescript-mode))
        ('json-ts-mode       (add-to-list 'yas-extra-modes 'json-mode))
        ('yaml-ts-mode       (add-to-list 'yas-extra-modes 'yaml-mode))
        )))
  :hook
  ((prog-mode      . yas-minor-mode)
   (text-mode      . yas-minor-mode)
   (yas-minor-mode . my/yas-alias-tree-sitter-modes))
  :init
  (add-to-list 'yas-snippet-dirs "~/.emacs.d/snippets")
  :config
  (yas-reload-all)
  (setq yas-fallback-behavior 'auto))

(use-package yasnippet-snippets
  :after yasnippet)
