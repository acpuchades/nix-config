{ config, lib, ... }:

let
  cfg = config.my.media-server;

  # Jellyfin's HTTP port. Not opened in the firewall (openFirewall = false);
  # reachable only via Caddy on loopback, which enforces allowedNetworks.
  jellyfinPort = 8096;

  # When mediaDir lives inside a shared (Samba) tree, the library folders are
  # created root:<shareGroup> 2770 so group members can drop files over SMB and
  # the setgid bit makes new content inherit the group; jellyfin joins the group
  # to read it. Otherwise the folders are owned by the jellyfin service account.
  shared = cfg.shareGroup != null;

  accelerated = cfg.accelerationDevices != [];
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
      default = [ "Movies" "Shows" "Music" ];
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
      default = [];
      description = "Restrict access to these CIDR ranges (empty = unrestricted)";
    };

    accelerationDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
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
      # Firewall stays closed; access is mediated by Caddy + allowedNetworks.
      openFirewall = false;
    };

    # Let jellyfin read the (group-owned) share, and reach the GPU when transcoding.
    users.users.jellyfin.extraGroups =
      lib.optional shared cfg.shareGroup
      ++ lib.optionals accelerated [ "video" "render" ];

    systemd.services.jellyfin.serviceConfig.DeviceAllow =
      lib.mkIf accelerated (map (d: "${d} rw") cfg.accelerationDevices);

    # Provision the media root and each library folder.
    systemd.tmpfiles.rules =
      let mk = path:
        if shared
        then "d ${path} 2770 root ${cfg.shareGroup} -"
        else "d ${path} 0750 jellyfin jellyfin -";
      in [ (mk cfg.mediaDir) ]
        ++ map (lib: mk "${cfg.mediaDir}/${lib}") cfg.libraries;

    services.caddy.virtualHosts."${cfg.hostName}".extraConfig =
      lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        (lib.optionalString (cfg.allowedNetworks != [])
          "@denied not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}\nabort @denied")
        "reverse_proxy http://127.0.0.1:${toString jellyfinPort}"
        "encode gzip"
      ]);
  };
}
