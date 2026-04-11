;; Org mode tweaks
(use-package org
  :mode ("\\.org\\'" . org-mode)
  :bind
  (("C-c a" . org-agenda)
   ("C-c c" . org-capture))
  :hook
  (org-mode . org-indent-mode)
  (org-mode . variable-pitch-mode)
  :init
  (setq diary-file
        (expand-file-name "~/Org/diary"))
  (setq org-agenda-files
        (directory-files-recursively
         (expand-file-name "~/Org") "\\.org\\'"))
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
  (org-refile-targets
   '(("~/Org/tasks.org" :maxlevel . 3)
     (org-agenda-files  :maxlevel . 2)))
  (org-refile-target-verify-function
   (lambda ()
     (not (and (buffer-file-name)
               (string-match-p "inbox\\.org" (buffer-file-name))))))
  (org-default-notes-file "~/Org/inbox.org")
  (org-capture-templates
   '(("i" "Entrada" entry
      (file "~/Org/inbox.org")
      "* %?\n%U\n")
     ("t" "Tarea" entry
      (file+headline "~/Org/tasks.org" "Tareas")
      "* PENDIENTE %?")
     ("e" "Evento" entry
      (file+headline "~/Org/events.org" "Eventos")
      "* %^{Título}\n%^{Fecha}T\n%?")
     ("n" "Nota" entry
      (file+headline "~/Org/notes.org" "Notas")
      "* %?\n%U\n")))
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
  :custom (org-roam-directory "~/Org/Roam")
  :bind
  (("C-c n l" . org-roam-buffer-toggle)
   ("C-c n f" . org-roam-node-find)
   ("C-c n i" . org-roam-node-insert))
  :config (org-roam-db-autosync-mode))
