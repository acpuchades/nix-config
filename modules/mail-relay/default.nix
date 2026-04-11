{ config, lib, pkgs, ... }:

{
  options.my.mail-relay = {
    enable = lib.mkEnableOption "SMTP mail relay";
    
    origin = lib.mkOption {
      type = lib.types.str;
      description = "Mail origin domain";
    };
    
    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Mail hostname";
    };
    
    relayHost = lib.mkOption {
      type = lib.types.str;
      description = "Relay host (e.g., [smtp.example.com]:587)";
    };
    
    saslPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to SASL password file";
    };
    
    destinations = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["localhost" "localhost.localdomain"];
      description = "Mail destinations";
    };
  };

  config = lib.mkIf config.my.mail-relay.enable {
    # SMTP relay with Postfix
    services.postfix = {
      enable = true;
      settings.main = {
        myorigin = config.my.mail-relay.origin;
        myhostname = config.my.mail-relay.hostname;
        inet_interfaces = "loopback-only";
        mydestination = lib.concatStringsSep ", " (
          config.my.mail-relay.destinations ++ ["$myhostname" "homeserver"]
        );
        relayhost = [ config.my.mail-relay.relayHost ];
        smtp_address_preference = "ipv4";
        smtp_tls_security_level = "encrypt";
        smtp_tls_loglevel = "1";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_password_maps = "texthash:${config.my.mail-relay.saslPasswordFile}";
        smtp_sasl_security_options = "noanonymous";
      };
    };
  };
}
