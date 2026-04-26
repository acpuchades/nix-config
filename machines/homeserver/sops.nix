{ config, ... }:
{
  defaultSopsFile = ./secrets/default.yml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  secrets = {

    "ddclient/domain" = { key = "ddclient/domain"; };
    "ddclient/password" = { key = "ddclient/password"; };

    "mailjet/token" = { key = "mailjet/token"; };
    "mailjet/secret" = { key = "mailjet/secret"; };

    "nextcloud/admin-pass" = {
      key = "nextcloud/admin-pass";
      owner = config.users.users.nextcloud.name;
      group = config.users.users.nextcloud.group;
    };

    "caddy/adguard-hash" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "caddy/prefect-hash" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "passwd/alex" = {
      key = "passwd/alex";
      neededForUsers = true;
    };

    "wireguard/private-key" = { key = "wireguard/privatekey"; };

    "wifi/network" = { key = "wifi/network"; };
    "wifi/password" = { key = "wifi/password"; };

  };

  templates = {

    "caddy/adguard-auth" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
      content = ''
        basic_auth {
          admin ${config.sops.placeholder."caddy/adguard-hash"}
        }
      '';
    };

    "caddy/prefect-auth" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
      content = ''
        basic_auth {
          admin ${config.sops.placeholder."caddy/prefect-hash"}
        }
      '';
    };

    "ddclient/config".content = ''
        use=web, web=checkip.amazonaws.com
        protocol=namecheap
        server=dynamicdns.park-your-domain.com
        login=${config.sops.placeholder."ddclient/domain"}
        password=${config.sops.placeholder."ddclient/password"}
        home,www
    '';

    "postfix/sasl_passwd" = {
      owner = "postfix";
      group = "postfix";
      mode = "0400";
      content = ''
        [in-v3.mailjet.com]:587 ${config.sops.placeholder."mailjet/token"}:${config.sops.placeholder."mailjet/secret"}
      '';
    };

    "wifi/secrets".content = ''
      home-wlan-psk=${config.sops.placeholder."wifi/password"}
    '';

  };

}
