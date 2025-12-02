inputs@{ config, pkgs, ... }:

{
  email = {
    maildirBasePath = "Mail";
    accounts.icloud = {
      primary = true;
      address = "acaravacapuchades@icloud.com";
      userName = "acaravacapuchades@icloud.com";
      realName = "Alejandro Caravaca Puchades";
      passwordCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."icloud/password".path}";

      maildir = {
        path = "iCloud";
      };

      imap = {
        host = "imap.mail.me.com";
        port = 993;
        tls.enable = true;
      };

      smtp = {
        host = "smtp.mail.me.com";
        port = 587;
        tls = {
          enable = true;
          useStartTls = true;
        };
      };

      mbsync = {
        enable = true;
        create = "both";
        expunge = "both";
        remove = "maildir";
        subFolders = "Verbatim";
        patterns = [ "*" "!Junk" ];

        extraConfig = {
          account = {
            Host = "imap.mail.me.com";
            User = "acaravacapuchades@icloud.com";
            TLSType = "IMAPS";
            AuthMechs = "LOGIN";
          };
          channel = {
            Sync = "All";
          };
          local = {
            Trash = "Some";
          };
        };
      };

      msmtp.enable = true;
      mu.enable = true;

    };
  };
}
