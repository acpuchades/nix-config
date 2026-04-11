;; Load all configuration files from config directory in order
(let ((config-dir (expand-file-name "~/.emacs.d/config/")))
  (when (file-directory-p config-dir)
    (dolist (config-file (sort (directory-files config-dir t "\\.el$") #'string<))
      (load-file config-file))))


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
