;; PACKAGE CONFIG

(require 'package)
(add-to-list 'package-archives '("gnu"   . "https://elpa.gnu.org/packages/"))
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(eval-and-compile
  (setq use-package-always-ensure t
        use-package-expand-minimally t))

(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))

(use-package treesit-auto
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;; USER SETTINGS

(setq inhibit-startup-message t)

(global-display-line-numbers-mode 1)
(column-number-mode 1)

(setq-default indent-tabs-mode t)
(setq-default tab-width 4)
