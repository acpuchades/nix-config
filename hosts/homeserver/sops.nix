{ config, ... }:
{
  defaultSopsFile = ./secrets/default.yml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  ssecrets = {
    "ddclient/domain" = { key = "ddclient/domain"; };
    "ddclient/password" = { key = "ddclient/password"; };

    "mailjet/token" = { key = "mailjet/token"; };
    "mailjet/secret" = { key = "mailjet/secret"; };

    "passwd/alex" = {
      key = "passwd/alex";
      neededForUsers = true;
    };

    "nginx/htpasswd/adguard" = {
      owner = "nginx";
      group = "nginx";
      mode = "0400";
    };

    "nginx/htpasswd/prefect" = {
      owner = "nginx";
      group = "nginx";
      mode = "0400";
    };

    "vpn/in/wg-private-key" = { key = "vpn/in/wg-private-key"; };
    "vpn/in/wifi-password" = { key = "vpn/in/wifi-password"; };

    "wg/server/private-key" = { key = "wireguard/server/privatekey"; };
    "wg/peers/alex-iphone/psk" = { key = "wireguard/peers/alex-iphone/psk"; };
    "wg/peers/alex-ipad/psk" = { key = "wireguard/peers/alex-ipad/psk"; };
    "wg/peers/alex-macbookpro/psk" = { key = "wireguard/peers/alex-macbookpro/psk"; };
    "wg/peers/mubin-phone/psk" = { key = "wireguard/peers/mubin-phone/psk"; };
    "wg/peers/mubin-laptop/psk" = { key = "wireguard/peers/mubin-laptop/psk"; };

    "wifi/network" = { key = "wifi/network"; };
    "wifi/password" = { key = "wifi/password"; };
  };

  templates = {

    "ddclient/config".content = ''
        use=web, web=checkip.amazonaws.com
        protocol=namecheap
        server=dynamicdns.park-your-domain.com
        login=${config.sops.placeholder."ddclient/domain"}
        password=${config.sops.placeholder."ddclient/password"}
        www,adguard,bitwarden,home,prefect
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
