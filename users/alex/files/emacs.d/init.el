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
	  bidi-inhibit-bpa         t)

;; Line numbers: reserve width once to avoid reflow flicker
(setq display-line-numbers-width-start t)

;; Smoother scrolling (Emacs 29+)
(when (fboundp 'pixel-scroll-precision-mode)
	(pixel-scroll-precision-mode 1))

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
	(setq recentf-save-file           (no-littering-expand-var-file-name "recentf.el")
		  savehist-file               (no-littering-expand-var-file-name "savehist.el")
		  save-place-file             (no-littering-expand-var-file-name "saveplace.el")
		  bookmark-default-file       (no-littering-expand-var-file-name "bookmarks")
		  tramp-persistency-file-name (no-littering-expand-var-file-name "tramp")
		  url-history-file            (no-littering-expand-var-file-name "url/history"))

	;; Redirect Eshell history
	(setq eshell-history-file-name (no-littering-expand-var-file-name "eshell/history")))

(use-package all-the-icons
	:if (display-graphic-p)) ;; Icons only in GUI mode

(use-package all-the-icons-dired
	:hook (dired-mode . all-the-icons-dired-mode))

;; Auto switch theme based on system appearance
(use-package auto-dark
  :if (display-graphic-p)
  :after catppuccin-theme
	:custom
		(auto-dark-allow-osascript          t) ;; macOS detection
		(auto-dark-polling-interval-seconds 2) ;; Check every 2s
	:init
		(auto-dark-mode 1)
	:hook
		(auto-dark-dark-mode  . (lambda	()
			(mapc #'disable-theme custom-enabled-themes)
			(catppuccin-load-flavor 'mocha)))
		(auto-dark-light-mode . (lambda ()
			(mapc #'disable-theme custom-enabled-themes)
			(catppuccin-load-flavor 'latte))))

;; Python auto-formatter
(use-package blacken
	:hook (python-base-mode . blacken-mode)
	:custom (blacken-line-length 100))

;; Catppuccin theme setup
(use-package catppuccin-theme
	:custom (catppuccin-flavor 'latte)
	:config
		(mapc #'disable-theme custom-enabled-themes)
		(load-theme 'catppuccin t))

;; Completion UI
(use-package corfu
	:init
		(global-corfu-mode) ;; Enable globally
	:custom
		(corfu-auto t)             ;; Enable auto completion
		(corfu-auto-delay 0.5)     ;; No delay for completion popup
		(corfu-auto-prefix 1)      ;; Show popup after 1 char
		(corfu-quit-no-match 'separator) ;; Don't quit on no match, allow separator
		(corfu-scroll-margin 2)    ;; Keep popup from touching edges
		(corfu-cycle t)            ;; Cycle through candidates
		(corfu-preselect 'prompt)  ;; Don't auto select first
		(corfu-quit-at-boundary t) ;; Quit when no further completion is possible
	:bind
		(:map corfu-map ("M-SPC" . corfu-insert-separator)))

;; EditorConfig support
(use-package editorconfig
	:config (editorconfig-mode 1))

;; LSP client (built-in)
(use-package eglot
	:ensure nil
	:hook (python-ts-mode . eglot-ensure)
	:custom
		(eglot-sync-connect nil)
		(flymake-no-changes-timeout 0.8)
		(flymake-start-on-save-buffer t)
		(flymake-start-on-newline nil)
	:config
		(add-to-list 'eglot-server-programs
			'(python-ts-mode . ("pyright-langserver" "--stdio"))))

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

;; Envrc support
(use-package envrc
	:hook (after-init . envrc-global-mode))

;; Fix PATH in GUI Emacs (macOS)
(use-package exec-path-from-shell
	:if (memq window-system '(mac ns x))
	:init (setq exec-path-from-shell-variables '("PATH" "MANPATH"))
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
		(minibuffer-setup . my/gc-minibuffer-setup)
		(minibuffer-exit  . my/gc-minibuffer-exit)
)

;; Icons in completion popups
(use-package kind-icon
	:after corfu
	:custom
		(kind-icon-use-icons t)
		(kind-icon-default-face 'corfu-default)
	:config
		(add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; Ligatures
(use-package ligature
	:config
	;; Enable the "www" ligature in every possible major mode
	(ligature-set-ligatures 't '("www"))
	;; Enable traditional ligature support in eww-mode, if the
	;; `variable-pitch' face supports it
	(ligature-set-ligatures 'eww-mode '("ff" "fi" "ffi"))
	;; Enable all Cascadia Code ligatures in programming modes
	(ligature-set-ligatures 'prog-mode '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
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

;; Nix
(use-package nix-ts-mode
  :mode ("\\.nix\\'" . nix-ts-mode)
  :config (treesit-auto-add-to-auto-mode-alist 'nix))

;; Fuzzy matching
(use-package orderless
	:init (setq completion-styles '(orderless basic)))

;; Org mode tweaks
(use-package org
	:mode ("\\.org\\'" . org-mode)
	:hook (org-mode . org-indent-mode)
	:custom
		(org-ellipsis                           " ▼")
		(org-enforce-todo-dependencies          t)
		(org-enforce-todo-checkbox-dependencies t)
		(org-hide-emphasis-markers              t)
		(org-hide-leading-stars                 t)
		(org-special-ctrl-a/e                   t)
		(org-use-fast-todo-selection            t)
		(org-log-done                           'time)
		(org-startup-folded                     'showeverything)
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

(use-package org-bullets
	:after org
	:hook (org-mode . org-bullets-mode))

;; Project management
(use-package project
	:ensure nil
	:config (project-remember-projects-under "~/GitHub"))

;; Tree-sitter auto mode installation
(use-package treesit-auto
	:custom
		(treesit-font-lock-level 3)
		(treesit-auto-install    nil)
	:config
		(treesit-auto-add-to-auto-mode-alist 'all)
		(global-treesit-auto-mode))

;; Minibuffer completion
(use-package vertico
	:init (vertico-mode))

;; Indentation & whitespace
(use-package whitespace
	:ensure nil
	:hook
		(prog-mode . (lambda ()
			(whitespace-mode 1)
			(add-hook 'before-save-hook 'whitespace-cleanup nil t)))
	:custom
		(require-final-newline  t)
		(whitespace-style '(
			face
			empty
			tabs
			tab-mark
			space-before-tab
			space-after-tab
			indentation
			trailing
		))
	:config
		(set-face-attribute 'whitespace-space
			nil :foreground "gray70" :background 'unspecified :underline nil)
		(set-face-attribute 'whitespace-tab
			nil :foreground "gray70" :background 'unspecified :underline nil))

;; Terminal emulator
(use-package vterm
	:commands vterm
	:custom (vterm-timer-delay 0.01))

(use-package vterm-toggle
	:bind (("C-c t" . vterm-toggle))
	:custom (vterm-toggle-scope 'project))

;; Which-key help
(use-package which-key
	:init (which-key-mode))

;; USER SETTINGS

(setq ring-bell-function 'ignore) ;; No bell

;; Modifier keys mapping (macOS)
(setq ns-alternate-modifier       'meta
	  ns-right-alternate-modifier 'none)

(set-language-environment "Spanish")

(setq-default cursor-type 'bar)
(add-hook 'overwrite-mode-hook #'my/set-cursor-type)

;; Always enable syntax highlighting
(setq font-lock-maximum-decoration t)
(global-font-lock-mode 1)

;; Save places & history
(save-place-mode 1)
(savehist-mode 1)

;; Use tabs for indentation
(setq-default indent-tabs-mode  t
			  tab-width         4)

(setq confirm-kill-emacs 'y-or-n-p)
(setq delete-by-moving-to-trash t)

;; Font
(set-face-attribute 'default nil
	:family "FiraCode Nerd Font Mono"
	:height 130)

;; Line numbers in prog-mode
(add-hook 'prog-mode-hook #'column-number-mode)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
