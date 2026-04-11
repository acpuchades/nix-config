{ config, lib, pkgs, ... }:

{
  options.my.emacs-ess = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for ESS/R development.";
    };
  };

  config = {
    # Configure Emacs with ESS packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # ESS packages
        ess
        ess-smart-equals
        ess-view-data
        
        # R-Markdown and Quarto support
        polymode
        poly-R
        poly-markdown
        quarto-mode
      ] ++ config.my.emacs-ess.extraPackages;
    };

    # ESS configuration that will be loaded by init.el
    home.file.".emacs.d/ess-config.el".text = ''
      ;; Emacs Speaks Statistics
      (use-package ess
        :mode
        (("\\.[Rr]\\'"     . ess-r-mode)
         ("\\.Rprofile\\'" . ess-r-mode))
        :preface
        (defun my/ess-add-sent-code-to-history (proc string &rest _args)
          "Mirror STRING sent by ESS into the inferior's comint history."
          (when (and (string-match-p "[^[:space:]]" string) ; ignore pure whitespace
                     (process-live-p proc))
            (when-let ((buf (process-buffer proc)))
              (with-current-buffer buf
                (when (derived-mode-p 'inferior-ess-mode)
                  ;; One history entry per send (region/line/etc. as a single item)
                  (comint-add-to-input-history string))))))

        (defun my/ess-at-cmdline-p ()
          (when-let ((proc (get-buffer-process (current-buffer))))
            (>= (point) (marker-position (process-mark proc)))))
        (defun my/ess-goto-cmdline ()
          (interactive)
          (goto-char (marker-position (process-mark (get-buffer-process (current-buffer))))))
        (defun my/ess-up-or-prev-line ()
          (interactive)
          (if (my/ess-at-cmdline-p) (comint-previous-input 1) (previous-line 1)))
        (defun my/ess-down-or-next-line ()
          (interactive)
          (if (my/ess-at-cmdline-p) (comint-next-input 1) (next-line 1)))

        (defun my/ess-repl-setup ()
          (setq-local comint-prompt-read-only t
                      comint-input-ignoredups t
                      comint-buffer-maximum-size 5000)
          (add-hook 'comint-output-filter-functions #'comint-truncate-buffer nil t))

        (defun my/ess-setup-eval-keys ()
          (local-set-key (kbd "C-c C-r")    #'ess-eval-region)
          (local-set-key (kbd "C-c C-b")    #'ess-eval-buffer)
          (local-set-key (kbd "C-c C-n")    #'ess-eval-line)
          (local-set-key (kbd "C-<return>") #'ess-eval-region-or-function-or-paragraph-and-step))

        (defun my/ess-inf-setup-navigate-keys ()
          (local-set-key (kbd "C-a")        #'my/ess-goto-cmdline)
          (local-set-key (kbd "<up>")       #'my/ess-up-or-prev-line)
          (local-set-key (kbd "<down>")     #'my/ess-down-or-next-line))
        :hook
        (ess-mode          . my/ess-setup-eval-keys)
        (inferior-ess-mode . my/ess-repl-setup)
        (inferior-ess-mode . my/ess-inf-setup-navigate-keys)
        :config
        (advice-add 'ess-send-string :after #'my/ess-add-sent-code-to-history)
        :custom
        (ess-ask-for-ess-directory nil)
        (ess-default-style 'RStudio)
        (ess-use-flymake nil))

      (use-package ess-r-mode
        :after ess
        :ensure nil
        :no-require t
        :preface
        (defun my/ess-r-insert-pipe ()
          "Insert the R pipe operator `|>` at point, with preceding space."
          (interactive)
          (just-one-space 1)
          (insert "|> "))
        (defun my/ess-r-insert-pipe-and-newline ()
          "Insert the R pipe operator `|>` at point, with preceding space and followed by newline."
          (interactive)
          (end-of-line)
          (just-one-space 1)
          (insert "|>")
          (newline-and-indent))
        :bind
        (:map ess-r-mode-map
              ("C-c p SPC"      . my/ess-r-insert-pipe)
              ("C-c p <return>" . my/ess-r-insert-pipe-and-newline))
        (:map inferior-ess-r-mode-map
              ("C-c p SPC"      . my/ess-r-insert-pipe)
              ("C-c p <return>" . my/ess-r-insert-pipe-and-newline))
        :custom
        (inferior-R-args "--no-save --no-restore-data --quiet"))

      (use-package ess-smart-equals
        :after ess
        :config (ess-smart-equals-activate))

      (use-package ess-view-data
        :after ess
        :bind
        (:map ess-r-mode-map
              ("C-c v" . ess-view-data-print)))

      ;; R-Markdown support
      (use-package polymode)
      (use-package poly-R)
      (use-package poly-markdown
        :mode (("\\.md\\'"  . poly-markdown-mode)
               ("\\.Rmd\\'" . poly-markdown+r-mode)))

      ;; Quarto support
      (use-package quarto-mode
        :mode (("\\.qmd\\'" . poly-quarto-mode))
        :bind
        (:map poly-quarto-mode-map
              ("C-c C-c" . polymode-eval-chunk)))
    '';

    # R snippets for yasnippet
    home.file.".emacs.d/snippets/ess-r-mode/ggcox".source = ./snippets/ggcox;
    home.file.".emacs.d/snippets/ess-r-mode/ggkm".source = ./snippets/ggkm;
    home.file.".emacs.d/snippets/ess-r-mode/ggpie".source = ./snippets/ggpie;
    home.file.".emacs.d/snippets/ess-r-mode/gtreg".source = ./snippets/gtreg;
    home.file.".emacs.d/snippets/ess-r-mode/gtsum".source = ./snippets/gtsum;
    home.file.".emacs.d/snippets/ess-r-mode/rix".source = ./snippets/rix;
  };
}
