;; Disable GUI elements early
(menu-bar-mode   -1)
(tool-bar-mode   -1)
(scroll-bar-mode -1)

;; Set frame size and other visual parameters before first frame
(setq default-frame-alist
      '((width                . 120)
        (height               .  60)
        (menu-bar-lines       .   0)
        (tool-bar-lines       .   0)
        (vertical-scroll-bars . nil)))

;; Avoid resizing flicker
(setq frame-inhibit-implied-resize t)

;; Prevent package.el from loading packages before init.el
(setq package-enable-at-startup nil)

;; Enable package quickstart and native compilation
(setq package-quickstart t)
(setq native-comp-deferred-compilation t)

;;Lower gc during startup and restore thereafter
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6
      file-name-handler-alist-old file-name-handler-alist
      file-name-handler-alist nil)

(add-hook 'emacs-startup-hook
  (lambda ()
    (setq gc-cons-threshold (* 128 1024 1024)
          gc-cons-percentage 0.1
          file-name-handler-alist file-name-handler-alist-old)))

;; Add package archives
(setq package-archives
  '(("melpa" . "https://melpa.org/packages/")
    ("gnu"   . "https://elpa.gnu.org/packages/")
    ("nongnu" . "https://elpa.nongnu.org/nongnu/")))
