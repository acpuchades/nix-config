{ config, lib, ... }:
{
  enable = true;
  enableDefaultConfig = false;
  matchBlocks."*" = {
    identitiesOnly = true;
    identityFile = [
      "${config.sops.secrets."ssh/nitrokey-stub".path}"
      "~/.ssh/id_ed25519"
    ];
  };
}
