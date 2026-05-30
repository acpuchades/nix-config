{ config, ... }:
{
  defaultSopsFile = ./secrets/default.yml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  secrets = {

    "mailjet/token" = { key = "mailjet/token"; };
    "mailjet/secret" = { key = "mailjet/secret"; };

    "nextcloud/admin" = {
      owner = config.users.users.nextcloud.name;
      group = config.users.users.nextcloud.group;
    };

    "cloudflare/account" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "cloudflare/token" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "caddy/adguard" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "caddy/prefect" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };

    "umami/app-secret" = {
      key = "umami/app-secret";
      mode = "0400";
    };

    "passwd/alex" = {
      key = "passwd/alex";
      neededForUsers = true;
    };

    "wireguard/private-key" = { key = "wireguard/private-key"; };

    "wireguard-client/wgproton" = { key = "wireguard-client/wgproton"; };

    "nut/monitor" = {
      mode = "0400";
    };

    "wifi/network" = { key = "wifi/network"; };
    "wifi/password" = { key = "wifi/password"; };

    # One SMB password per user (nested samba/<user> branch). Add a line here
    # for each additional user, then store the value with:
    #   sops machines/homeserver/secrets/default.yml
    "samba/alex" = { mode = "0400"; };

  };

  templates = {

    "caddy/cloudflare-env" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
      content = ''
        CLOUDFLARE_API_TOKEN=${config.sops.placeholder."cloudflare/token"}
      '';
    };

    "caddy/adguard-auth" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
      content = ''
        basic_auth {
          admin ${config.sops.placeholder."caddy/adguard"}
        }
      '';
    };

    "caddy/prefect-auth" = {
      owner = "caddy";
      group = "caddy";
      mode = "0400";
      content = ''
        basic_auth {
          admin ${config.sops.placeholder."caddy/prefect"}
        }
      '';
    };

    "ddclient/config".content = ''
        cache=/var/cache/ddclient/ddclient.cache
        usev4=webv4, webv4=checkip.amazonaws.com
        protocol=cloudflare
        zone=acpuchades.com
        ttl=120
        login=token
        password=${config.sops.placeholder."cloudflare/token"}
        analytics.acpuchades.com,blog.acpuchades.com,gps.acpuchades.com,vpn.acpuchades.com,www.acpuchades.com
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
