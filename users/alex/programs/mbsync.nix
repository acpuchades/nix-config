{ config, ... }: {
  enable = true;
  extraConfig = ''
    IMAPAccount icloud
      Host imap.mail.me.com
      User acaravacapuchades@icloud.com
      PassCmd "cat ${config.sops.secrets."icloud/password".path}"
      Port 993
      TLSType IMAPS
      AuthMechs LOGIN

    IMAPStore icloud-remote
      Account icloud

    MaildirStore icloud-local
      Path ~/Mail/
      Inbox ~/Mail/INBOX
      SubFolders Verbatim

    Channel icloud
      Far :icloud-remote:
      Near :icloud-local:
      Patterns *
      Create Both
      SyncState *
  '';
}
