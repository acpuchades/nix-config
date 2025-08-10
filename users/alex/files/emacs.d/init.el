;; PACKAGE CONFIG

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(add-to-list 'package-archives '("elpa"  . "https://elpa.gnu.org/packages/"))
(package-initialize)

(unless (package-installed-p 'use-package)
	(package-refresh-contents)
	(package-install 'use-package))
(eval-and-compile
	(setq use-package-always-ensure t
	      use-package-expand-minimally t))

(use-package blacken
  :hook (python-ts-mode . blacken-mode)
  :custom
  	(blacken-line-length 100))

(use-package eglot
	:ensure nil
	:hook (python-ts-mode . eglot-ensure)
	:config
	(add-to-list 'eglot-server-programs
		'(python-ts-mode . ("pyright-langserver" "--stdio"))))

(use-package exec-path-from-shell
  :if (memq window-system '(mac ns x))  ;; GUI Emacs
  :init (setq exec-path-from-shell-variables '("PATH" "MANPATH"))
  :config (exec-path-from-shell-initialize))

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
	:commands (magit-status magit-blame)
	:bind (("C-x g" . magit-status)))

(use-package project
	:ensure nil
	:config (project-remember-projects-under "~/GitHub"))

(use-package org
	:mode ("\\.org\\'" . org-mode)
	:hook
		((org-mode . org-indent-mode)
		 (org-mode . org-bullets-mode))
	:config
		(setq org-ellipsis                           " ▼"
		      org-enforce-todo-dependencies          t
		      org-enforce-todo-checkbox-dependencies t
		      org-hide-emphasis-markers              t
		      org-hide-leading-stars                 t
		      org-special-ctrl-a/e                   t
		      org-use-fast-todo-selection            t
		      org-log-done                           'time
		      org-startup-folded                     'showeverything)

		;; Hide underline in ellipsis
		(set-face-attribute 'org-ellipsis nil :underline nil)

		;; Configure task states
		(setq org-todo-keywords
			'((sequence "TODO(t)" "ACTIVE(a)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))

		;; Configure tags
		(setq org-tag-alist
			'((:startgroup)
				("@home"     . ?h)
				("@work"     . ?w)
				("@errand"   . ?e)
				("@computer" . ?c)
				("@phone"    . ?p)
				("@online"   . ?o)
			(:endgroup))))

(use-package treesit-auto
	:custom
		(treesit-auto-install 'prompt)
	:config
		(treesit-auto-add-to-auto-mode-alist 'all)
		(global-treesit-auto-mode))

;; USER SETTINGS

(setq ns-alternate-modifier       'meta  ;; Left Option = Meta
      ns-right-alternate-modifier 'none) ;; Right Option = None (normal typing)

(set-language-environment "Spanish")

(global-display-line-numbers-mode 1)
(column-number-mode 1)

(setq ring-bell-function 'ignore)

(set-face-attribute 'default nil
	:family "FiraCode Nerd Font Mono"
	:height 130)

(setq-default indent-tabs-mode t
              tab-width        4)

(setq python-indent-offset          4
      python-shell-interpreter      "ipython"
      python-shell-interpreter-args "-i --simple-prompt")
