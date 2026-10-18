{ config, ... }:
{
  programs.ssh =
    {
      enable = true;
      enableDefaultConfig = false;

      # The biocluster block lives in a sops-rendered fragment (users/alex/sops.nix)
      # so its work username and internal address stay out of this public repo.
      # Rendered at top level, ahead of every Host block; ssh skips a missing
      # Include, so a host that has not rendered it yet still parses.
      includes = [ config.sops.templates."ssh/biocluster.conf".path ];

      settings = {
        homeserver = {
          hostname = "192.168.2.2";
          user = "alex";
        };
      };
    };
}
