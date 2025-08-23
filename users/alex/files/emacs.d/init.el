;; FUNCTION DEFINITIONS

(defun my/enable-dark-mode ()
	"Enable dark mode by activating dark theme"
	(mapc #'disable-theme custom-enabled-themes)
	(catppuccin-load-flavor 'mocha))

(defun my/enable-light-mode ()
	"Enable light mode by activating light theme"
	(mapc #'disable-theme custom-enabled-themes)
	(catppuccin-load-flavor 'latte))

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
		(load-theme 'catppuccin t))

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
	:hook
	(ess-r-mode     . eglot-ensure)
	(python-ts-mode . eglot-ensure)
	:custom
		(eglot-sync-connect nil)
		(flymake-no-changes-timeout 0.8)
		(flymake-start-on-save-buffer t)
		(flymake-start-on-newline nil)
	:config
	(add-to-list 'eglot-server-programs
		'(ess-r-mode     . ("R" "--slave" "-e" "languageserver::run()"))
		'(python-ts-mode . ("pyright-langserver" "--stdio"))))

;; Embark
(use-package embark
	:bind
	(("C-."   . embark-act)         ;; pick some comfortable binding
	 ("C-;"   . embark-dwim)        ;; good alternative: do-what-I-mean
	 ("C-h B" . embark-bindings)) ;; show all availEmbark integration
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
	(("\\.[Rr]\\'"     . ess-r-mode)
	 ("\\.Rprofile\\'" . ess-r-mode))
	:custom
		(ess-ask-for-ess-directory nil)
		(ess-indent-offset         2)
		(ess-use-flymake           nil))

(use-package ess-r-mode
	:after ess
	:ensure nil
	:no-require t
	:bind (:map ess-r-mode-map
				("C-c C-r"    . ess-eval-region)
				("C-c C-b"    . ess-eval-buffer)
				("C-c C-n"    . ess-eval-line)
				("C-<return>" . ess-eval-region-or-function-or-paragraph-and-step)))

(use-package ess-smart-equals
	:after ess
	:config (ess-smart-equals-activate))

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
		(minibuffer-exit  . my/gc-minibuffer-exit))

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
	(("C-S-c C-S-c" . mc/edit-lines)
	 ("C-S-<down>"  . mc/mark-next-like-this)
	 ("C-S-<up>"    . mc/mark-previous-like-this)
	 ("C-c C-<"     . mc/mark-all-like-this)))

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

; Set emacs as editor from within
(setenv "EDITOR" "emacs")
(setenv "VISUAL" "emacs")

(setq ring-bell-function 'ignore) ;; No bell

;; Modifier keys mapping (macOS)
(setq ns-alternate-modifier       'meta
      ns-right-alternate-modifier 'none)

(set-language-environment  "Spanish")

(set-charset-priority       'unicode)
(setq locale-coding-system    'utf-8
      coding-system-for-read  'utf-8
      coding-system-for-write 'utf-8)
(set-terminal-coding-system   'utf-8)
(set-keyboard-coding-system   'utf-8)
(prefer-coding-system         'utf-8)
(setq default-process-coding-system '(utf-8-unix . utf-8-unix))


(setq-default cursor-type 'bar)
(add-hook 'overwrite-mode-hook #'my/set-cursor-type)

;; Always enable syntax highlighting
(setq font-lock-maximum-decoration t)
(global-font-lock-mode 1)

;; Save places & history
(save-place-mode 1)
(savehist-mode   1)

;; Use tabs for indentation
(setq-default indent-tabs-mode  t
              tab-width         4)

;; Make backspace unindent
(setq backward-delete-char-untabify-method 'hungry)
(global-set-key (kbd "DEL") #'backward-delete-char-untabify)

(setq use-short-answers t)
(setq confirm-kill-emacs 'y-or-n-p)
(setq delete-by-moving-to-trash t)

;; Font
(set-face-attribute 'default nil
	:family "FiraCode Nerd Font Mono"
	:height 130)

;; Line numbers in prog-mode
(add-hook 'prog-mode-hook #'column-number-mode)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
