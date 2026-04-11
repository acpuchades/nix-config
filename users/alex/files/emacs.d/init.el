;; Load core configuration if available
(when (file-exists-p "~/.emacs.d/core-config.el")
  (load-file "~/.emacs.d/core-config.el"))

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

;; Calendar settings
(use-package calendar
  :ensure nil
  :custom
  (calendar-date-style 'european)
  (calendar-week-start-day 1)
  (calendar-day-header-array   ["Do" "Lu" "Ma" "Mi" "Ju" "Vi" "Sa"])
  (calendar-day-name-array     ["domingo" "lunes" "martes" "miércoles"
                                "jueves" "viernes" "sábado"])
  (calendar-month-abbrev-array ["Ene" "Feb" "Mar" "Abr" "May" "Jun"
                                "Jul" "Ago" "Sep" "Oct" "Nov" "Dic"])
  (calendar-month-name-array   ["enero" "febrero" "marzo" "abril" "mayo"
                                "junio" "julio" "agosto" "septiembre"
                                "octubre" "noviembre" "diciembre"])
  (calendar-mark-diary-entries-flag t)
  (calendar-mark-entries-hook '(diary-mark-entries))
  (calendar-today-visible-hook '(calendar-mark-today))
  (diary-date-forms diary-european-date-forms)
  (diary-mark-entries-hook '(diary-mark-entries)))


;; Catppuccin theme setup
(use-package catppuccin-theme
  :custom
  (catppuccin-flavor 'mocha)
  :config
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'catppuccin :no-confirm))


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
               '(ess-r-mode   . ("air" "language-server")))
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("pyright-langserver" "--stdio"))))


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


;; Mu4e
(use-package mu4e
  :commands (mu4e)
  :bind (("C-c m" . mu4e))
  :custom
  (mu4e-maildir "~/Mail")
  (mu4e-update-interval 300)
  (mu4e-get-mail-command nil)
  (mu4e-index-update-error-warning nil)
  (mu4e-index-update-in-background nil)
  (mu4e-change-filenames-when-moving t)
  (mu4e-context-policy 'pick-first)
  (mu4e-compose-context-policy 'ask-if-none)
  :config
  (setq mu4e-contexts
        (list
         (make-mu4e-context
          :name "icloud"
          :match-func (lambda (msg)
                        (when msg (string-prefix-p "/iCloud"
                                                   (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address  . "acaravacapuchades@icloud.com")
                  (user-full-name     . "Alejandro Caravaca Puchades")
                  (mu4e-drafts-folder . "/iCloud/Drafts")
                  (mu4e-sent-folder   . "/iCloud/Sent Messages")
                  (mu4e-trash-folder  . "/iCloud/Deleted Messages")
                  (mu4e-refile-folder . "/iCloud/Archive"))))))

(use-package message
  :ensure nil
  :after mu4e
  :custom
  (sendmail-program "msmtp")
  (message-send-mail-function 'message-send-mail-with-sendmail)
  (message-sendmail-envelope-from 'header))


;; Nerd icons everywhere
(use-package nerd-icons)

(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters
               #'nerd-icons-corfu-formatter))

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


;; Org mode tweaks
(use-package org
  :disabled t
  :mode ("\\.org\\'" . org-mode)
  :bind
  (("C-c a" . org-agenda)
   ("C-c c" . org-capture))
  :hook
  (org-mode . org-indent-mode)
  (org-mode . variable-pitch-mode)
  :init
  (setq diary-file
        (expand-file-name "~/Org/diary"))
  (setq org-agenda-files
        (directory-files-recursively
         (expand-file-name "~/Org") "\\.org\\'"))
  :custom
  (org-agenda-include-diary t)
  (org-enforce-todo-dependencies t)
  (org-enforce-todo-checkbox-dependencies t)
  (org-hide-emphasis-markers t)
  (org-hide-leading-stars t)
  (org-special-ctrl-a/e t)
  (org-use-fast-todo-selection t)
  (org-log-done 'time)
  (org-startup-folded 'showeverything)
  (org-refile-targets
   '(("~/Org/tasks.org" :maxlevel . 3)
     (org-agenda-files  :maxlevel . 2)))
  (org-refile-target-verify-function
   (lambda ()
     (not (and (buffer-file-name)
               (string-match-p "inbox\\.org" (buffer-file-name))))))
  (org-todo-keywords
   '((sequence "TAREA(p)" "SIGUIENTE(n)" "|" "COMPLETADO(d!)")
     (sequence "ESPERANDO(w@/!)" "|" "CANCELADO(k!)")))
  (org-tag-alist
   '((:startgroup)
     ("@casa"     . ?c)
     ("@hospital" . ?h)
     ("@portatil" . ?p)
     ("@tableta"  . ?t)
     ("@movil"    . ?m)
     ("@email"    . ?e)
     ("@recados"  . ?r)
     (:endgroup)))
  (org-agenda-custom-commands
   `(
     ;; GTD entries
     ("i" "Revisar bandeja" tags "*"
      ((org-agenda-files '("~/Org/inbox.org"))
       (org-agenda-overriding-header "Bandeja de entrada")))
     ("n" "Siguiente"       todo      "SIGUIENTE"
      ((org-agenda-overriding-header "Siguientes tareas")))
     ("w" "Esperando"       todo      "ESPERANDO"
      ((org-agenda-overriding-header "Tareas en espera")))

     ;; Quick single-views
     ("c" "Casa"            tags-todo "@casa")
     ("h" "Hospital"        tags-todo "@hospital")
     ("p" "Portatil"        tags-todo "@portatil")
     ("t" "Tableta"         tags-todo "@tableta")
     ("e" "Correo-e"        tags-todo "@email")
     ("m" "Llamadas"        tags-todo "@movil")
     ("r" "Recados"         tags-todo "@recados")
     ))
  (org-default-notes-file "~/Org/inbox.org")
  (org-capture-templates
   '(("i" "Entrada" entry
      (file "~/Org/inbox.org")
      "* %?\n%U\n")
     ("t" "Tarea" entry
      (file+headline "~/Org/tasks.org" "Tareas")
      "* PENDIENTE %?")
     ("e" "Evento" entry
      (file+headline "~/Org/events.org" "Eventos")
      "* %^{Título}\n%^{Fecha}T\n%?")
     ("n" "Nota" entry
      (file+headline "~/Org/notes.org" "Notas")
      "* %?\n%U\n")))
  :config
  (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package org-modern
  :disabled t
  :after org
  :hook
  (org-mode . org-modern-mode)
  :custom
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-pretty-entities t))

(use-package org-roam
  :disabled t
  :custom (org-roam-directory "~/Org/Roam")
  :bind
  (("C-c n l" . org-roam-buffer-toggle)
   ("C-c n f" . org-roam-node-find)
   ("C-c n i" . org-roam-node-insert))
  :config (org-roam-db-autosync-mode))



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


;; Load ESS configuration if available
(when (file-exists-p "~/.emacs.d/ess-config.el")
  (load-file "~/.emacs.d/ess-config.el"))

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

;; Make shift+backspace unindent
(setq backward-delete-char-untabify-method 'hungry)
(global-set-key (kbd "S-<backspace>") #'backward-delete-char-untabify)

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

;; Text editing tweaks
(add-hook 'text-mode-hook #'visual-line-mode)

;; Set fira code mono as default
(set-face-attribute 'default nil
                    :family "FiraCode Nerd Font Mono"
                    :height 130)

;; Proper Unicode symbols first
(when (find-font (font-spec :family "Noto Sans Symbols2"))
  (set-fontset-font t 'symbol "Noto Sans Symbols2" nil 'prepend))
(when (find-font (font-spec :family "Noto Sans Symbols"))
  (set-fontset-font t 'symbol "Noto Sans Symbols"  nil 'prepend))

;; Good idea on macOS: ensure emoji fallback too
(when (find-font (font-spec :family "Apple Color Emoji"))
  (set-fontset-font t 'emoji (font-spec :family "Apple Color Emoji") nil 'prepend))

;; Emoji fallback
(when (find-font (font-spec :family "Noto Color Emoji"))
  (set-fontset-font t 'emoji "Noto Color Emoji" nil 'prepend))

;; Prefer Symbols NF for private-use glyphs (NF v3)
(when (find-font (font-spec :family "Symbols Nerd Font Mono"))
  (set-fontset-font t 'symbol  (font-spec :family "Symbols Nerd Font Mono") nil 'prepend)
  (set-fontset-font t 'unicode (font-spec :family "Symbols Nerd Font Mono") nil 'prepend))

(when (find-font (font-spec :family "Unifont"))
  (set-fontset-font t 'unicode "Unifont" nil 'append))
