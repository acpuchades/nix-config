;; Alex's personal Emacs configuration
;; This file contains user-specific settings that override or extend the core configuration

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

