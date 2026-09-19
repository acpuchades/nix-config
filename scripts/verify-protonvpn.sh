#!/usr/bin/env bash
# Acceptance tests for the ProtonVPN egress described in modules/protonvpn.
#
# Run as root on the homeserver:  sudo ./scripts/verify-protonvpn.sh
#
# These tests are PER CLIENT TUNNEL. With several exits configured (es, in, us
# …) one run proves one of them; pass --tunnel to pick, or run it once per
# tunnel. Without the flag it takes the first name alphabetically.
#
#   sudo ./scripts/verify-protonvpn.sh --tunnel us
#   sudo ./scripts/verify-protonvpn.sh --tunnel in --safe
#
# The P2P tunnel and the resolver checks are not per-tunnel and run every time.
#
# Tests 5, 6 and 8 are DISRUPTIVE — they take a tunnel administratively down, or
# add a temporary firewall rule, to prove the failure modes behave. Everything is
# restored by an EXIT trap, including on interrupt. Pass --safe to skip them.
#
# The point of the disruptive ones is that a kill switch nobody has ever seen
# fire is a belief, not a control. They are the only tests here that prove the
# thing the whole design exists for.

set -uo pipefail

NS=torrent
P2P_IF=proton-p2p
VETH_NS_ADDR=10.200.0.2
RPC_PORT=9091
GW=10.2.0.1
DNS_TABLE=44                   # resolver upstream table (no blackhole: degrades to ISP)
RESOLVER_USER=dnscrypt-proxy
IP_ECHO=https://ifconfig.co
IP_ECHO_JSON=https://ifconfig.co/json

CLIENT_TUNNEL=""
RUN_DISRUPTIVE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --safe)   RUN_DISRUPTIVE=0; shift ;;
    --tunnel) CLIENT_TUNNEL="${2:-}"; [[ -n "$CLIENT_TUNNEL" ]] || { echo "--tunnel needs a name" >&2; exit 2; }; shift 2 ;;
    *)        echo "usage: $0 [--safe] [--tunnel <name>]" >&2; exit 2 ;;
  esac
done

# Everything about the tunnel under test is READ FROM THE CONFIGURATION rather
# than hardcoded. With one tunnel that was merely tidy; with several it is the
# difference between testing the tunnel you named and testing whichever one the
# constants happened to describe.
CFG=".#nixosConfigurations.homeserver.config.my.protonvpn"
cfgs() { nix eval --raw "$CFG.$1" 2>/dev/null; }          # string-valued
cfgn() { nix eval "$CFG.$1" 2>/dev/null; }                # number-valued

if [[ -z "$CLIENT_TUNNEL" ]]; then
  CLIENT_TUNNEL=$(nix eval --raw --apply 'x: builtins.head (builtins.attrNames x)' \
    "$CFG.clientTunnels" 2>/dev/null)
fi
[[ -n "$CLIENT_TUNNEL" ]] || { echo "no client tunnels configured" >&2; exit 2; }

T="clientTunnels.\"$CLIENT_TUNNEL\""
CLIENT_IF=$(cfgs "$T.interface")
CLIENT_TABLE=$(cfgn "$T.table")
KS_CHAIN="protonvpn-ks-$CLIENT_TUNNEL"
GATEWAY_CIDR=$(cfgs "$T.gateway")
TUNNELED_SRC=${GATEWAY_CIDR%%/*}   # wg0's address inside this tunnel's prefix
TUNNELED_PEER="${TUNNELED_SRC%.*}.2"  # a PEER address in it, for input-route simulation
[[ -n "$CLIENT_IF" && -n "$CLIENT_TABLE" && -n "$TUNNELED_SRC" ]] || {
  echo "could not read tunnel '$CLIENT_TUNNEL' from the flake" >&2; exit 2; }

# The configured Proton endpoints. An exit address in the same /24 as the peer
# we tunnel to is Proton's by construction — a far better test than ASN org.
CLIENT_ENDPOINT=$(cfgs "$T.peer.endpoint" | cut -d: -f1)
P2P_ENDPOINT=$(cfgs "p2pTunnel.peer.endpoint" | cut -d: -f1)

# EVERY client tunnel's interface, not just the one under test. The checks that
# assert the main table is untouched have to see all of them: a default route
# installed by proton-us is just as wrong when the run happens to be testing
# proton-es, and keying those on $CLIENT_IF quietly narrowed them to a third of
# what they used to cover.
ALL_CLIENT_IFS=$(nix eval --raw --apply \
  'x: builtins.concatStringsSep " " (map (t: t.interface) (builtins.attrValues x))' \
  "$CFG.clientTunnels" 2>/dev/null)
PROTON_IF_RE=$(printf '%s %s' "$ALL_CLIENT_IFS" "$P2P_IF" | tr -s ' ' '|')

# The resolver uses ONE tunnel regardless of which one is under test — it is a
# single host-wide service, so `resolver.viaTunnel` names it and nothing about
# --tunnel changes that.
RESOLVER_TUNNEL=$(nix eval --json "$CFG.resolver.viaTunnel" 2>/dev/null | tr -d '"')
[[ "$RESOLVER_TUNNEL" == "null" ]] && RESOLVER_TUNNEL=""
RESOLVER_IF=""
[[ -n "$RESOLVER_TUNNEL" ]] && \
  RESOLVER_IF=$(cfgs "clientTunnels.\"$RESOLVER_TUNNEL\".interface")

printf '\033[1mTesting client tunnel: %s (%s, table %s, prefix via %s)\033[0m\n' \
  "$CLIENT_TUNNEL" "$CLIENT_IF" "$CLIENT_TABLE" "$TUNNELED_SRC"

pass=0; fail=0; skip=0
RESTORE=()

cleanup() {
  for (( i=${#RESTORE[@]}-1 ; i>=0 ; i-- )); do
    eval "${RESTORE[i]}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
sk()   { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; skip=$((skip+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '        %s\n' "$1"; }

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 2; }

# Poll a command until it succeeds, up to N seconds. Recovery is not
# instantaneous and asserting it with a single try after a fixed sleep turns a
# slow-but-working path into a red FAIL — which is exactly what it did before.
wait_for() {
  local secs="$1"; shift
  local i
  for (( i=0; i<secs; i++ )); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

egress()     { curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null; }
egress_src() { curl -fsS --max-time 15 --interface "$1" "$IP_ECHO" 2>/dev/null; }
egress_ns()  { ip netns exec "$NS" curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null; }

# Is this egress address one of Proton's?
#
# The ASN org is NOT a reliable test and must not be the deciding one: Proton
# leases capacity from hosting providers, so a perfectly good Proton exit
# reports the lessor's name (M247, Datacamp, …) and never the word "Proton".
# That is why this check used to FAIL on 130.195.250.74 — an address in the
# very same /24 as the configured endpoint.
#
# The reliable signal is the configured endpoint itself: an exit in the same
# /24 as the peer we are tunnelling to is Proton's by construction. ASN is kept
# only as a second chance for exits that sit in a different block.
is_proton() {
  local addr="$1" json org
  local endpoint_net="${3:-}"
  if [[ -n "$endpoint_net" && "${addr%.*}" == "${endpoint_net%.*}" ]]; then
    return 0
  fi
  json=$(curl -fsS --max-time 15 "$IP_ECHO_JSON" --interface "${2:-}" 2>/dev/null) || return 2
  org=$(printf '%s' "$json" | grep -o '"asn_org"[^,]*' | cut -d'"' -f4)
  [[ -z "$org" ]] && return 2
  printf '%s' "$org" | grep -qi 'proton'
}

###############################################################################
hdr "1. Host egress is unchanged (still the ISP address)"
HOST_IP=$(egress)
if [[ -n "$HOST_IP" ]]; then
  note "host egress: $HOST_IP"
  # Negate the grep rather than grepping for a non-matching LINE: `ip route get`
  # prints a "cache" line after the route, so `grep -v` found it and passed even
  # when the route itself named a tunnel.
  if ip route get 1.1.1.1 2>/dev/null | grep -qE "dev ($PROTON_IF_RE)"; then
    no "host default route goes through a Proton tunnel — main table was modified"
  else
    ok "host default route uses none of: $ALL_CLIENT_IFS $P2P_IF"
  fi
else
  no "host has no egress at all"
fi

if ip route show table main | grep -qE "^default .* dev ($PROTON_IF_RE)"; then
  no "a Proton interface owns the default route in the MAIN table"
else
  ok "main table's default route is untouched"
fi

###############################################################################
hdr "2. A tunneled source egresses from Proton, distinct from Transmission's"
CLIENT_IP=$(egress_src "$TUNNELED_SRC")
NS_IP=$(egress_ns)
note "tunneled-source egress: ${CLIENT_IP:-<none>}"
note "namespace egress:       ${NS_IP:-<none>}"

if [[ -z "$CLIENT_IP" ]]; then
  no "tunneled source has no egress ($CLIENT_IF down, or the policy rule is missing)"
elif [[ "$CLIENT_IP" == "$HOST_IP" ]]; then
  no "tunneled source left via the ISP — it is NOT being steered"
else
  ok "tunneled source egresses somewhere other than the ISP"
  if is_proton "$CLIENT_IP" "$TUNNELED_SRC" "$CLIENT_ENDPOINT"; then
    ok "tunneled egress is a Proton address"
  elif [[ $? -eq 2 ]]; then
    sk "could not corroborate the exit as Proton's; distinctness checked only"
  else
    no "tunneled egress is neither in the endpoint's /24 nor a Proton ASN"
  fi
fi

if [[ -n "$CLIENT_IP" && -n "$NS_IP" ]]; then
  if [[ "$CLIENT_IP" != "$NS_IP" ]]; then
    ok "browsing and BitTorrent do NOT share an exit IP"
  else
    no "both tunnels exit on the SAME address — the separation has collapsed"
  fi
fi

###############################################################################
hdr "3. Transmission namespace egress and forwarded port"
if [[ -z "$NS_IP" ]]; then
  no "namespace has no egress"
elif [[ "$NS_IP" == "$HOST_IP" ]]; then
  no "namespace egressed via the ISP — isolation has failed"
else
  ok "namespace egresses via the tunnel, not the ISP"
fi

# Read the port the RENEWAL SERVICE holds, rather than issuing a competing
# NAT-PMP request of our own. protonvpn-natpmp renews the same tcp mapping every
# 45s; a second client asking for the same thing at the same moment is liable to
# go unanswered, and that silence then reads as "Proton does not do NAT-PMP" —
# which is how this check failed while the service itself was working fine and
# had a port mapped. The service logs only on change, so its last logged port is
# the current one for as long as the unit is up.
PORT=$(journalctl -u protonvpn-natpmp --no-pager 2>/dev/null \
        | sed -n 's/.*forwarded port changed .* -> \([0-9]\{1,\}\),.*/\1/p' | tail -1)
PORT_SRC="renewal service"
if [[ -z "$PORT" ]]; then
  PORT=$(ip netns exec "$NS" natpmpc -a 1 0 tcp 60 -g "$GW" 2>/dev/null \
          | sed -n 's/.*Mapped public port \([0-9]\{1,\}\).*/\1/p' | head -1)
  PORT_SRC="live probe"
fi
# Read Transmission's peer-port back. Keep the raw output: the field's spelling
# has moved between Transmission versions ("Listenport", "Peer listening port"),
# and swallowing a parse miss made a healthy daemon look like the renewal
# service was not applying the port at all.
SI_OUT=$(ip netns exec "$NS" transmission-remote "$VETH_NS_ADDR:$RPC_PORT" -si 2>&1)
SI_RC=$?
LISTEN=$(printf '%s\n' "$SI_OUT" \
        | grep -iE 'listen[ -]?port|peer listening port' \
        | grep -oE '[0-9]{2,5}' | head -1)
note "NAT-PMP forwarded port: ${PORT:-<no reply>} (via $PORT_SRC)"
note "transmission peer-port: ${LISTEN:-<unknown>}"
if ! systemctl is-active --quiet protonvpn-natpmp.service; then
  no "protonvpn-natpmp.service is not running — the mapping will expire"
elif [[ -z "$PORT" ]]; then
  no "no forwarded port from either the service or a probe (is this server P2P-flagged with NAT-PMP enabled?)"
elif [[ "$PORT" == "$LISTEN" ]]; then
  ok "forwarded port $PORT matches Transmission's peer-port"
elif [[ -z "$LISTEN" ]]; then
  # Distinguish "cannot read it" from "it disagrees". The renewal service logs
  # only after transmission-remote --port succeeds, so a mapped port that was
  # pushed is evidence RPC works and this is a read-side problem, not a
  # forwarding one.
  sk "could not read Transmission's peer-port (rc=$SI_RC) — port $PORT was mapped and pushed"
  note "transmission-remote -si said: $(printf '%s' "$SI_OUT" | head -3 | tr '\n' ' ')"
else
  no "forwarded port $PORT != Transmission's $LISTEN (renewal service not applying it)"
fi

###############################################################################
hdr "4. The namespace has no route other than the tunnel"
ROUTES=$(ip netns exec "$NS" ip route show 2>/dev/null)
note "$(printf '%s' "$ROUTES" | tr '\n' '|')"
UNEXPECTED=$(printf '%s\n' "$ROUTES" | grep -vE "(^default dev $P2P_IF|^10\.200\.0\.0/30 dev |^$)" || true)
if [[ -z "$UNEXPECTED" ]]; then
  ok "only the tunnel default and the RPC veth link route exist"
else
  no "unexpected route(s) in the namespace: $UNEXPECTED"
fi
if printf '%s\n' "$ROUTES" | grep -qE '^default' && \
   ! printf '%s\n' "$ROUTES" | grep -qE "^default dev $P2P_IF"; then
  no "the namespace default route is not the tunnel"
fi

###############################################################################
hdr "5. proton-p2p down blackholes the namespace (fail closed)"
if (( RUN_DISRUPTIVE )); then
  RESTORE+=("ip netns exec $NS ip link set $P2P_IF up")
  ip netns exec "$NS" ip link set "$P2P_IF" down
  sleep 2
  if ip netns exec "$NS" curl -fsS --max-time 8 "$IP_ECHO" >/dev/null 2>&1; then
    no "namespace still reached the internet with the tunnel DOWN — it is leaking"
  else
    ok "namespace has no path to the internet with the tunnel down"
  fi
  # Bringing the link back up is NOT what recovers this tunnel. It lives in a
  # namespace with no networkd, and `ip link set up` cannot reinstate the
  # default route the kernel flushed on down. In production the watchdog
  # notices the dead probe and restarts the unit, which rebuilds the tunnel and
  # its route; that is the path exercised here, rather than a bare link-up that
  # was always going to leave the namespace routeless and read as a failure.
  ip netns exec "$NS" ip link set "$P2P_IF" up
  systemctl restart "protonvpn-$P2P_IF.service" >/dev/null 2>&1 || true
  if wait_for 30 ip netns exec "$NS" curl -fsS --max-time 10 "$IP_ECHO"; then
    ok "namespace recovered after the tunnel came back"
  else
    no "namespace did NOT recover — check protonvpn-$P2P_IF.service"
  fi
else
  sk "disruptive test skipped (--safe)"
fi

###############################################################################
hdr "6. $CLIENT_IF down blackholes tunneled sources (fail closed)"

# The kill switch is PER TUNNEL, and that is the property worth asserting: the
# chain this tunnel's sources jump to may accept traffic leaving via THIS
# interface and nothing else. A chain that accepted another tunnel's interface
# would not leak to the ISP, but it would silently hand the user a different
# exit country than the one they chose — and nothing at runtime would say so.
if iptables -S "$KS_CHAIN" >/dev/null 2>&1; then
  if iptables -S "$KS_CHAIN" | grep -q -- "-o $CLIENT_IF -j ACCEPT"; then
    ok "$KS_CHAIN accepts egress via $CLIENT_IF"
  else
    no "$KS_CHAIN has no ACCEPT for $CLIENT_IF"
  fi
  if [[ $(iptables -S "$KS_CHAIN" | grep -c -- "-j ACCEPT") -eq 1 ]]; then
    ok "$KS_CHAIN accepts exactly one interface"
  else
    no "$KS_CHAIN accepts more than one interface — exits can cross over"
    note "iptables -S $KS_CHAIN"
  fi
  if iptables -S "$KS_CHAIN" | tail -1 | grep -q -- "-j DROP"; then
    ok "$KS_CHAIN terminates in DROP"
  else
    no "$KS_CHAIN does not end in DROP — traffic can fall through to the ISP"
  fi
else
  no "$KS_CHAIN does not exist — this tunnel's sources have no kill switch"
fi

if (( RUN_DISRUPTIVE )); then
  RESTORE+=("ip link set $CLIENT_IF up")
  ip link set "$CLIENT_IF" down
  sleep 2
  if curl -fsS --max-time 8 --interface "$TUNNELED_SRC" "$IP_ECHO" >/dev/null 2>&1; then
    no "tunneled source still egressed with $CLIENT_IF DOWN — it fell back to the ISP"
  else
    ok "tunneled source has no egress with the tunnel down"
  fi
  if ip route show table "$CLIENT_TABLE" | grep -q '^blackhole default'; then
    ok "blackhole default is present in table $CLIENT_TABLE"
  else
    no "no blackhole in table $CLIENT_TABLE — a lookup could fall through to main"
  fi
  # networkd owns this tunnel's table routes, so bringing the link up is all
  # that should be needed — it re-applies [Route] on carrier gain. There is no
  # longer a protonvpn-route-<iface>.service to poke: a oneshot could not see
  # this event at all, because the interface never leaves sysfs when it goes
  # down, so its .device unit stays active and the unit stays "already started".
  ip link set "$CLIENT_IF" up
  if wait_for 30 curl -fsS --max-time 10 --interface "$TUNNELED_SRC" "$IP_ECHO"; then
    ok "tunneled egress recovered on its own (networkd re-applied the routes)"
  else
    no "tunneled egress did NOT recover — check 40-$CLIENT_IF.network's [Route] sections"
    note "ip route show table $CLIENT_TABLE"
  fi
else
  sk "disruptive test skipped (--safe)"
fi

###############################################################################
hdr "7. No IPv6 leak from tunneled sources"
if curl -6 -fsS --max-time 8 --interface "$TUNNELED_SRC" "$IP_ECHO" >/dev/null 2>&1; then
  no "a tunneled source reached the internet over IPv6"
else
  ok "tunneled source has no IPv6 egress"
fi
if ip netns exec "$NS" curl -6 -fsS --max-time 8 "$IP_ECHO" >/dev/null 2>&1; then
  no "the namespace reached the internet over IPv6"
else
  ok "namespace has no IPv6 egress"
fi
V6=$(ip netns exec "$NS" ip -6 addr show scope global 2>/dev/null)
[[ -z "$V6" ]] && ok "namespace has no global IPv6 address" \
               || no "namespace has a global IPv6 address: $V6"

###############################################################################
hdr "8. No DNS leak"
UP=$(nix eval --raw ".#nixosConfigurations.homeserver.config.services.adguardhome.settings.dns.upstream_dns" 2>/dev/null || echo "")
if ip netns exec "$NS" grep -q "$GW" /etc/netns/"$NS"/resolv.conf 2>/dev/null \
   || grep -q "$GW" /etc/netns/"$NS"/resolv.conf 2>/dev/null; then
  ok "namespace resolver is the tunnel's ($GW), not the host's"
else
  no "namespace resolver is not the in-tunnel resolver"
fi
if grep -q '127.0.0.1' /etc/netns/"$NS"/resolv.conf 2>/dev/null; then
  no "namespace resolv.conf still points at loopback (the host's resolver)"
fi

# Upstream DNS is steered BY UID, not by a firewall mark. The rule has to be a
# uidrange one: a mark set in mangle OUTPUT lands after connect() has already
# bound the socket to the WAN address, and the reroute that follows changes the
# route without revisiting the source, so queries reach Proton with an RFC1918
# source and are dropped. Assert the mechanism, not just that something exists.
RESOLVER_UID=$(id -u "$RESOLVER_USER" 2>/dev/null || true)
if [[ -z "$RESOLVER_UID" ]]; then
  sk "$RESOLVER_USER has no stable uid (resolver.viaTunnel unset?)"
elif ip rule show | grep -q "uidrange $RESOLVER_UID-$RESOLVER_UID.*lookup $DNS_TABLE"; then
  ok "resolver uid $RESOLVER_UID is steered into table $DNS_TABLE"
else
  sk "no uidrange rule for $RESOLVER_USER (resolver.viaTunnel unset?)"
fi

# The resolver table must NOT carry a blackhole. That is what makes upstream DNS
# degrade to the ISP when the tunnel dies instead of taking the whole LAN's name
# resolution down with it — which is exactly what a shared table once did.
#
# Keyed on the RESOLVER's tunnel, not on the one under test. These are different
# whenever --tunnel names anything but resolver.viaTunnel, and comparing against
# $CLIENT_IF made this report an empty table on a run against `in` or `us` while
# table $DNS_TABLE was in fact routing perfectly well via the resolver's own.
if [[ -z "$RESOLVER_TUNNEL" ]]; then
  sk "resolver.viaTunnel is unset — upstream DNS is on the ISP path by configuration"
elif ip route show table "$DNS_TABLE" | grep -q blackhole; then
  no "table $DNS_TABLE has a blackhole — a dead tunnel will kill DNS host-wide"
elif ip route show table "$DNS_TABLE" | grep -q "dev $RESOLVER_IF"; then
  ok "table $DNS_TABLE routes via $RESOLVER_IF ($RESOLVER_TUNNEL), no blackhole (degrades to ISP)"
elif [[ -z "$(ip route show table "$DNS_TABLE")" ]]; then
  sk "table $DNS_TABLE is empty — $RESOLVER_IF is down, so upstream DNS has degraded to the ISP"
else
  no "table $DNS_TABLE does not route via $RESOLVER_IF ($RESOLVER_TUNNEL)"
  note "$(ip route show table "$DNS_TABLE")"
fi

# End-to-end proof, run AS THE RESOLVER'S OWN UID. This is the real path now,
# not a stand-in: same uid, same rule, same source selection dnscrypt-proxy gets.
if (( RUN_DISRUPTIVE )) && [[ -n "$RESOLVER_UID" ]]; then
  RESOLVER_GID=$(id -g "$RESOLVER_USER" 2>/dev/null || echo 65534)
  DNS_EGRESS=$(setpriv --reuid="$RESOLVER_UID" --regid="$RESOLVER_GID" --clear-groups \
                 curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null || true)
  note "resolver-uid egress: ${DNS_EGRESS:-<none>}"
  if [[ -z "$DNS_EGRESS" ]]; then
    no "resolver-uid traffic had no egress at all — DNS is failing CLOSED"
    note "table $DNS_TABLE must not contain a blackhole; check the route unit"
  elif [[ "$DNS_EGRESS" == "$HOST_IP" ]]; then
    no "resolver-uid traffic left via the ISP — the uid rule is not steering"
  else
    ok "resolver-uid traffic leaves via the tunnel ($DNS_EGRESS)"
  fi
else
  sk "resolver-uid egress proof skipped (--safe)"
fi

###############################################################################
hdr "9. Inbound services still work"
for h in www.acpuchades.com cloud.acpuchades.com photos.acpuchades.com \
         bitwarden.acpuchades.com analytics.acpuchades.com; do
  code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 15 "https://$h" 2>/dev/null || echo 000)
  if [[ "$code" =~ ^(200|301|302|303|307|308|401|403)$ ]]; then
    ok "$h responds ($code)"
  else
    no "$h did not respond (got ${code})"
  fi
done

RECENT=$(wg show wg0 latest-handshakes 2>/dev/null | awk -v now="$(date +%s)" \
          '$2 != 0 && (now-$2) < 900 {n++} END {print n+0}')
if [[ "${RECENT:-0}" -gt 0 ]]; then
  ok "wg0 has $RECENT peer handshake(s) in the last 15 min (inbound works)"
else
  sk "no recent wg0 handshakes — reconnect a peer to prove inbound"
fi

###############################################################################
hdr "10. LAN and inter-client traffic is not tunneled"
# Simulate a packet arriving from a PEER, not from wg0's own address. With
# `iif`, the kernel does an input lookup and rejects a source that is local to
# this host outright ("Invalid argument") — which silently turned all three of
# these into SKIPs, so the check was never actually running.
for dst in 192.168.2.1 192.168.2.2 10.0.0.2; do
  DEV=$(ip route get "$dst" from "$TUNNELED_PEER" iif wg0 2>/dev/null | grep -o 'dev [^ ]*' | head -1 | cut -d' ' -f2)
  if [[ " $ALL_CLIENT_IFS " == *" $DEV "* ]]; then
    no "traffic from a tunneled source to $dst would go through $DEV"
  elif [[ -n "$DEV" ]]; then
    ok "$dst is reached via $DEV (main table), not the tunnel"
  else
    sk "could not resolve a route to $dst"
  fi
done

###############################################################################
hdr "11. Path MTU sanity from a tunneled source"
if curl -fsS -o /dev/null --max-time 90 --interface "$TUNNELED_SRC" \
     "https://speed.cloudflare.com/__down?bytes=10000000" 2>/dev/null; then
  ok "10 MB TCP transfer completed (no PMTU black hole)"
else
  no "large TCP transfer failed or stalled — suspect MTU/MSS clamping"
fi

if curl --http3 -fsS -o /dev/null --max-time 30 --interface "$TUNNELED_SRC" \
     https://cloudflare-quic.com/ 2>/dev/null; then
  ok "QUIC (HTTP/3) request completed"
elif ! curl --http3 --version >/dev/null 2>&1 && ! curl -V 2>/dev/null | grep -q HTTP3; then
  sk "this curl has no HTTP/3 support; test QUIC from a real client"
else
  no "QUIC request failed — UDP path or MTU problem"
fi

###############################################################################
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 )) || exit 1
