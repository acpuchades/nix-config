# protonvpn egress — working log

Append-only. Survives reboots, so the trail is not lost when DNS dies and the
box has to be restarted. Newest entry at the bottom.

---

## 2026-09-19 — "DNS not working again" (2nd reboot)

### How the host got here

Boot -1 (00:39 → 01:17) started **without** protonvpn: activation removed the
netdev symlinks at 00:39:14. At **00:48:57** a `nixos-rebuild` activated
protonvpn. At 01:17 the box was rebooted and came back on generation 576, which
has no protonvpn in it — so the protonvpn activation was a `test`-style switch
with no bootloader entry. **That is the rollback: a plain reboot always returns
to a known-good, protonvpn-free system.** Useful, keep it.

### Root cause #1 — the table-42 default route was never installed (CONFIRMED)

`protonvpn-route-proton-client.service` carried:

```nix
requires = [ "wireguard-proton-client.service" ];
partOf   = [ "wireguard-proton-client.service" ];
```

That unit **does not exist on this host**. Confirmed three ways:

* `networking.wireguard.useNetworkd = true` (it follows `networking.useNetworkd`,
  set in `machines/homeserver/networking.nix:10`).
* In nixpkgs' `wireguard.nix`, the units are behind `mkIf (!cfg.useNetworkd)`
  (L736/L744) — so under networkd there is no `wireguard-<iface>.service` at all,
  only `40-<iface>.netdev` / `.network`.
* Evaluating the real config: `netdevs = [ "40-proton-client" "40-wg0" ]`,
  `wgServices = [ ]`.

And the kernel said it out loud in the journal:

```
sep 19 00:52:00 systemctl[23514]: Failed to restart wireguard-proton-client.service:
                                  Unit wireguard-proton-client.service not found.
```

A `Requires=` on a nonexistent unit means the route service can never start, so
table 42 contained nothing but its `blackhole default metric 1000`.

**Effects, both observed:**

* Watchdog: `curl: (7) Failed to connect to 1.1.1.1:443 after 0 ms` — "0 ms" is
  the blackhole answering instantly, not a network timeout.
* Resolver: `[ERROR] write udp 192.168.2.2:38420->5.134.118.198:443:
  write: invalid argument` at 00:49:00 — EINVAL is what a blackhole route returns
  to `sendto()`. **DNS died within 3 seconds of protonvpn activating**, and stayed
  dead: 351 TIMEOUT lines over the rest of the boot.

At **00:52:52** alex ran `sudo ip route replace default dev proton-client table 42`
by hand. From 00:53:00 on, **every watchdog probe passed**. So the tunnel itself
is fine — the only thing missing was that route.

### Root cause #2 — DNS still failed with the route in place (OPEN)

After the manual route, and across two clean dnscrypt restarts (01:05:20,
01:16:58), upstream DNS still timed out:

```
read udp 192.168.2.2:53185->149.112.112.10:8443: i/o timeout
```

Note it is now a **timeout**, not EINVAL — the packet leaves, no reply comes back.
And the source is still **192.168.2.2**, never 10.2.0.2.

That is expected mechanically: the mark is set in `mangle OUTPUT`, which runs
*after* source-address selection, and the post-mangle reroute
(`ip_route_me_harder`) changes the output route but **not** the already-chosen
source address. The module compensates with
`-t nat -A POSTROUTING -o proton-client -m mark --mark 66 -j MASQUERADE`.
Why that is not taking effect is the open question.

Ruled out so far:
* The mark rule installed fine — no "FAILED to install the DNS mark rule" in the journal.
* firewall.service reloaded at 00:48:59, so the MASQUERADE rule was (re)applied.
  (The four "Bad rule" lines are the harmless `-D` deletes of not-yet-existing rules.)
* `ksChain` is hooked into **FORWARD only**, so it cannot touch host-local DNS.
* `checkReversePath = "loose"`.
* The netdev is correct — no `RouteTable=`, so `allowedIPsAsRoutes = false` is
  honoured and networkd installs no routes. Property #1 of the module holds.

Contrast worth keeping: the watchdog's `curl --interface 10.2.0.2` **works**. It
differs from the DNS path in exactly one way — it owns a correct source address
from the start (rule 1003) and needs no NAT. That points the finger squarely at
the mark+MASQUERADE path, not at the tunnel.

### Design note surfaced by this

The module's comment on the DNS mark says a failure there should cost *privacy*,
not *resolution* ("failing the unit costs name resolution for the entire LAN and
every VPN peer"). But the blackhole in table 42 makes the steered DNS path fail
**closed**, which is precisely what took the LAN's DNS down at 00:49:00. The
stated intent and the actual behaviour disagree. Worth resolving deliberately.

### Fix applied for #1

`protonvpn-route-proton-client.service` is now anchored to the interface's
**`.device` unit** instead of a nonexistent wireguard service:

```nix
wantedBy = [ "sys-subsystem-net-devices-proton\\x2dclient.device" ];
after    = [ "sys-subsystem-net-devices-proton\\x2dclient.device" "protonvpn-policy.service" ];
bindsTo  = [ "sys-subsystem-net-devices-proton\\x2dclient.device" ];
```

Verified the anchor is real, not theoretical — wg0 (same networkd wireguard
path) already has `sys-subsystem-net-devices-wg0.device` **loaded active plugged**
on the running system. The device unit is also a strictly better trigger than the
old `multi-user.target`: route installed when the link appears, removed when it
goes, reinstalled when it returns.

The watchdog's escalation had the same dead reference (`systemctl restart
wireguard-<iface>.service`, the line that logged NOTINSTALLED above). It now runs
`networkctl reconfigure proton-client` for the client tunnel; the P2P tunnel is a
real hand-built unit and keeps its `systemctl restart`.

### Staged rollout, so #2 cannot cause a third outage

`resolver.routeUpstreamThroughClient = false` is set **temporarily** in
`machines/homeserver/default.nix`. That leaves upstream DNS on the ISP path
(still encrypted to no-log resolvers — what is lost is source-address hiding)
while the tunnel itself is proven. Revert it once #2 is understood.

Activate with `test`, never `switch`, until this is settled — `test` writes no
bootloader entry, so a reboot remains a guaranteed rollback to generation 576.

### Next evidence to collect once up (answers #2 in one shot)

```sh
ip rule show                                          # 1002 fwmark, 1003 src present?
ip route show table 42                                # default dev proton-client, ABOVE the blackhole?
sudo iptables -t nat -L POSTROUTING -v -n --line-numbers   # does the mark-66 MASQUERADE have nonzero counters?
sudo iptables -t mangle -L OUTPUT -v -n               # is the cgroup mark rule matching packets at all?
```

The decisive question is the **MASQUERADE packet counter**. Zero means the DNS
packet entered the tunnel still carrying src 192.168.2.2 (an RFC1918 address
Proton will drop — which would explain the timeout exactly). Nonzero means the
NAT fired and the problem is on the reply path instead.

### VERIFIED LIVE (01:28, after `nixos-rebuild test`)

Fix #1 works. The route is now installed **by the unit**, not by hand:

```
$ systemctl is-active protonvpn-route-proton-client.service   → active (Result=success, 01:28:22)
$ ip route show table 42
default dev proton-client scope link          ← metric 0, wins
blackhole default metric 1000                 ← still there as the fail-closed backstop
```

Rules, tunnel and egress all correct:

```
1000: from 10.0.1.0/24 to {192.168.2.0/24,10.0.0.0/24,10.0.1.0/24} lookup main
1001: from 10.0.1.0/24 lookup 42
1003: from 10.2.0.2      lookup 42
proton-client  UNKNOWN  10.2.0.2/32
```

* Watchdog: passing silently every 60s (no probe-failure lines at all).
* **ISP exit `207.188.163.51` vs tunnel exit `130.195.250.74`** — a Proton
  address in the same /24 as the endpoint. The tunnel really carries traffic.
* DNS: **zero** TIMEOUT/ERROR lines this boot, all three resolvers live.
* P2P side up too: `protonvpn-proton-p2p`, `protonvpn-veth-torrent`,
  transmission active, NAT-PMP got port 51073 and pushed it to transmission.

### #2 — the mechanism is structurally wrong, not merely misconfigured

`dnscrypt-proxy.service` is `DynamicUser=yes`, running as **uid 62582** — allocated
at runtime from systemd's 61184–65519 range, so it is not stable and cannot be
named at eval time. That is why the module marks by cgroup.

But marking in `mangle OUTPUT` is *inherently too late*: `connect()` has already
performed the route lookup with mark 0, picked `192.168.2.2` from `main`, and
bound the socket to it. The post-mangle reroute changes the **route**, never the
**source**. So the steered DNS path can only ever work by SNAT band-aid, and it
fails closed into the blackhole when the tunnel drops — the opposite of what the
module's own docs say should happen for DNS.

Contrast: `curl --interface 10.2.0.2` works perfectly, because it owns a correct
source address from the start and matches rule 1003. That is the path to copy.

---

## 2026-09-19 — #2 fixed: uid steering + a table that degrades

Two decisions, both taken deliberately rather than patched around.

### Mechanism: uid rule, not firewall mark

The mark approach was not misconfigured, it was **unfixable as designed**.
`-j MARK` in `mangle OUTPUT` runs after `connect()` has already done the route
lookup, chosen `192.168.2.2` from `main` and bound the socket to it. The
post-mangle reroute changes the *route* and never the *source*, so the query
reached Proton carrying an RFC1918 address — dropped silently, which is exactly
the `i/o timeout` with source `192.168.2.2` we saw. The MASQUERADE existed only
to paper over a source that was wrong by construction.

A **uid rule is consulted by that first lookup**, so source selection lands on
10.2.0.2 from the start — the same path `curl --interface 10.2.0.2` already
proves works. Gone: the cgroup match, the mangle rule, the mark, the SNAT, and
the ExecStartPost/ExecStopPost pair on the resolver.

The cost is dropping `DynamicUser` for dnscrypt-proxy, since an `ip rule` can
match a uid but knows nothing of cgroups. Every other sandboxing directive
nixpkgs sets is untouched. **No uid is written down** — NixOS allocates it and
the scripts read it back with `id -u`, so there is no number to collide with the
host's other services (which allocate descending from 999) or to drift.

### Failure mode: degrade, don't die

Upstream DNS now uses **table 44**, holding only the tunnel default and **no
blackhole**. When the interface goes the kernel drops that route with it, the
table empties, rule 1002 matches nothing, and the lookup falls through to `main`
— queries leave over the ISP, still encrypted to the same no-log resolvers.

Table 42 keeps its blackhole unchanged; that fail-closed guarantee is for **peer**
traffic, and sharing it with the resolver is what took the LAN's DNS down twice.
This is what the module's docs already claimed ("fallback means degraded, not
leaking") — now the code agrees with them.

Hardening worth keeping: the uid lookup in `protonvpn-policy` is **non-fatal**.
The blackhole and peer steering rules are installed before it, and letting a
missing uid abort the unit would drop the fail-closed guarantees to protect a
privacy nicety.

### Notes for next time

* `systemd.sysusers.enable = false` here, so `users.users` is realised into
  `/etc/passwd` by the activation script before any unit starts. There is no
  unit to order against — an `After=systemd-sysusers.service` would be a
  no-op that reads like a guarantee. Don't add one back.
* Loopback is unaffected: rule 0 (`local`) is consulted before 1002, so
  dnscrypt's replies to AdGuard on 127.0.0.1:5300 never reach the uid rule.
* Flipping DynamicUser off makes systemd migrate `StateDirectory` from
  `/var/lib/private/dnscrypt-proxy` back to `/var/lib/dnscrypt-proxy`. If that
  ever fails, the only loss is the cached resolver lists; dnscrypt re-fetches
  them through its own bootstrap resolvers. Not fatal, but check
  `journalctl -u dnscrypt-proxy` for "loaded" lines after the first switch.
* `verify-protonvpn.sh` §8 was rewritten. The old disruptive check marked a
  `nobody`-owned curl by uid — a *stand-in* that tested the reroute, so it could
  pass while the real resolver path failed. It now runs curl **as the resolver's
  own uid**, which is the actual path, and asserts table 44 has no blackhole.

---

## 2026-09-19 — first verify run: 8 failures, one real bug behind most of them

`sudo ./scripts/verify-protonvpn.sh` after the uid-steering switch. The uid rule
itself was fine — `PASS resolver uid 969 is steered into table 44` — but §6 tore
the client tunnel down and **it never came back**, so §8, §11 and the rest ran
against a dead tunnel.

### The real bug: a .device unit tracks EXISTENCE, not UP

`ip link set proton-client down` flushes the routes through that device, but the
interface never leaves sysfs — so `sys-subsystem-net-devices-proton\x2dclient.device`
**stayed active**, `BindsTo` never fired, and the oneshot stayed `active` with
`RemainAfterExit=true`. The script's `systemctl start protonvpn-route-…` was
therefore a no-op on an already-started unit. Tunnel back, routes gone,
`ip route show table 42` left holding nothing but its blackhole.

So the oneshot was wrong twice, for two different reasons: first anchored to a
unit that does not exist under networkd (never ran at all), then anchored to a
device unit that cannot observe the event that matters.

**Fix: networkd owns the routes.** It already owns the interface and re-applies
`[Route]` on carrier gain, which is precisely the event the oneshot was blind to.
The unit is deleted. Generated `40-proton-client.network`:

```ini
[Route]
Destination=0.0.0.0/0
Scope=link
Table=42

[Route]
Destination=0.0.0.0/0
PreferredSource=10.2.0.2
Scope=link
Table=44
```

Both pin `Table=`, so neither can touch `main` — still consistent with
`allowedIPsAsRoutes = false`, which exists to stop WireGuard installing 0.0.0.0/0
into `main`. `PreferredSource` pins the source so the uid rule's whole purpose
cannot be undone by a second address appearing.

Note the degrade path worked exactly as designed even in the failure: with the
tunnel dead, table 44 was empty and §8 reported `resolver-uid egress:
207.188.163.51` — the ISP, not a timeout. Under the old shared-table design that
same state was a host-wide DNS outage.

### Test defects found (the system was fine; the checks were not)

* **§2 "not a Proton address"** — `130.195.250.74` is in the *same /24* as the
  configured endpoint `130.195.250.66`. The check asserted ASN org contains
  "Proton", but Proton leases capacity, so a healthy exit reports the lessor
  (M247, Datacamp, …). Now the endpoint's /24 is the primary signal and ASN is
  only a fallback.
* **§3 NAT-PMP "<no reply>"** — the script issued its *own* `natpmpc` request
  while `protonvpn-natpmp` renews the same tcp mapping every 45s; the collision
  went unanswered and read as "Proton does not do NAT-PMP", while the service
  had in fact mapped port 51073 minutes earlier. Now reads the port from the
  service's journal, with a live probe only as fallback.
* **§5 p2p "did NOT recover"** — recovery there is *not* `ip link set up`: the
  namespace has no networkd and nothing reinstates the flushed default route.
  In production the watchdog restarts the unit. The test now does that, and
  polls up to 30s instead of a single try after `sleep 3`.
* **§10 all SKIP** — `ip route get <dst> from 10.0.1.1 iif wg0` uses wg0's *own*
  address as an input source, which the kernel rejects with `Invalid argument`.
  All three checks had been silently skipping. Now uses a peer address
  (10.0.1.2) and actually runs.
* **§6/§5 timing** — added a `wait_for` helper; a single try after a fixed sleep
  turns a slow-but-working recovery into a red FAIL.

### Unrelated, still open: cloud.acpuchades.com returns 503

**Not a protonvpn problem and not caused by any of this.** Traced it out:
Caddy → nginx → php-fpm, and `curl -H 'Host: cloud.acpuchades.com'
http://127.0.0.1:8080/` returns **503 straight from nginx**, with nginx and
phpfpm-nextcloud both active and the socket permissions correct. So the 503
originates inside Nextcloud/PHP (maintenance mode or a PHP error), not in the
web tier. Needs its own look.

Worth noting: CLAUDE.md claims "web-server (Caddy + ACME — NOT nginx; there is
no `services.nginx` anywhere in this repo)". That is **wrong** —
`modules/cloud-suite/default.nix:423` enables `services.nginx`, and Nextcloud is
deliberately served Caddy → nginx → php-fpm. The file needs correcting.

---

## 2026-09-19 — GREEN. 26 passed, 2 failed, 0 skipped

Everything this module exists to do is now verified end to end:

```
2.  tunneled egress 130.195.250.74   namespace egress 130.195.250.107
    PASS browsing and BitTorrent do NOT share an exit IP
5.  PASS namespace has no path to the internet with the tunnel down
    PASS namespace recovered after the tunnel came back
6.  PASS tunneled source has no egress with the tunnel down
    PASS tunneled egress recovered on its own (networkd re-applied the routes)
8.  PASS resolver uid 969 is steered into table 44
    PASS table 44 routes via proton-client with no blackhole (degrades to ISP)
    PASS resolver-uid traffic leaves via the tunnel (130.195.250.74)
10. PASS all three LAN/inter-client destinations use main, not the tunnel
11. PASS 10 MB TCP transfer + QUIC (no PMTU black hole)
```

§6 is the one that matters most: **recovered on its own**, with no unit to poke.
That is the whole point of moving the routes into networkd. And §8 closes out the
DNS saga — the resolver's queries leave with a Proton source address, by uid, and
the table they use carries no blackhole to strand them if the tunnel dies.

### Remaining

* **§3 `transmission peer-port: <unknown>`** — a READ-side defect in the check,
  not a forwarding failure. `protonvpn-natpmp` logs only *after*
  `transmission-remote --port` succeeds, and it logged (51073), so RPC is
  reachable and writable and the port was applied. The field's spelling has
  moved between Transmission versions; the check now matches loosely, keeps the
  raw output, and reports an unreadable port as a SKIP that says so rather than
  as "the renewal service is not applying it".
* **§9 cloud.acpuchades.com 503** — unrelated to this module, still open. nginx
  answers 503 directly on 127.0.0.1:8080, so it originates inside Nextcloud/PHP.
  CLAUDE.md has been corrected: it claimed no `services.nginx` exists here, when
  cloud-suite enables it on loopback for NextCloud's PHP-FPM.
