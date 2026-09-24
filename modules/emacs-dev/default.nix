{ lib, ... }:

{
  # Configure Emacs with development packages
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [

      # Development tools. Deliberately absent: which-key, project and
      # editorconfig (built into Emacs 30 — a MELPA copy here would shadow the
      # bundled version; copilot still pulls MELPA editorconfig in as its own
      # dependency, so that one shadows it while emacs-copilot is imported)
      # and the treesit grammars (emacs-core owns them via
      # treesit-extra-load-path; a second declaration here could silently
      # diverge into a different store closure).
      magit
      treesit-auto
      multiple-cursors
      rainbow-delimiters
      rainbow-mode

      # Plain .md everywhere (poly-markdown in emacs-ess builds on it for .Rmd)
      markdown-mode
    ];
  };

  # Development configuration that will be loaded by init.el
  home.file.".emacs.d/config/30-devel.el".source = ./config/30-devel.el;
  home.file.".emacs.d/config/31-prog-mode.el".source = ./config/31-prog-mode.el;
}
