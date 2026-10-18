# Source-restricted firewall accepts — the one implementation of this host's
# firewall convention: there is no blanket LAN accept and wg0 is not a trusted
# interface, so a service LAN/VPN clients reach directly declares exactly which
# source networks may reach which of its ports:
#
#   my.firewall-allow.samba = { networks = cfg.allowedNetworks; ports = [ 445 ]; };
#
# Each (network, protocol) pair becomes one accept inserted at the head of
# nixos-fw, so it precedes the default refuse rule, plus the matching delete on
# firewall stop — rendered from the same spec, so the two cannot drift. Insert
# order does not matter while every rule in nixos-fw is an accept (they all
# are). A source rule matches whatever interface the packet arrived on, so VPN
# peers are covered by listing the wg prefixes. IPv6 networks go to ip6tables:
# iptables rejects them, and the v6 chain is otherwise closed.
#
# A library module like wireguard-client: no enable gate, inert while empty.
# iptables backend only — nftables is not enabled on this host.
{ config, lib, ... }:

let
  ruleSpecs =
    allow:
    let
      ports =
        if lib.length allow.ports == 1 then
          "--dport ${toString (lib.head allow.ports)}"
        else
          "-m multiport --dports ${lib.concatMapStringsSep "," toString allow.ports}";
    in
    lib.concatMap (
      net:
      map (proto: {
        tool = if lib.hasInfix ":" net then "ip6tables" else "iptables";
        rule = "nixos-fw -p ${proto} -s ${net} ${ports} -j nixos-fw-accept";
      }) allow.protocols
    ) allow.networks;

  specs = lib.concatMap ruleSpecs (lib.attrValues config.my.firewall-allow);
in
{
  options.my.firewall-allow = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          networks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Source networks (CIDR, IPv4 or IPv6) allowed to reach `ports`.";
          };
          ports = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.port;
            description = "Destination ports to accept from `networks`.";
          };
          protocols = lib.mkOption {
            type = lib.types.nonEmptyListOf (
              lib.types.enum [
                "tcp"
                "udp"
              ]
            );
            default = [ "tcp" ];
            description = "Transport protocols to accept on `ports`.";
          };
        };
      }
    );
    default = { };
    description = "Named source-restricted accepts, one entry per service.";
  };

  config.networking.firewall = lib.mkIf (specs != [ ]) {
    extraCommands = lib.concatMapStringsSep "\n" (s: "${s.tool} -I ${s.rule}") specs;
    extraStopCommands = lib.concatMapStringsSep "\n" (s: "${s.tool} -D ${s.rule} || true") specs;
  };
}
