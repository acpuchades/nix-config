#!/usr/bin/env bash
# Acceptance tests for the ProtonVPN egress described in modules/protonvpn.
#
# Run as root on the homeserver:  sudo ./scripts/verify-protonvpn.sh
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
CLIENT_IF=proton-client
P2P_IF=proton-p2p
CLIENT_TABLE=42
TUNNELED_SRC=10.0.1.1          # wg0's address inside the tunneled prefix
VETH_NS_ADDR=10.200.0.2
RPC_PORT=9091
GW=10.2.0.1
DNS_MARK=66
IP_ECHO=https://ifconfig.co
IP_ECHO_JSON=https://ifconfig.co/json

RUN_DISRUPTIVE=1
[[ "${1:-}" == "--safe" ]] && RUN_DISRUPTIVE=0

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

egress()     { curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null; }
egress_src() { curl -fsS --max-time 15 --interface "$1" "$IP_ECHO" 2>/dev/null; }
egress_ns()  { ip netns exec "$NS" curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null; }

# Proton's ASN org, when the echo service reports it. Falls back to "differs
# from the ISP address", which is weaker but never wrong.
is_proton() {
  local addr="$1" json org
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
  if ip route get 1.1.1.1 2>/dev/null | grep -qv "$CLIENT_IF"; then
    ok "host default route does not use $CLIENT_IF"
  else
    no "host default route goes through the tunnel — main table was modified"
  fi
else
  no "host has no egress at all"
fi

if ip route show table main | grep -qE "^default .* dev ($CLIENT_IF|$P2P_IF)"; then
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
  if is_proton "$CLIENT_IP" "$TUNNELED_SRC"; then
    ok "tunneled egress is a Proton address (by ASN)"
  elif [[ $? -eq 2 ]]; then
    sk "ASN lookup unavailable; distinctness checked only"
  else
    no "tunneled egress is not a Proton address"
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

PORT=$(ip netns exec "$NS" natpmpc -a 1 0 tcp 60 -g "$GW" 2>/dev/null \
        | sed -n 's/.*Mapped public port \([0-9]\{1,\}\).*/\1/p' | head -1)
LISTEN=$(ip netns exec "$NS" transmission-remote "$VETH_NS_ADDR:$RPC_PORT" -si 2>/dev/null \
        | sed -n 's/.*Listenport: *\([0-9]\{1,\}\).*/\1/p' | head -1)
note "NAT-PMP forwarded port: ${PORT:-<no reply>}"
note "transmission peer-port: ${LISTEN:-<unknown>}"
if [[ -z "$PORT" ]]; then
  no "Proton did not answer NAT-PMP (is this server P2P-flagged with NAT-PMP enabled?)"
elif [[ "$PORT" == "$LISTEN" ]]; then
  ok "forwarded port matches Transmission's peer-port"
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
  ip netns exec "$NS" ip link set "$P2P_IF" up
  sleep 3
  if ip netns exec "$NS" curl -fsS --max-time 20 "$IP_ECHO" >/dev/null 2>&1; then
    ok "namespace recovered after the tunnel came back"
  else
    no "namespace did NOT recover — check protonvpn-$P2P_IF.service"
  fi
else
  sk "disruptive test skipped (--safe)"
fi

###############################################################################
hdr "6. proton-client down blackholes tunneled sources (fail closed)"
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
  ip link set "$CLIENT_IF" up
  sleep 3
  systemctl start "protonvpn-route-$CLIENT_IF.service" >/dev/null 2>&1 || true
  if curl -fsS --max-time 20 --interface "$TUNNELED_SRC" "$IP_ECHO" >/dev/null 2>&1; then
    ok "tunneled egress recovered"
  else
    no "tunneled egress did NOT recover — check protonvpn-route-$CLIENT_IF.service"
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

if iptables -t mangle -S OUTPUT | grep -q "dnscrypt-proxy.service.*--set-xmark 0x$(printf '%x' $DNS_MARK)"; then
  ok "resolver upstream is marked for the tunnel"
else
  sk "resolver upstream marking rule not found (routeUpstreamThroughClient off?)"
fi
if ip rule show | grep -q "fwmark 0x$(printf '%x' $DNS_MARK).*lookup $CLIENT_TABLE"; then
  ok "fwmark rule routes marked traffic into table $CLIENT_TABLE"
else
  sk "no fwmark rule for the resolver"
fi

# Prove the mark -> reroute path actually works on this kernel, which is the
# one assumption the resolver routing rests on. Marking by uid here is only a
# stand-in for the cgroup match; what is being tested is the reroute.
if (( RUN_DISRUPTIVE )); then
  TESTUID=$(id -u nobody 2>/dev/null || echo 65534)
  iptables -t mangle -I OUTPUT -m owner --uid-owner "$TESTUID" -j MARK --set-mark "$DNS_MARK"
  RESTORE+=("iptables -t mangle -D OUTPUT -m owner --uid-owner $TESTUID -j MARK --set-mark $DNS_MARK")
  MARKED_IP=$(setpriv --reuid="$TESTUID" --regid=65534 --clear-groups \
                curl -fsS --max-time 15 "$IP_ECHO" 2>/dev/null || true)
  note "marked-process egress: ${MARKED_IP:-<none>}"
  if [[ -z "$MARKED_IP" ]]; then
    no "marked traffic had no egress at all"
  elif [[ "$MARKED_IP" == "$HOST_IP" ]]; then
    no "marked traffic left via the ISP — the post-mangle reroute is NOT happening"
    note "set my.protonvpn.resolver.routeUpstreamThroughClient = false"
  else
    ok "marked traffic is rerouted into the tunnel (reroute works on this kernel)"
  fi
else
  sk "mark/reroute proof skipped (--safe)"
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
for dst in 192.168.2.1 192.168.2.2 10.0.0.2; do
  DEV=$(ip route get "$dst" from "$TUNNELED_SRC" iif wg0 2>/dev/null | grep -o 'dev [^ ]*' | head -1 | cut -d' ' -f2)
  if [[ "$DEV" == "$CLIENT_IF" ]]; then
    no "traffic from a tunneled source to $dst would go through the tunnel"
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
