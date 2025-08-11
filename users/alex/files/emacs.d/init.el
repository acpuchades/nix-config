;; FUNCTION DEFINITIONS

(defun my/enable-light-mode ()
	"Enable light mode with catppuccin latte flavour."
	(catppuccin-load-flavor 'latte))

(defun my/enable-dark-mode ()
	"Enable dark mode with catppuccin mocha flavour."
	(catppuccin-load-flavor 'mocha))

(defun my/set-cursor-type ()
	"Change cursor shape depending on overwrite-mode."
	(setq cursor-type (if overwrite-mode 'box 'bar)))

;; PACKAGE CONFIG

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(add-to-list 'package-archives '("elpa"  . "https://elpa.gnu.org/packages/"))
(package-initialize)

(unless (package-installed-p 'use-package)
	(package-refresh-contents)
	(package-install 'use-package))
(eval-and-compile
	(setq use-package-always-ensure    t
	      use-package-expand-minimally t))

(use-package no-littering
	:ensure t
	:init

	;; Custom file
	(setq custom-file
		(no-littering-expand-etc-file-name "custom.el"))

	(when (file-exists-p custom-file) (load custom-file :noerror))

	;; Backups & autosaves
	(setq backup-directory-alist
		`(("."  . ,(no-littering-expand-var-file-name "backup/"))))
	(setq auto-save-file-name-transforms
		`((".*"   ,(no-littering-expand-var-file-name "auto-save/") t)))
	(setq auto-save-list-file-prefix
		(no-littering-expand-var-file-name "auto-save/sessions/"))

	;; Histories & caches
	(setq recentf-save-file           (no-littering-expand-var-file-name "recentf.el")
	      savehist-file               (no-littering-expand-var-file-name "savehist.el")
	      save-place-file             (no-littering-expand-var-file-name "saveplace.el")
	      bookmark-default-file       (no-littering-expand-var-file-name "bookmarks")
	      tramp-persistency-file-name (no-littering-expand-var-file-name "tramp")
	      url-history-file            (no-littering-expand-var-file-name "url/history"))

	;; Eshell
	(setq eshell-history-file-name (no-littering-expand-var-file-name "eshell/history")))

(use-package all-the-icons
  :if (display-graphic-p)) ;; Only load if in GUI mode

(use-package all-the-icons-dired
  :hook (dired-mode . all-the-icons-dired-mode))

(use-package auto-dark
	:ensure t
	:custom
		(auto-dark-allow-osascript          t)
		(auto-dark-polling-interval-seconds 2)
	:init
		(auto-dark-mode)
	:hook
		(auto-dark-dark-mode  . my/enable-dark-mode)
		(auto-dark-light-mode . my/enable-light-mode))

(use-package blacken
	:hook (python-ts-mode . blacken-mode)
	:custom (blacken-line-length 100))

(use-package catppuccin-theme
	:ensure t
	:custom (catppuccin-flavor 'latte)
	:config (load-theme 'catppuccin t))

(use-package corfu
	:ensure t
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
		(:map corfu-map
			("M-SPC" . corfu-insert-separator)))

(use-package eglot
	:ensure nil
	:hook (python-ts-mode . eglot-ensure)
	:config
	(add-to-list 'eglot-server-programs
		'(python-ts-mode . ("pyright-langserver" "--stdio"))))

(use-package envrc
	:ensure t
	:hook (after-init . envrc-global-mode))

(use-package exec-path-from-shell
	:if (memq window-system '(mac ns x))  ;; GUI Emacs
	:ensure t
	:init (setq exec-path-from-shell-variables '("PATH" "MANPATH"))
	:config (exec-path-from-shell-initialize))

(use-package kind-icon
	:after corfu
	:custom
		(kind-icon-use-icons t)
		(kind-icon-default-face 'corfu-default)
	:config
		(add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

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

(use-package magit
	:ensure t
	:commands (magit-status magit-blame)
	:bind (("C-x g" . magit-status)))

(use-package marginalia
	:ensure t
	:init (marginalia-mode))

(use-package orderless
	:ensure t
	:init (setq completion-styles '(orderless basic)))

(use-package org
	:ensure t
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
	:ensure t
	:after org
	:hook (org-mode . org-bullets-mode))

(use-package project
	:ensure nil
	:config (project-remember-projects-under "~/GitHub"))

(use-package treesit-auto
	:ensure t
	:custom
		(treesit-auto-install    'prompt)
		(treesit-font-lock-level 4)
	:config
		(treesit-auto-add-to-auto-mode-alist 'all)
		(global-treesit-auto-mode))

(use-package vertico
	:ensure t
	:init (vertico-mode))

(use-package vterm
	:ensure t
	:commands vterm)

(use-package vterm-toggle
	:ensure t
	:bind (("C-c t" . vterm-toggle))
	:custom (vterm-toggle-scope 'project))

(use-package which-key
	:ensure t
	:init (which-key-mode))

;; USER SETTINGS

(setq ring-bell-function 'ignore)

(setq ns-alternate-modifier       'meta  ;; Left Option = Meta
      ns-right-alternate-modifier 'none) ;; Right Option = None (normal typing)

(setq-default cursor-type 'bar)
(add-hook 'overwrite-mode-hook #'my/set-cursor-type)

;; Enable syntax highlighting
(setq font-lock-maximum-decoration t)
(global-font-lock-mode 1)

(save-place-mode 1)
(savehist-mode 1)
(setq confirm-kill-emacs 'y-or-n-p)
(setq delete-by-moving-to-trash t)

(set-language-environment "Spanish")

(set-face-attribute 'default nil
	:family "FiraCode Nerd Font Mono"
	:height 130)

(add-hook 'prog-mode-hook #'column-number-mode)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; Smoother scrolling (Emacs 29+)
(when (fboundp 'pixel-scroll-precision-mode)
	(pixel-scroll-precision-mode 1))

(setq-default indent-tabs-mode       t
              tab-width              4
              require-final-newline  t
              whitespace-line-column 100
              whitespace-style       '(face empty trailing lines-char tab-mark))

(add-hook 'prog-mode-hook   #'whitespace-mode)
(add-hook 'before-save-hook #'whitespace-cleanup)

(setq python-indent-offset          4
      python-shell-interpreter      "ipython"
      python-shell-interpreter-args "-i --simple-prompt")
