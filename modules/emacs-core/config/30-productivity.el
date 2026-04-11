;; Calendar settings
(use-package calendar
  :ensure nil
  :custom
  (calendar-date-style 'european)
  (calendar-week-start-day 1)
  (calendar-day-header-array   ["Do" "Lu" "Ma" "Mi" "Ju" "Vi" "Sa"])
  (calendar-day-name-array     ["domingo" "lunes" "martes" "miércoles"
                                "jueves" "viernes" "sábado"])
  (calendar-month-abbrev-array ["Ene" "Feb" "Mar" "Abr" "May" "Jun"
                                "Jul" "Ago" "Sep" "Oct" "Nov" "Dic"])
  (calendar-month-name-array   ["enero" "febrero" "marzo" "abril" "mayo"
                                "junio" "julio" "agosto" "septiembre"
                                "octubre" "noviembre" "diciembre"])
  (calendar-mark-diary-entries-flag t)
  (calendar-mark-entries-hook '(diary-mark-entries))
  (calendar-today-visible-hook '(calendar-mark-today))
  (diary-date-forms diary-european-date-forms)
  (diary-mark-entries-hook '(diary-mark-entries)))


;; Org mode tweaks
(use-package org
  :disabled t
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
  (org-todo-keywords
   '((sequence "TAREA(p)" "SIGUIENTE(n)" "|" "COMPLETADO(d!)")
     (sequence "ESPERANDO(w@/!)" "|" "CANCELADO(k!)")))
  (org-tag-alist
   '((:startgroup)
     ("@casa"     . ?c)
     ("@hospital" . ?h)
     ("@portatil" . ?p)
     ("@tableta"  . ?t)
     ("@movil"    . ?m)
     ("@email"    . ?e)
     ("@recados"  . ?r)
     (:endgroup)))
  (org-agenda-custom-commands
   `(
     ;; GTD entries
     ("i" "Revisar bandeja" tags "*"
      ((org-agenda-files '("~/Org/inbox.org"))
       (org-agenda-overriding-header "Bandeja de entrada")))
     ("n" "Siguiente"       todo      "SIGUIENTE"
      ((org-agenda-overriding-header "Siguientes tareas")))
     ("w" "Esperando"       todo      "ESPERANDO"
      ((org-agenda-overriding-header "Tareas en espera")))

     ;; Quick single-views
     ("c" "Casa"            tags-todo "@casa")
     ("h" "Hospital"        tags-todo "@hospital")
     ("p" "Portatil"        tags-todo "@portatil")
     ("t" "Tableta"         tags-todo "@tableta")
     ("e" "Correo-e"        tags-todo "@email")
     ("m" "Llamadas"        tags-todo "@movil")
     ("r" "Recados"         tags-todo "@recados")
     ))
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
  :disabled t
  :after org
  :hook
  (org-mode . org-modern-mode)
  :custom
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-pretty-entities t))

(use-package org-roam
  :disabled t
  :custom (org-roam-directory "~/Org/Roam")
  :bind
  (("C-c n l" . org-roam-buffer-toggle)
   ("C-c n f" . org-roam-node-find)
   ("C-c n i" . org-roam-node-insert))
  :config (org-roam-db-autosync-mode))
