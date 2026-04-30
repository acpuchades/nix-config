{ ... }:

{
  nix.settings = {
    extra-substituters = [ "https://rstats-on-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };
}
