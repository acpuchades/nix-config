;; Alex's personal Emacs configuration
;; This file contains user-specific settings that override or extend the core configuration

;; Configuración personal de mu4e
(with-eval-after-load 'mu4e
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

;; Personal language and locale settings
(set-language-environment "Spanish")

;; Personal calendar settings (Spanish)
(with-eval-after-load 'calendar
  (setq calendar-day-header-array   ["Do" "Lu" "Ma" "Mi" "Ju" "Vi" "Sa"]
        calendar-day-name-array     ["domingo" "lunes" "martes" "miércoles"
                                     "jueves" "viernes" "sábado"]
        calendar-month-abbrev-array ["Ene" "Feb" "Mar" "Abr" "May" "Jun"
                                     "Jul" "Ago" "Sep" "Oct" "Nov" "Dic"]
        calendar-month-name-array   ["enero" "febrero" "marzo" "abril" "mayo"
                                     "junio" "julio" "agosto" "septiembre"
                                     "octubre" "noviembre" "diciembre"]))

;; Personal org-mode settings (Spanish GTD)
(with-eval-after-load 'org
  (setq org-todo-keywords
        '((sequence "TAREA(p)" "SIGUIENTE(n)" "|" "COMPLETADO(d!)")
          (sequence "ESPERANDO(w@/!)" "|" "CANCELADO(k!)")))
  
  (setq org-tag-alist
        '((:startgroup)
          ("@casa"     . ?c)
          ("@hospital" . ?h)
          ("@portatil" . ?p)
          ("@tableta"  . ?t)
          ("@movil"    . ?m)
          ("@email"    . ?e)
          ("@recados"  . ?r)
          (:endgroup)))
  
  (setq org-agenda-custom-commands
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
          ("r" "Recados"         tags-todo "@recados"))))

