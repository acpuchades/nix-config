{ pkgs, ... }:

{
  agents = {
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
