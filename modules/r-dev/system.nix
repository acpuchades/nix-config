{ ... }:

{
  nix.settings = {
    extra-substituters = [
      "https://rstats-on-nix.cachix.org"
    ];
    extra-trusted-substituters = [ "https://rstats-on-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:oMJOoBGKPOLGIKgRnMBbMXBTklu4SaBdd5SGGhIfOKQ="
    ];
  };
}
