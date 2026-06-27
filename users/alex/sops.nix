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

    "crates-io/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "crates-io/token";
    };

    "github/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "github/token";
    };

    "icloud/password" = {
      key = "icloud/password";
    };

    "ntfy/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "ntfy/token";
    };

    "pypi/token" = {
      sopsFile = ./secrets/${host}.yml;
      key = "pypi/token";
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
    "cargo/credentials.toml".content = ''
      [registry]
      token = "${config.sops.placeholder."crates-io/token"}"
    '';

    "gh/hosts.yml".content = ''
      github.com:
        user: acpuchades
        git_protocol: https
        oauth_token: ${config.sops.placeholder."github/token"}
    '';

    "pypi/pypirc".content = ''
      [pypi]
      username = __token__
      password = ${config.sops.placeholder."pypi/token"}
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
