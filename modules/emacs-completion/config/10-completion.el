;; Completion at point extensions
(use-package cape
  :bind ("C-c p" . cape-prefix-map) ;; Alternative key: M-<tab>, M-p, M-+
  :init
  ;; Only the buffer-agnostic capfs go on the GLOBAL
  ;; completion-at-point-functions (corfu-auto runs every one of these on each
  ;; keystroke); mode-specific ones attach per mode below. Note add-hook
  ;; PREPENDS, so the last one added here is tried first.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  ;; Mode-scoped capfs: elisp symbols/blocks only where they mean something,
  ;; keywords in code, emoji in prose, history in shells.
  (defun my/cape-elisp-capfs ()
    (add-hook 'completion-at-point-functions #'cape-elisp-symbol nil t)
    (add-hook 'completion-at-point-functions #'cape-elisp-block nil t))
  (add-hook 'emacs-lisp-mode-hook #'my/cape-elisp-capfs)
  (defun my/cape-prog-capfs ()
    (add-hook 'completion-at-point-functions #'cape-keyword nil t))
  (add-hook 'prog-mode-hook #'my/cape-prog-capfs)
  (defun my/cape-text-capfs ()
    (add-hook 'completion-at-point-functions #'cape-emoji nil t))
  (add-hook 'text-mode-hook #'my/cape-text-capfs)
  (defun my/cape-comint-capfs ()
    (add-hook 'completion-at-point-functions #'cape-history nil t))
  (add-hook 'comint-mode-hook #'my/cape-comint-capfs)
  (add-hook 'eshell-mode-hook #'my/cape-comint-capfs))

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
   ("M-s m"   . consult-line-multi) ;; consult-multi-occur was removed upstream
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

;; Rich minibuffer annotations
(use-package marginalia
  :init (marginalia-mode))

;; Nerd icons for corfu. The formatter is autoloaded, so registering it
;; doesn't load nerd-icons (every icon set) at startup — that waits for the
;; first popup.
(use-package nerd-icons-corfu
  :defer t
  :init
  (with-eval-after-load 'corfu
    (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)))

;; Fuzzy matching
(use-package orderless
  :init (setq completion-styles '(orderless basic)))

;; Minibuffer completion
(use-package vertico
  :init (vertico-mode))
