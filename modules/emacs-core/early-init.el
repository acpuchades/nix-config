;; Disable GUI elements early
(menu-bar-mode   -1)
(tool-bar-mode   -1)
(scroll-bar-mode -1)

;; Set frame size and other visual parameters before first frame
(setq default-frame-alist '((width                . 120)
                            (height               .  50)
                            (menu-bar-lines       .   0)
                            (tool-bar-lines       .   0)
                            (vertical-scroll-bars . nil)))

(when (eq window-system 'ns)
  (add-to-list 'default-frame-alist '(ns-transparent-titlebar . t)))

;; Avoid resizing flicker
(setq frame-inhibit-implied-resize t)

;; package.el MUST activate at startup: nix's site-start.el only puts the
;; store's elpa dirs on `load-path', it never loads their *-autoloads.el, and
;; without those every autoloaded entry point (`gcmh-mode', the :hook/:commands
;; deferral in every use-package form) is a void-function at startup.
;; What has to stay out is ~/.emacs.d/elpa, where runtime installs once
;; accumulated copies that shadowed the pinned Nix set — so point
;; `package-user-dir' at an unused path instead of disabling activation.
(setq package-user-dir (expand-file-name "elpa-unused" user-emacs-directory))

;; Disable package-quickstart: with Nix-managed packages the store paths
;; change on each rebuild, leaving the cache pointing at deleted paths.
(setq package-quickstart nil)

;; Nix AOT-compiles every package at build time; JIT compilation would only
;; churn ~/.emacs.d/eln-cache. (native-comp-deferred-compilation is the
;; pre-Emacs-29 spelling of this variable.)
(setq native-comp-jit-compilation nil)

;;Lower gc during startup and restore thereafter
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6
      file-name-handler-alist-old file-name-handler-alist
      file-name-handler-alist nil)

;; Only percentage and handlers are restored here: gc-cons-threshold is
;; handed to gcmh-mode (00-core.el), which starts on this same hook.
(add-hook 'emacs-startup-hook
  (lambda ()
    (setq gc-cons-percentage 0.1
          file-name-handler-alist file-name-handler-alist-old)))

;; No package-archives on purpose: packages come from Nix, and configured
;; archives are what once let a startup `package-refresh-contents` install
;; runtime copies into ~/.emacs.d/elpa that shadowed the pinned set.
