{ config, lib, pkgs, ... }:

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
    services.caddy = {
      # Run nixos-rebuild once with lib.fakeHash, copy the expected hash from
      # the error output, then replace lib.fakeHash with the real value.
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-4WF7tIx8d6O/Bd0q9GhMch8lS3nlR5N3Zg4ApA3hrKw=";
      };
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
