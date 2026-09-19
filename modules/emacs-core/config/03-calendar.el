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
  ;; This flag alone does the marking. Never add diary-mark-entries to
  ;; diary-mark-entries-hook — that hook runs AT THE END of
  ;; diary-mark-entries itself, so it recurses forever and hangs M-x calendar.
  (calendar-mark-diary-entries-flag t)
  (calendar-today-visible-hook '(calendar-mark-today))
  (diary-date-forms diary-european-date-forms))


