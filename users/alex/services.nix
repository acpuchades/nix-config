{ config, lib, pkgs, ... }:
{
  gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin
      then pkgs.pinentry_mac
      else pkgs.pinentry-curses;
  };

  mbsync = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    frequency = "*:0/10";
    postExec = "${config.programs.mu.package}/bin/mu index";
  };

}
