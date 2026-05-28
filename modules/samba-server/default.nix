{ config, lib, pkgs, ... }:

let
  cfg = config.my.samba-server;
in
{
  options.my.samba-server = {
    enable = lib.mkEnableOption "Samba (SMB) file server";

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group owning auto-created share directories";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = lib.literalExpression ''
        {
          alex = config.sops.secrets."samba/alex".path;
          bob  = config.sops.secrets."samba/bob".path;
        }
      '';
      description = ''
        Map of existing UNIX user → file containing that user's SMB password.
        Samba keeps its own password database separate from the system one, so
        each password is loaded into the passdb before smbd starts (typically a
        sops secret path). Each key must be a real UNIX account.
      '';
    };

    workgroup = lib.mkOption {
      type = lib.types.str;
      default = "WORKGROUP";
      description = "SMB workgroup name";
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        CIDR ranges allowed to reach the SMB port. Enforced both at the
        firewall (source-restricted accept rules) and inside Samba via
        `hosts allow`. Empty means no firewall opening is added (VPN peers on a
        trusted interface can still connect).
      '';
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (
        lib.types.oneOf [ lib.types.str lib.types.int lib.types.bool ]
      ));
      default = {};
      example = lib.literalExpression ''
        {
          shared = {
            path = "/srv/share";
            "read only" = false;
            "valid users" = "alex";
          };
        }
      '';
      description = ''
        Share definitions, passed through to `services.samba.settings`. Any
        share that sets `path` gets that directory created (owned by `user`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.samba = {
      enable = true;
      # We open the firewall ourselves, source-restricted to allowedNetworks.
      openFirewall = false;
      # No NetBIOS/WINS: modern clients (incl. macOS) connect over TCP 445.
      nmbd.enable = false;
      winbindd.enable = false;

      settings = {
        global = {
          "workgroup" = cfg.workgroup;
          "server string" = config.networking.hostName;
          "server role" = "standalone server";

          # Require SMB3 with mandatory transport encryption.
          "server min protocol" = "SMB3";
          "smb encrypt" = "required";

          # No anonymous access; map failed logins to nothing.
          "guest account" = "nobody";
          "map to guest" = "never";

          # Defence in depth on top of the firewall rules below.
          "hosts allow" = lib.concatStringsSep " " (cfg.allowedNetworks ++ [ "127.0.0.1" ]);
          "hosts deny" = "0.0.0.0/0";

          # macOS interoperability (Finder, resource forks, xattrs).
          "vfs objects" = "catia fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";
        };
      } // cfg.shares;
    };

    # Create directories for shares that declare a path. Owned root:<group>,
    # mode 2770: the share group gets full access and the setgid bit makes new
    # files/dirs inherit that group, so all group members can read/write each
    # other's uploads.
    systemd.tmpfiles.rules = lib.mapAttrsToList
      (_: share: "d ${share.path} 2770 root ${cfg.group} -")
      (lib.filterAttrs (_: share: share ? path) cfg.shares);

    # Samba's passdb is separate from the system password database, so load each
    # user's SMB password into it before smbd starts.
    systemd.services.samba-provision-users = {
      description = "Provision Samba passwords";
      wantedBy = [ "multi-user.target" ];
      before = [ "samba-smbd.service" ];
      path = [ config.services.samba.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatStringsSep "\n" ([ "set -eu" ] ++ lib.mapAttrsToList
        (user: file: ''
          pass="$(cat ${file})"
          if pdbedit -L 2>/dev/null | cut -d: -f1 | grep -qx ${user}; then
            printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -s ${user}
          else
            printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -s -a ${user}
          fi
        '')
        cfg.users);
    };

    # Allow SMB (TCP 445) only from the configured networks. Inserted at the top
    # of the nixos-fw chain so it precedes the default refuse rule. VPN peers are
    # already covered via the trusted wg interface; these rules cover the LAN.
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n"
      (net: "iptables -I nixos-fw -p tcp -s ${net} --dport 445 -j nixos-fw-accept")
      cfg.allowedNetworks;

    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n"
      (net: "iptables -D nixos-fw -p tcp -s ${net} --dport 445 -j nixos-fw-accept || true")
      cfg.allowedNetworks;
  };
}
