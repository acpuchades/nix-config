inputs@{ config, lib, host, ...}:

let
  defaultSopsFile = ./secrets/default.yml;

  # SOPS encrypts values but leaves the YAML key structure in plaintext, so the
  # `git-crypt:` subtree can be walked without decrypting the file. Returns the
  # "/"-joined path of every leaf below it, relative to `git-crypt:` itself.
  gitCryptKeys =
    let
      lines = lib.splitString "\n" (builtins.readFile defaultSopsFile);
      step = acc: line:
        let
          entry = builtins.match "( *)([^:]+): *(.*)" line;
          indent = builtins.stringLength (builtins.elemAt entry 0);
          name = builtins.elemAt entry 1;
          value = builtins.elemAt entry 2;
          parents = builtins.filter (p: p.indent < indent) acc.stack;
        in
        if !acc.inside then acc // { inside = line == "git-crypt:"; }
        else if entry == null || indent == 0 then acc // { inside = false; }
        else {
          inside = true;
          stack = parents ++ [ { inherit indent name; } ];
          # A leaf carries an inline value (ENC[...]); a group does not.
          keys = acc.keys ++ lib.optional (value != "")
            (lib.concatStringsSep "/" (map (p: p.name) parents ++ [ name ]));
        };
    in
    (builtins.foldl' step { inside = false; stack = [ ]; keys = [ ]; } lines).keys;

  gitCryptSecrets = lib.genAttrs (map (k: "git-crypt/${k}") gitCryptKeys) (name: {
    sopsFile = defaultSopsFile;
    key = name;
  });
in
{
  age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  age.generateKey = true;
  inherit defaultSopsFile;
  defaultSopsFormat = "yaml";

  secrets = gitCryptSecrets // {

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
