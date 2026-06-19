;; GitHub Copilot inline completion
;;
;; The Copilot language server is provided by Nix: the emacs-overlay copilot
;; package pre-points `copilot-server-executable' at the nix-store
;; `copilot-language-server' binary, so there is no `M-x copilot-install-server'
;; step and no Node.js dependency.
;;
;; Division of labour with the corfu/cape stack (05-completion.el):
;;   - corfu   -> popup list of LSP/symbol candidates for the current token
;;   - copilot -> greyed-out inline suggestion for the rest of the line/block
;; They are kept from fighting: Copilot's overlay is hidden while the corfu
;; popup is on screen, and TAB accepts a Copilot suggestion only when one is
;; actually showing (`copilot-completion-map' is live only then, so otherwise
;; TAB indents as usual).
(use-package copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("<tab>"     . copilot-accept-completion)
              ("TAB"       . copilot-accept-completion)
              ("C-<tab>"   . copilot-accept-completion)
              ("M-<tab>"   . copilot-accept-completion-by-word)
              ("C-M-<tab>" . copilot-accept-completion-by-line)
              ("M-]"       . copilot-next-completion)
              ("M-["       . copilot-previous-completion)
              ("C-g"       . copilot-clear-overlay))
  :custom
  ;; Show a suggestion shortly after typing stops.
  (copilot-idle-delay 0.2)
  ;; Don't warn about major modes with no registered indentation width.
  (copilot-indent-offset-warning-disable t)
  :config
  ;; Suppress the Copilot ghost text while the corfu popup is active, so only
  ;; one completion UI is visible at a time; it returns once corfu closes.
  (add-to-list 'copilot-disable-display-predicates
               (lambda () (bound-and-true-p completion-in-region-mode))))
