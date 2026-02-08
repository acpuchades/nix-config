inputs@{ config, host, ...}:
{
  age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  age.generateKey = true;
  defaultSopsFile = ./secrets/default.yml;
  defaultSopsFormat = "yaml";

  secrets = {

    "anthropic/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "anthropic/token";
    };

    "github/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "github/token";
    };

    "icloud/password" = {
      key = "icloud/password";
    };

    "prefect/user" = {
      sopsFile = ./secrets/default.yml;
      key = "prefect/user";
    };

    "prefect/password" = {
      sopsFile = ./secrets/default.yml;
      key = "prefect/password";
    };

  };

  templates = {
    "gh/hosts.yml".content = ''
      github.com:
        user: acpuchades
        git_protocol: https
        oauth_token: ${config.sops.placeholder."github/token"}
    '';

    "prefect/profiles.toml".content = ''
      active = "ephemeral"

      [profiles.local]
      PREFECT_API_URL = "http://127.0.0.1:4200/api"

      [profiles.homeserver]
      PREFECT_API_URL = "https://prefect.acpuchades.com/api"
      PREFECT_API_AUTH_STRING = "${config.sops.placeholder."prefect/user"}:${config.sops.placeholder."prefect/password"}"
    '';
  };

}
