;; Alex's personal Emacs configuration
;; This file contains user-specific settings that override or extend the core
;; configuration. (Language environment and the Spanish calendar live in
;; emacs-core's 02-defaults.el and 03-calendar.el — one owner each.)

;; Where the org files live. Top level, not after-load: the calendar reads
;; diary-file too, and org-roam must see its directory before it loads.
(setq org-directory          "~/Org"
      org-default-notes-file "~/Org/inbox.org"
      org-roam-directory     "~/Org/Roam"
      diary-file             (expand-file-name "~/Org/diary"))

;; Personal org-mode settings (Spanish GTD)
(with-eval-after-load 'org
  ;; Every .org under ~/Org except Roam/ — those are notes, not tasks, and
  ;; agenda-scanning each one would slow every agenda view as the notes grow.
  (setq org-agenda-files
        (when (file-directory-p org-directory)
          (directory-files-recursively
           org-directory "\\.org\\'" nil
           (lambda (dir) (not (string= (file-name-nondirectory dir) "Roam"))))))

  (setq org-refile-targets
        '(("~/Org/tasks.org" :maxlevel . 3)
          (org-agenda-files  :maxlevel . 2)))
  (setq org-refile-target-verify-function
        (lambda ()
          (not (and (buffer-file-name)
                    (string-match-p "inbox\\.org" (buffer-file-name))))))

  ;; Capture templates sit beside org-todo-keywords on purpose: "TAREA" below
  ;; must BE one of those keywords, or the captured headline is a plain one
  ;; that no agenda or todo list ever shows.
  (setq org-capture-templates
        '(("i" "Entrada" entry
           (file "~/Org/inbox.org")
           "* %?\n%U\n")
          ("t" "Tarea" entry
           (file+headline "~/Org/tasks.org" "Tareas")
           "* TAREA %?")
          ("e" "Evento" entry
           (file+headline "~/Org/events.org" "Eventos")
           "* %^{Título}\n%^{Fecha}T\n%?")
          ("n" "Nota" entry
           (file+headline "~/Org/notes.org" "Notas")
           "* %?\n%U\n")))

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

