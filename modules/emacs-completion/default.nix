{ config, lib, ... }:

{
  options.my.emacs-completion = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for completion framework.";
    };
  };

  config = {
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
      ] ++ config.my.emacs-completion.extraPackages;
    };

    # Completion configuration that will be loaded by init.el
    home.file.".emacs.d/config/05-completion.el".source = ./config/05-completion.el;
  };
}
