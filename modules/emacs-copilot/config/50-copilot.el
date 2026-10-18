;; GitHub Copilot inline completion
;;
;; The Copilot language server is provided by Nix: the emacs-overlay copilot
;; package pre-points `copilot-server-executable' at the nix-store
;; `copilot-language-server' binary, so there is no `M-x copilot-install-server'
;; step and no Node.js dependency.
;;
;; The CREDENTIAL is the one imperative piece: a one-time `M-x copilot-login'
;; (device flow) writes ~/.config/github-copilot/apps.json, which no Nix or
;; sops config manages — redo it after a fresh provision. Until that file
;; exists the prog-mode hook below stays off, so an unauthenticated host
;; (e.g. the headless server) doesn't spawn the server and log auth failures
;; on every file open.
;;
;; Division of labour with the corfu/cape stack (10-completion.el):
;;   - corfu   -> popup list of LSP/symbol candidates for the current token
;;   - copilot -> greyed-out inline suggestion for the rest of the line/block
;; Privacy gate: Copilot uploads the buffer to GitHub as soon as the mode is
;; on, so it stays off for temp files (decrypted secrets, see 02-defaults.el),
;; inside git-crypt repos (a dominating .gitattributes with filter=git-crypt),
;; and inside any project opted out with an empty `.no-copilot' file at its
;; root. Gated at enable time, not via `copilot-disable-predicates': those only
;; suppress suggestions, after the document has already been sent.
;;
;; They are kept from fighting: Copilot's overlay is hidden while the corfu
;; popup is on screen, and TAB accepts a Copilot suggestion only when one is
;; actually showing (`copilot-completion-map' is live only then, so otherwise
;; TAB indents as usual).
(use-package copilot
  :preface
  (defun my/copilot-git-crypt-dir-p (dir)
    "Non-nil if DIR has a .gitattributes routing files through git-crypt."
    (let ((attrs (expand-file-name ".gitattributes" dir)))
      (and (file-readable-p attrs)
           (with-temp-buffer
             (insert-file-contents attrs)
             (re-search-forward "filter=git-crypt" nil t)))))
  (defun my/copilot-private-p ()
    "Non-nil if the current buffer must not be sent to Copilot."
    (let ((file (or buffer-file-name default-directory)))
      (and file
           (or (my/file-in-temp-dir-p file)
               (locate-dominating-file file ".no-copilot")
               (locate-dominating-file file #'my/copilot-git-crypt-dir-p)))))
  (defun my/copilot-maybe-enable ()
    "Enable copilot-mode when a Copilot credential exists and the buffer is
not private (see `my/copilot-private-p')."
    (when (and (file-exists-p "~/.config/github-copilot/apps.json")
               (not (my/copilot-private-p)))
      (copilot-mode 1)))
  :hook (prog-mode . my/copilot-maybe-enable)
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
