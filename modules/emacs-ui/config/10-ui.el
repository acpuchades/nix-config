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

;; Nerd icons everywhere
(use-package nerd-icons)

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

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
