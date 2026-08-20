{ config, lib, pkgs, ... }:

# One owner for `services.caddy.package`.
#
# Caddy plugins are compiled in, so wanting one is a property of the *build*,
# not of a vhost — and `services.caddy.package` is a single-value option, so the
# first module to need a second plugin cannot simply set it too: two definitions
# collide and the eval fails. That was the state this module fixes, with
# `acme-cloudflare` holding the package because it happened to be the first one
# to need a plugin, leaving anything else silently coupled to whether ACME was
# enabled at all.
#
# So the list is the mergeable thing and the package is derived from it. A module
# contributes what it needs — `my.caddy-plugins.plugins = [ "…@vX" ]` — and NixOS
# concatenates the definitions, the way `globalConfig` already concatenates.
let cfg = config.my.caddy-plugins;
in
{
  options.my.caddy-plugins = {
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      description = ''
        xcaddy plugin specs to build Caddy with, `module@version`. Any module may
        add to this; the definitions merge. Deduplicated and sorted before the
        build, so the derivation does not change when an unrelated module is
        toggled and the resulting `hash` depends on the *set*, not the order the
        imports happen to be in.

        Setting this at all replaces `services.caddy.package`.
      '';
    };

    hash = lib.mkOption {
      type = lib.types.str;
      default = lib.fakeHash;
      description = ''
        Vendor hash for the assembled plugin set. It is a property of the whole
        list, so it lives with the machine that fixes the list rather than with
        any one contributor — a module adding a plugin cannot know it.

        **Adding or bumping a plugin changes this.** Leave it, rebuild, and take
        the `got:` value out of the mismatch error. The failure is loud and names
        the answer, which is the reason this defaults to `fakeHash` rather than
        to something that would build the wrong tree quietly.
      '';
    };
  };

  config = lib.mkIf (cfg.plugins != [ ]) {
    services.caddy.package = pkgs.caddy.withPlugins {
      plugins = lib.sort (a: b: a < b) (lib.unique cfg.plugins);
      inherit (cfg) hash;
    };
  };
}
