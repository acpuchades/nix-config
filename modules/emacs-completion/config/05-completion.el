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

;; Nerd icons for corfu
(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters
               #'nerd-icons-corfu-formatter))

;; Fuzzy matching
(use-package orderless
  :init (setq completion-styles '(orderless basic)))

;; Minibuffer completion
(use-package vertico
  :init (vertico-mode))
