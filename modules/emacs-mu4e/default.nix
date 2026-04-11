{ config, lib, ... }:

{
  options.my.emacs-mu4e = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Emacs packages for mu4e mail client.";
    };
  };

  config = {
    # Configure Emacs with mu4e packages
    programs.emacs = {
      enable = lib.mkDefault true;
      extraPackages = epkgs: with epkgs; [
        # Mail client
        mu4e
      ] ++ config.my.emacs-mu4e.extraPackages;
    };

    # mu4e base configuration that will be loaded by init.el
    home.file.".emacs.d/config/35-mu4e.el".source = ./config/35-mu4e.el;
    
    # Nix integration for mu4e
    home.file.".emacs.d/config/05-nix-integration-mu4e.el".text = ''
      ;; Nix-provided mu
      (setq mu4e-mu-binary "${config.programs.mu.package}/bin/mu")
    '';
  };
}
