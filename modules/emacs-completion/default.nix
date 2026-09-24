{ lib, ... }:

{
  # Configure Emacs with completion packages
  programs.emacs = {
    enable = lib.mkDefault true;
    extraPackages = epkgs: with epkgs; [
      # Completion framework
      vertico
      consult
      corfu
      cape
      marginalia
      embark
      embark-consult
      orderless
      nerd-icons-corfu
    ];
  };

  # Completion configuration that will be loaded by init.el
  home.file.".emacs.d/config/10-completion.el".source = ./config/10-completion.el;
}
