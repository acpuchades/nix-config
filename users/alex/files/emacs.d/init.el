;; FUNCTION DEFINITIONS

(defun my/enable-dark-mode ()
  "Enable dark mode by activating dark theme"
  (unless (eq catppuccin-flavor 'mocha)
    (setq catppuccin-flavor 'mocha)
    (catppuccin-reload)))

(defun my/enable-light-mode ()
  "Enable light mode by activating light theme"
  (unless (eq catppuccin-flavor 'latte)
    (setq catppuccin-flavor 'latte)
    (catppuccin-reload)))

(defun my/apply-system-appearance ()
  "Apply appropriate theme depending on system mode"
  (if (eq (frame-parameter nil 'background-mode) 'dark)
      (my/enable-dark-mode) (my/enable-light-mode)))

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

;; Manually initialize packages (auto-init is disabled in early-init.el)
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

;; Auto switch theme based on system appearance
(use-package auto-dark
  :if (display-graphic-p)
  :after catppuccin-theme
  :custom
  (auto-dark-allow-osascript t) ;; macOS detection
  (auto-dark-polling-interval-seconds 2) ;; Check every 2s
  :init
  (auto-dark-mode 1)
  :hook
  (window-setup . my/apply-system-appearance)
  (auto-dark-dark-mode  . my/enable-dark-mode)
  (auto-dark-light-mode . my/enable-light-mode))

;; Python auto-formatter
(use-package blacken
  :hook
  (python-mode . blacken-mode)
  (python-ts-mode . blacken-mode)
  :custom (blacken-line-length 100))

;; Completion at point extensions
(use-package cape
  :bind ("C-c p" . cape-prefix-map) ;; Alternative key: M-<tab>, M-p, M-+
  :init
  ;; Add to the global default value of `completion-at-point-functions' which is
  ;; used by `completion-at-point'.  The order of the functions matters, the
  ;; first function returning a result wins.  Note that the list of buffer-local
  ;; completion functions takes precedence over the global list.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block)
  (add-hook 'completion-at-point-functions #'cape-elisp-symbol)
  (add-hook 'completion-at-point-functions #'cape-history)
  (add-hook 'completion-at-point-functions #'cape-keyword)
  (add-hook 'completion-at-point-functions #'cape-emoji))

;; Catppuccin theme setup
(use-package catppuccin-theme
  :custom
  (catppuccin-flavor 'latte)
  :config
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'catppuccin :no-confirm))

;; Consult
(use-package consult
  :bind (
  ;; C-c bindings (prefix map)
  ("C-c h"   . consult-history)
  ("C-c m"   . consult-mode-command)
  ("C-c k"   . consult-kmacro)
  ;; C-x bindings (ctl-x-map)
  ("C-x M-:" . consult-complex-command)
  ("C-x b"   . consult-buffer)
  ("C-x C-b" . consult-buffer)
  ("C-x 4 b" . consult-buffer-other-window)
  ("C-x 5 b" . consult-buffer-other-frame)
  ("C-x r b" . consult-bookmark)
  ("C-x p b" . consult-project-buffer)
  ;; M-g bindings (goto-map)
  ("M-g g"   . consult-goto-line)
  ("M-g M-g" . consult-goto-line)
  ;; M-s bindings (search-map)
  ("M-s r"   . consult-ripgrep)
  ("M-s l"   . consult-line)
  ("M-s L"   . consult-line-multi)
  ("M-s m"   . consult-multi-occur)
  ("M-s k"   . consult-keep-lines)
  ("M-s u"   . consult-focus-lines)))

;; Completion UI
(use-package corfu
  :init
    (global-corfu-mode) ;; Enable globally
  :custom
    (corfu-auto t)     ;; Enable auto completion
    (corfu-auto-delay 0.5)   ;; Adjust delay for completion popup
    (corfu-auto-prefix 1)    ;; Show popup after 1 char
    (corfu-quit-no-match 'separator) ;; Don't quit on no match, allow separator
    (corfu-scroll-margin 2)  ;; Keep popup from touching edges
    (corfu-cycle t)    ;; Cycle through candidates
    (corfu-preselect 'prompt)  ;; Don't auto select first
    (corfu-quit-at-boundary t) ;; Quit when no further completion is possible
  :bind
    (:map corfu-map ("M-SPC" . corfu-insert-separator)))

;; Dashboard
(use-package dashboard
  :custom
  (dashboard-startup-banner "~/.emacs.d/share/logo.svg")
  (dashboard-center-content t)
  (dashboard-verticallly-center-content t)
  (dashboard-display-icons-p t)
  (dashboard-icon-type 'nerd-icons)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-items '((projects  . 5)
                     (recents   . 5)
                     (bookmarks . 5)
                     (agenda    . 5)))
  :config
  (dashboard-setup-startup-hook))

;; Doom modeline
(use-package doom-modeline
  :hook (after-init . doom-modeline-mode))

;; EditorConfig support
(use-package editorconfig
  :config (editorconfig-mode 1))

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
               '(ess-r-mode   . ("R" "--slave" "-e" "languageserver::run()")))
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("pyright-langserver" "--stdio"))))

;; Embark
(use-package embark
  :bind
  (("C-."   . embark-act)   ;; pick some comfortable binding
   ("C-;"   . embark-dwim)  ;; good alternative: do-what-I-mean
   ("C-h B" . embark-bindings)))  ;; show all availEmbark integration

(use-package embark-consult
  :after (embark consult)
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

;; Envrc support
(use-package envrc
  :hook (after-init . envrc-global-mode))

;; Emacs Speaks Statistics (R Support)
(use-package ess
  :mode
  (("\\.[Rr]\\'"   . ess-r-mode)
   ("\\.Rprofile\\'" . ess-r-mode))
  :custom
    (ess-ask-for-ess-directory nil)
    (ess-indent-offset   2)
    (ess-use-flymake     nil))

(use-package ess-r-mode
  :after ess
  :ensure nil
  :no-require t
  :bind (:map ess-r-mode-map
        ("C-c C-r"  . ess-eval-region)
        ("C-c C-b"  . ess-eval-buffer)
        ("C-c C-n"  . ess-eval-line)
        ("C-<return>" . ess-eval-region-or-function-or-paragraph-and-step)))

(use-package ess-smart-equals
  :after ess
  :config (ess-smart-equals-activate))

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
    (focus-out  . #'garbage-collect)
    (minibuffer-setup . my/gc-minibuffer-setup)
    (minibuffer-exit  . my/gc-minibuffer-exit))

;; Ligatures
(use-package ligature
  :config
  ;; Enable the "www" ligature in every possible major mode
  (ligature-set-ligatures 't '("www"))
  ;; Enable traditional ligature support in eww-mode, if the
  ;; `variable-pitch' face supports it
  (ligature-set-ligatures 'eww-mode '("ff" "fi" "ffi"))
  ;; Enable all Cascadia Code ligatures in programming modes
  (ligature-set-ligatures 'prog-mode
    '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
      ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
      "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
      "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
      "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
      "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
      "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
      "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
      ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
      "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
      "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
      "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
      "\\\\" "://"))
  (global-ligature-mode t))

;; Git interface
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))

;; Rich minibuffer annotations
(use-package marginalia
  :init (marginalia-mode))

;; Multiple cursors
(use-package multiple-cursors
  :bind
  (("C->"     . mc/mark-next-like-this)
   ("C-<"     . mc/mark-previous-like-this)
   ("C-c C-<" . mc/mark-all-like-this)))

;; Nerd icons everywhere
(use-package nerd-icons)
(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))
(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))
(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

;; Nix
(use-package nix-ts-mode
  :mode ("\\.nix\\'" . nix-ts-mode)
  :config (treesit-auto-add-to-auto-mode-alist 'nix)
  :hook (nix-ts-mode . (lambda ()
    (setq-local indent-tabs-mode nil tab-width 2))))

;; Fuzzy matching
(use-package orderless
  :init (setq completion-styles '(orderless basic)))

;; Org mode tweaks
(use-package org
  :mode ("\\.org\\'" . org-mode)
  :hook (org-mode . org-indent-mode)
  :custom
    (org-ellipsis " ▼")
    (org-enforce-todo-dependencies t)
    (org-enforce-todo-checkbox-dependencies t)
    (org-hide-emphasis-markers t)
    (org-hide-leading-stars t)
    (org-special-ctrl-a/e t)
    (org-use-fast-todo-selection t)
    (org-log-done 'time)
    (org-startup-folded 'showeverything)
    (org-todo-keywords
      '((sequence "TODO(t)" "ACTIVE(a)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))
    (org-tag-alist
      '((:startgroup)
        ("@home"     . ?h)
        ("@work"     . ?w)
        ("@errand"   . ?e)
        ("@computer" . ?c)
        ("@phone"    . ?p)
        ("@online"   . ?o)
      (:endgroup)))
  :config
    (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-todo-faces
   '(("WAIT" . (:inherit warning :weight bold)))))

(use-package org-roam
  :custom (org-roam-directory "~/Org/roam")
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert))
  :config (org-roam-db-autosync-mode))

;; R-Markdown support
(use-package polymode)
(use-package poly-R)
(use-package poly-markdown
  :mode (("\\.md\\'"  . poly-markdown-mode)
         ("\\.Rmd\\'" . poly-markdown+r-mode)))

;; Project management
(use-package project
  :ensure nil
  :config (project-remember-projects-under "~/GitHub"))

;; Quarto support
(use-package quarto-mode
  :mode (("\\.qmd\\'" . poly-markdown+r-mode)))

;; Rainbow delimiters
(use-package rainbow-delimiters
  :hook ((prog-mode conf-mode) . rainbow-delimiters-mode))

;; Rainbow mode
(use-package rainbow-mode
  :hook ((css-mode html-mode conf-mode prog-mode) . rainbow-mode)
  :custom (rainbow-x-colors nil)) ; avoid huge X11 name list in completions

;; Auto-save files when idle
(use-package super-save
  :init (super-save-mode 1)
  :custom (super-save-auto-save-when-idle t))

;; Treemacs
(use-package treemacs
  :defer t
  :bind
  (:map global-map
        ("C-x t t"   . treemacs)
        ("C-x t d"   . treemacs-select-directory)
        ("C-x t B"   . treemacs-bookmark)
        ("C-x t C-t" . treemacs-find-file)
        ("M-0"       . treemacs-select-window))
  :custom
  (treemacs-width 30)
  (treemacs-position 'left)
  (treemacs-is-never-other-window t)
  (treemacs-collapse-dirs 3)
  (treemacs-show-hidden-files nil)
  (treemacs-sorting 'alphabetic-asc)
  (treemacs-indentation 2)
  (treemacs-git-mode 'deferred)
  (treemacs-find-workspace-method 'find-for-file-or-pick-first)
  :config
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1)
  (treemacs-project-follow-mode 1))

(use-package treemacs-magit
  :after (treemacs magit))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config
  (treemacs-load-theme "nerd-icons"))

;; Tree-sitter auto mode installation
(use-package treesit-auto
  :custom
    (treesit-font-lock-level 3)
    (treesit-auto-install  nil)
  :config
    (treesit-auto-add-to-auto-mode-alist 'all)
    (global-treesit-auto-mode))

;; Minibuffer completion
(use-package vertico
  :init (vertico-mode))

;; Terminal emulator
(use-package vterm
  :commands vterm
  :custom
  (vterm-timer-delay 0.01))

(use-package vterm-toggle
  :bind (("C-c v" . vterm-toggle))
  :preface
  (defun my/is-vterm-display-buffer-p (buffer-or-name _)
    (let ((buffer (get-buffer buffer-or-name)))
      (with-current-buffer buffer
        (or (equal major-mode 'vterm-mode)
            (string-prefix-p vterm-buffer-name (buffer-name buffer))))))
  :custom
  (vterm-toggle-scope 'project)
  (vterm-toggle-fullscreen-p nil)
  :config
  (add-to-list 'display-buffer-alist '(my/is-vterm-display-buffer-p
                                       (display-buffer-at-bottom)
                                       (dedicated       .      t)
                                       (reusable-frames .    nil)
                                       (window-height   .    0.4))))

;; Which-key help
(use-package which-key
  :init (which-key-mode))

;; Indentation & whitespace
(use-package whitespace
  :ensure nil
  :hook
    (prog-mode . (lambda ()
      (whitespace-mode 1)
      (add-hook 'before-save-hook 'whitespace-cleanup nil t)))
  :custom
    (require-final-newline t)
    (whitespace-style '(
      empty
      face
      spaces
      space-before-tab
      space-after-tab
      tabs
      tab-mark
      trailing
      )))

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
  (prog-mode      . yas-minor-mode)
  (yas-minor-mode . my/yas-alias-tree-sitter-modes)
  :config
  (yas-reload-all))

(use-package yasnippet-snippets
  :after yasnippet)

;; USER SETTINGS

;; Start emacs server
(require 'server)
(unless (server-running-p)
  (server-start))

;; Disable bell sounds
(setq ring-bell-function 'ignore)

;; Adjust font size scaling step
(setq text-scale-mode-step 1.05)

;; Modifier keys mapping (macOS)
(setq ns-alternate-modifier     'meta
    ns-right-alternate-modifier 'none)

(set-language-environment  "Spanish")

(set-charset-priority     'unicode)
(setq locale-coding-system  'utf-8
    coding-system-for-read  'utf-8
    coding-system-for-write 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(prefer-coding-system       'utf-8)
(setq default-process-coding-system '(utf-8-unix . utf-8-unix))

(setq-default cursor-type 'bar)
(add-hook 'overwrite-mode-hook #'my/set-cursor-type)

;; Always enable syntax highlighting
(setq font-lock-maximum-decoration t)
(global-font-lock-mode 1)

;; Save recent files, history & places
(recentf-mode    1)
(savehist-mode   1)
(save-place-mode 1)

;; Avoid tabs for indentation
(setq-default indent-tabs-mode nil
              tab-width          4)

;; Make backspace unindent
(setq backward-delete-char-untabify-method 'hungry)
(global-set-key (kbd "DEL") #'backward-delete-char-untabify)

;; Enable delete selection mode
(delete-selection-mode 1)

;; GUI tweaks
(setq use-short-answers t)
(setq confirm-kill-emacs 'y-or-n-p)
(setq delete-by-moving-to-trash t)

;; Programming tweaks
(add-hook 'prog-mode-hook #'hl-line-mode)  ;; highlight line
(add-hook 'prog-mode-hook #'column-number-mode)  ;; column numbers
(add-hook 'prog-mode-hook #'display-line-numbers-mode)  ;; line numbers

(setq display-fill-column-indicator-column 100)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)  ;; fill column

;; Set fira code mono as default
(set-face-attribute 'default nil
                    :family "FiraCode Nerd Font Mono"
                    :height 130)

;; Prefer Symbols NF for private-use glyphs (NF v3)
(when (find-font (font-spec :family "Symbols Nerd Font Mono"))
  (set-fontset-font t 'symbol  (font-spec :family "Symbols Nerd Font Mono") nil 'prepend)
  (set-fontset-font t 'unicode (font-spec :family "Symbols Nerd Font Mono") nil 'prepend))

;; Good idea on macOS: ensure emoji fallback too
(when (find-font (font-spec :family "Apple Color Emoji"))
  (set-fontset-font t 'emoji (font-spec :family "Apple Color Emoji") nil 'prepend))
