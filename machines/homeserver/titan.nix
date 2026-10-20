# titan — body-composition, nutrition, recovery and training analytics
# (titan.acpuchades.com). The app is the PRIVATE acpuchades/titan-web flake: its
# `overlays.default` gives pkgs.titan (the API) and pkgs.titan-frontend (the
# dashboard's static files), its `nixosModules.default` the `services.titan` unit
# (hardened, migrations on start, hourly source sync, a local PostgreSQL database
# and role over peer auth). This file is only the host topology around it.
#
# INTERNAL: LAN and WireGuard peers only, like media/nominatim — the vhost aborts
# every other source, AdGuard rewrites the name to this host, and there is no
# public DNS record (nothing in ddclient). It is multi-user personal HEALTH data:
# sign-up is open, but only to whoever can reach the vhost at all. eva is
# deliberately NOT given it (agents/eva allowedHostnames).
#
# Mail (sign-up confirmation, password reset) goes through the local Postfix on
# 127.0.0.1:25, which relays via Mailjet — the same path cloud-suite uses, so no
# SMTP credential exists for it.
#
# Curried over the flake input for the same reason ./fugazi.nix is: `imports`
# needs it. Its sops secret/template stay in ./sops.nix and its alert unit in
# ./default.nix, per the convention in fugazi.nix's header.
#
# Admin (accounts are otherwise self-service):
#   sudo titan-manage users list            # also create, set-password, disable, enable, delete
{ titan-web }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ./networks.nix) privateNetworks;
  hostName = "titan.acpuchades.com";
  api = "127.0.0.1:${toString config.services.titan.port}";
in
{
  imports = [ titan-web.nixosModules.default ];

  nixpkgs.overlays = [ titan-web.overlays.default ];

  services.titan = {
    enable = true;
    package = pkgs.titan;
    publicUrl = "https://${hostName}";
    # Same origin: emailed links and the OAuth return land on the dashboard.
    dashboardUrl = "https://${hostName}";
    environment.TITAN_DEFAULT_TIMEZONE = config.time.timeZone;
    # TITAN_SECRET_KEY (+ the Withings/Oura OAuth apps once registered).
    environmentFile = config.sops.templates."titan/env".path;
    smtp = {
      host = "127.0.0.1";
      port = 25;
      # Loopback to our own Postfix, which then relays over TLS; its STARTTLS
      # certificate is for m.acpuchades.com, which 127.0.0.1 would not match.
      security = "none";
      from = "titan <noreply@acpuchades.com>";
    };
  };

  # The API never serves the SPA: Caddy does, from the store, and proxies /v1.
  services.caddy.virtualHosts.${hostName}.extraConfig = ''
    @denied not remote_ip ${lib.concatStringsSep " " privateNetworks}
    abort @denied
    header Strict-Transport-Security "max-age=31536000"
    encode gzip

    handle /v1/* {
      reverse_proxy ${api}
    }
    handle /health {
      reverse_proxy ${api}
    }
    handle {
      root * ${pkgs.titan-frontend}
      # Vite fingerprints everything under /assets: cache it for good, and never
      # index.html, so a deploy is picked up on the next load.
      @app not path /assets/*
      header /assets/* Cache-Control "public, max-age=31536000, immutable"
      header @app Cache-Control "no-cache"
      try_files {path} /index.html
      file_server
    }
  '';
}
