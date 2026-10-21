{ config, lib, ... }:

let
  cfg = config.my.media-server;

  # Jellyfin's HTTP port. Jellyfin binds 0.0.0.0 (its bind address is stateful
  # config, not set here); who may actually reach it directly is governed by
  # the allowedDirectNetworks firewall rules below — plaintext, Jellyfin's own
  # login, no nginx. Everyone else comes through the nginx vhost.
  jellyfinPort = 8096;

  # When mediaDir lives inside a shared (Samba) tree, the library folders are
  # created root:<shareGroup> 2770 so group members can drop files over SMB and
  # the setgid bit makes new content inherit the group; jellyfin joins the group
  # to read it. Otherwise the folders are owned by the jellyfin service account.
  shared = cfg.shareGroup != null;

  accelerated = cfg.accelerationDevices != [ ];
in
{
  options.my.media-server = {
    enable = lib.mkEnableOption "Jellyfin media server";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for the Jellyfin reverse proxy";
    };

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/shared/Media";
      description = "Base directory under which the library folders are created";
    };

    libraries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Movies"
        "Shows"
        "Music"
      ];
      description = ''
        Library subfolders to create under mediaDir. Each becomes a directory
        you point a Jellyfin library at; add new entries to provision more.
      '';
    };

    shareGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "share";
      description = ''
        If set, library folders are owned root:<shareGroup> with mode 2770 and
        the jellyfin user joins this group. Use it to put the libraries inside
        an existing Samba share so files dropped over SMB are readable by
        Jellyfin. When null the folders are owned by the jellyfin account.
      '';
    };

    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };

    allowedDirectNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.2.0/24" ];
      description = ''
        CIDR ranges allowed to reach Jellyfin's own HTTP port (8096) directly,
        in plaintext, bypassing nginx — what TV and mobile apps on the LAN use.
        Empty closes direct access entirely (the vhost is then the only way in).
      '';
    };

    accelerationDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "/dev/dri/renderD128" ]'';
      description = ''
        DRI render nodes to expose to Jellyfin for hardware transcoding. Grants
        the service rw access to each device and adds the jellyfin user to the
        `video`/`render` groups. The actual codec/VAAPI settings still have to be
        enabled in Jellyfin's dashboard.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      # No global opening; direct :8096 access is granted per source network
      # below, everything else goes through nginx + allowedNetworks.
      openFirewall = false;
    };

    # Direct app access, source-restricted (modules/firewall-allow). Jellyfin's
    # own login still applies there.
    my.firewall-allow.jellyfin = {
      networks = cfg.allowedDirectNetworks;
      ports = [ jellyfinPort ];
    };

    # Let jellyfin read the (group-owned) share, and reach the GPU when transcoding.
    users.users.jellyfin.extraGroups =
      lib.optional shared cfg.shareGroup
      ++ lib.optionals accelerated [
        "video"
        "render"
      ];

    systemd.services.jellyfin.serviceConfig.DeviceAllow = lib.mkIf accelerated (
      map (d: "${d} rw") cfg.accelerationDevices
    );

    # Provision the media root and each library folder.
    systemd.tmpfiles.rules =
      let
        mk =
          path:
          if shared then "d ${path} 2770 root ${cfg.shareGroup} -" else "d ${path} 0750 jellyfin jellyfin -";
      in
      [ (mk cfg.mediaDir) ] ++ map (lib: mk "${cfg.mediaDir}/${lib}") cfg.libraries;

    # mediaDir is an option and typically lives on a separate data disk, but
    # systemd infers no mount dependency from a path a service merely reads. If
    # jellyfin starts while that filesystem is still mounting it scans the empty
    # stub under the mountpoint and marks the whole library missing — which it
    # then persists in its own database, so the damage outlives the mount
    # landing. Resolves to whichever mount provides the path, so it follows the
    # option and no-ops when mediaDir is on /.
    systemd.services.jellyfin.unitConfig.RequiresMountsFor = [ cfg.mediaDir ];

    services.nginx.virtualHosts.${cfg.hostName} = {
      inherit (cfg) allowedNetworks;
      # Jellyfin's recommended proxy settings: websockets for the session
      # socket (remote control, sync play), no response buffering so streams
      # start immediately, and room for subtitle/image uploads.
      extraConfig = "client_max_body_size 20m;";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString jellyfinPort}";
        proxyWebsockets = true;
        extraConfig = "proxy_buffering off;";
      };
    };
  };
}
