;; Nix-provided coreutils
(setq insert-directory-program "${pkgs.coreutils}/bin/ls")

;; Nix-provided grammars
(setq treesit-extra-load-path
    '("${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib"))

;; Nix-provided mu
(setq mu4e-mu-binary "${config.programs.mu.package}/bin/mu")
