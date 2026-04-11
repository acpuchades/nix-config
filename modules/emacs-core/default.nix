{ config, lib, pkgs, ... }:

{
  options.my.emacs-core = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for core functionality.";
    };
  };

  config = {
    # Configure Emacs with core packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # Package management
        use-package

        # File organization
        no-littering

        # Performance
        gcmh

        # Completion framework
        vertico
        consult
        corfu
        cape
        marginalia
        embark
        embark-consult
        orderless

        # Snippets
        yasnippet
        yasnippet-snippets

        # Development tools
        which-key
        super-save
        multiple-cursors
        rainbow-delimiters
        rainbow-mode
        editorconfig

        # Shell integration
        eshell-toggle
        exec-path-from-shell

        # Environment
        direnv
        envrc

        # Project management
        project

        # Additional packages for init.el
        auto-dark
        catppuccin-theme
        dashboard
        doom-modeline
        ligature
        mu4e
        nerd-icons
        nerd-icons-corfu
        nerd-icons-dired
        nerd-icons-ibuffer
        org-modern
        org-roam
        treemacs
        treemacs-magit
        treemacs-nerd-icons
      ] ++ config.my.emacs-core.extraPackages;
    };

    # Core emacs configuration
    home.file.".emacs.d/early-init.el".source = ./early-init.el;
    home.file.".emacs.d/init.el".source = ./init.el;
    home.file.".emacs.d/share/logo.svg".source = ./share/logo.svg;
    
    # Deploy config files
    home.file.".emacs.d/config/00-core.el".text = ''
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

      ;; Consult
      (use-package consult
        :bind
        (
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

      ;; Direnv
      (use-package direnv
        :config
        (direnv-mode 1)
        (setq direnv-always-show-summary t))

      ;; EditorConfig support
      (use-package editorconfig
        :config (editorconfig-mode 1))

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

      ;; Rich minibuffer annotations
      (use-package marginalia
        :init (marginalia-mode))

      ;; Multiple cursors
      (use-package multiple-cursors
        :bind
        (("C->"     . mc/mark-next-like-this)
         ("C-<"     . mc/mark-previous-like-this)
         ("C-c C-<" . mc/mark-all-like-this)))

      ;; Fuzzy matching
      (use-package orderless
        :init (setq completion-styles '(orderless basic)))

      ;; Project management
      (use-package project
        :ensure nil
        :config (project-remember-projects-under "~/GitHub"))

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

      ;; TRAMP
      (use-package tramp
        :defer t
        :config
        ;; Make TRAMP also use the remote user's own PATH
        (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

      ;; Minibuffer completion
      (use-package vertico
        :init (vertico-mode))

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
    '';
    
    home.file.".emacs.d/config/10-ui.el".source = ./config/10-ui.el;
    home.file.".emacs.d/config/20-dev.el".source = ./config/20-dev.el;
    home.file.".emacs.d/config/30-productivity.el".source = ./config/30-productivity.el;
  };
}
