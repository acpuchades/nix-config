{ config, lib, pkgs, ... }:

{
  options.my.web-server = {
    enable = lib.mkEnableOption "Web server with SSL and reverse proxy";

    adminEmail = lib.mkOption {
      type = lib.types.str;
      description = "Admin email for ACME certificates";
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          root = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Document root for static content";
          };

          proxyPass = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Proxy pass URL";
          };

          proxyWebsockets = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable websocket proxying";
          };

          basicAuthFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Basic auth file";
          };
        };
      });
      default = {};
      description = "Virtual hosts configuration";
    };
  };

  config = lib.mkIf config.my.web-server.enable {
    # ACME certificates management
    security.acme = {
      acceptTerms = true;
      defaults.email = config.my.web-server.adminEmail;
    };

    # Nginx
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts = lib.mapAttrs (name: hostConfig: {
        forceSSL = true;
        enableACME = true;
        root = hostConfig.root;
        basicAuthFile = hostConfig.basicAuthFile;
        locations = lib.mkIf (hostConfig.proxyPass != null) {
          "/" = {
            proxyPass = hostConfig.proxyPass;
            proxyWebsockets = hostConfig.proxyWebsockets;
          };
        };
      }) config.my.web-server.virtualHosts;
    };
  };
}
