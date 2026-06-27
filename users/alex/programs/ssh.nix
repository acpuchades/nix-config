{ ... }:
{
  enable = true;
  enableDefaultConfig = false;

  settings = {
    homeserver = {
      hostname = "192.168.2.2";
      user = "alex";
    };

    biocluster = {
      hostname = "172.19.1.20";
      user = "acaravaca";
    };
  };
}
