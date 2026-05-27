{ pkgs, ... }:
{
  gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin
      then pkgs.pinentry_mac
      else pkgs.pinentry-curses;
  };
}
