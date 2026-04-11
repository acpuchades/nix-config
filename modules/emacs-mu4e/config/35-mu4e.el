;; Mu4e base configuration
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
  (mu4e-compose-context-policy 'ask-if-none))

(use-package message
  :ensure nil
  :after mu4e
  :custom
  (sendmail-program "msmtp")
  (message-send-mail-function 'message-send-mail-with-sendmail)
  (message-sendmail-envelope-from 'header))
