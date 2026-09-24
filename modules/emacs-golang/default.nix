{ ... }:

{
  # The toolchain (gopls, gotools) comes from modules/golang-dev — the
  # *-dev modules own binaries, the emacs-* modules own elisp. The config
  # uses only the built-in go-ts-mode, so no external Emacs packages either.

  # Configuración de Go para Emacs
  home.file.".emacs.d/config/75-go.el".source = ./config/75-go.el;
}
