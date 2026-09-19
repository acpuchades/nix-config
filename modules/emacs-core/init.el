;; A bare loader, on purpose: user settings belong in config/ files (this
;; module's 02-defaults.el and onward), where filename order is the ONLY load
;; order. Anything added below this loader would run after — and override —
;; even 99-personal.el.
(let ((config-dir (expand-file-name "~/.emacs.d/config/")))
  (when (file-directory-p config-dir)
    (dolist (config-file (sort (directory-files config-dir t "\\.el$") #'string<))
      (load-file config-file))))
