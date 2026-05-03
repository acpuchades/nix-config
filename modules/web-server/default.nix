{ config, lib, ... }:

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

          redirect = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Permanent redirect target URL (request path and query are appended)";
          };

          basicAuthFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Basic auth file";
          };

          allowedNetworks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Restrict access to these CIDR ranges (empty = unrestricted)";
          };
        };
      });
      default = {};
      description = "Virtual hosts configuration";
    };
  };

  config = lib.mkIf config.my.web-server.enable {
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.caddy = {
      enable = true;
      email = config.my.web-server.adminEmail;
      virtualHosts = lib.mapAttrs (_name: hostConfig: {
        extraConfig = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
          (lib.optionalString (hostConfig.allowedNetworks != [])
            "@denied not remote_ip ${lib.concatStringsSep " " hostConfig.allowedNetworks}\nabort @denied")
          (lib.optionalString (hostConfig.basicAuthFile != null)
            "import ${hostConfig.basicAuthFile}")
          (lib.optionalString (hostConfig.root != null)
            "root * ${hostConfig.root}\nfile_server")
          (lib.optionalString (hostConfig.proxyPass != null)
            "reverse_proxy ${hostConfig.proxyPass}")
          (lib.optionalString (hostConfig.redirect != null)
            "redir ${hostConfig.redirect}{uri} permanent")
          "encode gzip"
        ]);
      }) config.my.web-server.virtualHosts;
    };
  };
}
