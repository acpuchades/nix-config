{ ... }:
{
  enable = true;
  enableDefaultConfig = false;

  matchBlocks = {
    homeserver = {
      hostname = "192.168.2.2";
      user = "alex";
    };
  };
}
