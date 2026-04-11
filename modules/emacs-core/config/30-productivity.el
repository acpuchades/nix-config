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


