{ config, pkgs, ... }:

let

  mailSyncScript = pkgs.writeShellScript "mbsync-mu-sync" ''
    set -euo pipefail
    "${config.programs.mbsync.package}/bin/mbsync" -a
    "${config.programs.mu.package}/bin/mu" index
  '';

in

{
  agents = {
    mbsync-mu = {
      enable = true;
      config = {
        ProgramArguments = [ "${mailSyncScript}" ];
        StartInterval = 600;
        RunAtLoad = true;
      };
    };

    ntfy = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.ntfy}/bin/ntfy"
          "subscribe"
          "--from-config"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/ntfy.log";
        StandardErrorPath = "/tmp/ntfy.err";
      };
    };
  };
}
