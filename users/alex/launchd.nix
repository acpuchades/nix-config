{ config, lib, pkgs, ... }:
{
  launchd = lib.mkIf pkgs.stdenv.isDarwin (
    {
      agents = {
        ntfy = {
          enable = true;
          config = {
            ProgramArguments = [
              "${pkgs.ntfy-sh}/bin/ntfy"
              "subscribe"
              "--from-config"
            ];
            KeepAlive = true;
            RunAtLoad = true;
            # Not /tmp: world-writable, so another user could pre-create these
            # as symlinks; and ntfy logs carry message contents.
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ntfy.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ntfy.err";
          };
        };
      };
    }
  );
}
