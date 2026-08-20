{ config, lib, ... }:

{
  options.my.acme-cloudflare = {
    enable = lib.mkEnableOption "Cloudflare DNS-01 ACME challenge for Caddy";

    email = lib.mkOption {
      type = lib.types.str;
      default = "admin@acpuchades.com";
      description = "Email address for ACME certificate notifications";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "Environment file containing CLOUDFLARE_API_TOKEN";
    };
  };

  config = lib.mkIf config.my.acme-cloudflare.enable {
    # The DNS-01 solver is a compiled-in plugin. The package itself is assembled
    # by my.caddy-plugins, which owns `services.caddy.package` — this module used
    # to set it directly, which made it the only place a plugin could be added
    # and quietly coupled every other plugin to ACME being enabled.
    my.caddy-plugins.plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];

    services.caddy = {
      globalConfig = ''
        cert_issuer acme {
          email ${config.my.acme-cloudflare.email}
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1:53 8.8.8.8:53
        }
      '';
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile =
      config.my.acme-cloudflare.credentialsFile;
  };
}
