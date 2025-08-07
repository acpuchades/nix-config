;; Disable GUI elements early
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; Set frame size and other visual parameters before first frame
(setq default-frame-alist
	'((width                . 100)
	  (height               .  40)
	  (menu-bar-lines       .   0)
	  (tool-bar-lines       .   0)
	  (vertical-scroll-bars . nil)))

;; Avoid resizing flicker
(setq frame-inhibit-implied-resize t)

;; Skip startup screen
(setq inhibit-startup-message t)

;; Prevent package.el from loading packages before init.el
(setq package-enable-at-startup nil)
