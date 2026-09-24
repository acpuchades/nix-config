;; Org mode tweaks. Mechanism only: where the files live, the capture
;; templates and the TODO keywords they use are personal (99-personal.el).
(use-package org
  :mode ("\\.org\\'" . org-mode)
  :bind
  (("C-c a" . org-agenda)
   ("C-c c" . org-capture))
  :hook
  (org-mode . org-indent-mode)
  (org-mode . variable-pitch-mode)
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
  :config
  (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package org-modern
  :after org
  :hook
  (org-mode . org-modern-mode)
  :custom
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-pretty-entities t))

(use-package org-roam
  :bind
  (("C-c n l" . org-roam-buffer-toggle)
   ("C-c n f" . org-roam-node-find)
   ("C-c n i" . org-roam-node-insert))
  :config (org-roam-db-autosync-mode))
