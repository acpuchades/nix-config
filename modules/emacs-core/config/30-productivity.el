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

;; Mu4e
(use-package mu4e
  :commands (mu4e)
  :bind (("C-c m" . mu4e))
  :custom
  (mu4e-maildir "~/Mail")
  (mu4e-update-interval 300)
  (mu4e-get-mail-command nil)
  (mu4e-index-update-error-warning nil)
  (mu4e-index-update-in-background nil)
  (mu4e-change-filenames-when-moving t)
  (mu4e-context-policy 'pick-first)
  (mu4e-compose-context-policy 'ask-if-none)
  :config
  (setq mu4e-contexts
        (list
         (make-mu4e-context
          :name "icloud"
          :match-func (lambda (msg)
                        (when msg (string-prefix-p "/iCloud"
                                                   (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address  . "acaravacapuchades@icloud.com")
                  (user-full-name     . "Alejandro Caravaca Puchades")
                  (mu4e-drafts-folder . "/iCloud/Drafts")
                  (mu4e-sent-folder   . "/iCloud/Sent Messages")
                  (mu4e-trash-folder  . "/iCloud/Deleted Messages")
                  (mu4e-refile-folder . "/iCloud/Archive"))))))

(use-package message
  :ensure nil
  :after mu4e
  :custom
  (sendmail-program "msmtp")
  (message-send-mail-function 'message-send-mail-with-sendmail)
  (message-sendmail-envelope-from 'header))

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
