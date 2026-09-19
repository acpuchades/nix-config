# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

**MacBook Pro (nix-darwin):**
```bash
sudo darwin-rebuild switch --flake .#MacBook-Pro-de-Alejandro
```

**Homeserver (NixOS):**
```bash
sudo nixos-rebuild switch --flake .#homeserver
```

**Edit secrets (SOPS-encrypted YAML):**
```bash
sops machines/homeserver/secrets/default.yml
sops users/alex/secrets/default.yml
```

For package changes, verify with `nix build`, not just `nix eval` — eval passes
even when a package fails to compile.

## Architecture Overview

A Nix flakes-based personal system configuration managing two machines:

- **MacBook-Pro-de-Alejandro** (`machines/macbookpro/`) — aarch64-darwin, nix-darwin + home-manager
- **homeserver** (`machines/homeserver/`) — x86_64-linux, NixOS + home-manager

`machines/common.nix` holds the wiring both share: the `modules/*/system.nix`
fragments and the home-manager glue for user alex (curried over flake inputs —
arguments used in `imports` cannot come from `_module.args`).

### Flake Inputs

`nixpkgs` is `nixpkgs-26.05-darwin`; most inputs follow it. The exceptions and
the reasoning for every input live as comments in `flake.nix` — read them there.
The ones that shape the architecture:

- `nixpkgs-unstable` — escape hatch for openclaw and immich on the homeserver only
- `fugazi-web` / `fugazi-web-testing` — the same PRIVATE repo on two branches
  (tarball URLs + netrc, since `github:` ignores netrc); ONE nixosModule imported,
  the testing instance gets only the second input's packages
- `nix-caddy-withplugins` — deliberately does NOT follow nixpkgs (its pinned base
  FOD hash depends on its own toolchain)
- `emacs-overlay`, `sops-nix`, `better-zen`
- `disko` — provisioning metadata only (`disko.enableConfig = false`); the
  runtime filesystem config stays in `hardware-configuration.nix`

### Module System (`modules/`)

Two conventions, split by half:

- **Server modules** (NixOS, homeserver only) are enable-gated:
  `options.my.<module>.enable = lib.mkEnableOption "...";`
  `config = lib.mkIf config.my.<module>.enable { ... };`
- **Dev and Emacs modules** (home-manager, both hosts) have no enable option —
  presence in the `imports` list in `users/alex/default.nix` is the toggle.

Some modules pair `default.nix` (home-manager) with a `system.nix` (system
layer) because home-manager refuses `nixpkgs.overlays` under `useGlobalPkgs`:
`emacs-core` (emacs-overlay + nix-community cachix), `r-dev` (rstats-on-nix
cachix), `prefect-server`. The `system.nix` trio is imported once, in
`machines/common.nix`.

**Emacs modules** (11): `emacs-core`, `emacs-completion`, `emacs-ui`,
`emacs-dev`, `emacs-org`, `emacs-ess`, `emacs-python`, `emacs-nix`,
`emacs-rust`, `emacs-golang`, `emacs-copilot`. ELisp lives in each module's
`config/` (or is generated inline) and lands in `~/.emacs.d/config/`, where
init.el (a bare loader) loads files in FILENAME order — the NN prefix is the
only cross-module ordering there is. Each module owns a reserved prefix band
(new files go inside the owner's band): 00-09 core, 10-19 completion,
20-29 ui, 30-39 dev, 40-49 org, 50-59 copilot, 60+ one language apiece
(60 python, 65 nix, 70 rust, 75 go, 80 ess), 99 personal (users/alex, never
a module). Conventions: the `*-dev` modules own
toolchain binaries (LSP servers, formatters), the `emacs-*` modules own elisp;
eglot-ensure hooks go directly on mode hooks (never inside
`with-eval-after-load 'eglot` — eglot is deferred); packages come only from
Nix (`use-package-always-ensure` is nil, no package-archives).

**Development modules**: `python-dev`, `r-dev`, `rust-dev`, `golang-dev`,
`js-dev`, `c-dev`, `nix-dev`, and `android-dev` (macbookpro only).

**Server modules** (homeserver only), the load-bearing ones:

- `web-server` — Caddy + ACME; Caddy is the public entry point and terminates
  TLS for every host. One deliberate exception: `cloud-suite` enables
  `services.nginx` on 127.0.0.1 to serve NextCloud's PHP-FPM, so that vhost is
  Caddy → nginx → php-fpm. Don't add `services.nginx` anywhere else.
- `cloud-suite` — NextCloud, Collabora, Vaultwarden, Immich
- `protonvpn` — ProtonVPN egress: N prefix-steered client tunnels, one per exit
  country (`my.protonvpn.clientTunnels`) — each owns a `sourcePrefixes` range of
  wg0, its own routing table, kill-switch chain and watchdog, so a peer's exit
  follows from which prefix its address came out of; peers on 10.0.0.0/24 stay
  untunneled on the ISP. Plus a netns-isolated P2P tunnel for Transmission with
  NAT-PMP port renewal. Verify with `scripts/verify-protonvpn.sh --tunnel <name>`.
- `mail-server` — Postfix inbound → eva's Maildir, Mailjet relay outbound,
  rspamd, ACME STARTTLS
- `dns-filtering` — AdGuard Home + DNSCrypt
- `vpn-server` — WireGuard server (peers declared under `my.vpn-server.peers`
  in `machines/homeserver/default.nix`)
- `openclaw` — multi-agent module (`my.openclaw.instances.<name>`), runs eva
- `fugazi-web` — host topology around the upstream flake's module (public
  backtest service, www.fugazitrade.com)

Plus: `backup` (restic → B2), `ntfy-alert`, `transmission-server`,
`media-server`, `postgresql-server`, `prefect-server`, `samba-server`,
`print-server`, `geocoding`, `home-assistant`, `server-stats`, `web-analytics`,
`service-dashboard`, `acme-cloudflare`, `caddy-plugins`, `host-security`
(fail2ban), `ups-monitor`, `tor-bridge`, `push-notifications`,
`wireguard-client` (library module driven by protonvpn).

### User Configuration (`users/alex/`)

Home-manager config shared by both machines; `host` arg ("macbookpro" /
"homeserver") for per-host conditionals, passed via `extraSpecialArgs` so it is
usable in `imports` (where `pkgs` is not). Programs under `programs/`: ghostty,
git (delta), gpg, ssh, tmux, zsh (oh-my-zsh), starship, gh, atuin, eza, fzf,
zoxide, claude-code. Also `agents/eva.nix` (eva's openclaw instance config),
`services.nix`, `sops.nix`, `files/`, `launchd.nix` (darwin).

### Secrets Management

`.sops.yaml` defines age-key recipients by file-path regex. Age-encrypted YAML:

- `machines/homeserver/secrets/default.yml` — WireGuard/Proton keys, WiFi,
  Caddy basic-auth, DB credentials, Cloudflare/Mailjet/ntfy/restic-B2 tokens,
  the openclaw/eva credential block
- `machines/macbookpro/secrets/default.yml`
- `users/alex/secrets/default.yml` — service tokens (GitHub, Anthropic, PyPI,
  crates.io, Prefect, ntfy, iCloud), plus per-host overrides
  `users/alex/secrets/{homeserver,macbookpro}.yml`

Referenced as `config.sops.secrets.<name>.path` or via sops templates.

### Homeserver

`machines/homeserver/default.nix` is the host configuration; one service is
split out: `fugazi.nix` (everything fugazi-web: policy helpers, the `testing`
instance, overlay, assertions). It is curried over the flake inputs because its
`imports` needs them. Its sops secrets stay in `sops.nix` and its ntfy-alert
units in `default.nix`, so those lists each read as one thing.

`services.nix` holds the small standalone services: bitcoind (full node, tx
indexing), PostgreSQL, ddclient, openssh, pipewire, avahi. `networking.nix` is
hostname/WiFi/firewall; `settings.nix` kernel/boot/nix tuning; `users.nix`
accounts; `networks.nix` the shared LAN/WireGuard prefix constants;
`disko.nix` the disk layout (provisioning-only).

Firewall convention: there is NO blanket LAN accept and wg0 is NOT a trusted
interface. A service that LAN/VPN clients reach directly gets its own
source-restricted `-I nixos-fw` accepts driven by an allowed-networks option
(samba, print, dns-filtering, ups-monitor, media-server all follow this
pattern); everything else is reachable only through Caddy.

### MacBook-specific

- Declarative Homebrew in `machines/macbookpro/homebrew.nix`
- macOS preferences and nix policy (GC, store optimise) in `settings.nix`
- Zen browser via `browser.nix` (better-zen input)
- User launchd agents in `users/alex/launchd.nix`

## Upstream-Tracked Workarounds (check periodically; drop when possible)

Each row carries bookkeeping tied to external state. On each `nix flake update`
(or every few months), re-check and remove once the drop condition is met.
Locations are given as greppable identifiers, not line numbers. Last reviewed:
2026-09-19.

| Workaround | Location | Drop condition / re-check |
|---|---|---|
| Caddy plugin-set hash pin (`caddy.withPlugins` from `nix-caddy-withplugins`) | `my.caddy-plugins.hash` in `machines/homeserver/default.nix`; overlay nearby; input in `flake.nix` | Effectively permanent (nixpkgs#450289 closed: nixpkgs' own withPlugins hashes caddy+plugins together). Re-pin `hash` only when the plugin LIST changes. If the *base* FOD (`caddy-base-proxy`) fails instead, `nix flake update nix-caddy-withplugins` — and if its bot hasn't caught up, wait rather than hand-patch. |
| OpenClaw skills hardlink staging | `skillsStageSeed` in `modules/openclaw/default.nix` | The skills loader silently drops any SKILL.md with nlink>=2, and `auto-optimise-store` hardlinks every store file — so store-path `extraDirs` load ZERO skills. ExecStartPre copies skills to `${stateDir}/nix-skills` (fresh inodes). Drop when the skills loader stops enforcing `rejectHardlinks` (the plugin loader already did in 2026.6.x). Re-check on each openclaw bump: `openclaw skills check` must show Total ≠ 0. |
| OpenClaw source = nixpkgs-unstable | `pkgsUnstable` in `machines/homeserver/default.nix`; input in `flake.nix` | 26.05 freezes openclaw at 2026.5.7 (claude-cli exec approvals hang — no permission responder). Drop when 26.05 catches up; `nix flake update nixpkgs-unstable` to bump. |
| OpenClaw insecure-package allowance | `allowInsecurePredicate` on `pkgsUnstable` in `machines/homeserver/default.nix` | Upstream's deliberate `knownVulnerabilities` (LLM prompt-injection). Won't be lifted; predicate is version-independent, nothing to hand-bump. |
| rPackages.V8 icu78 force-link | overlay in `modules/r-dev/system.nix` | Drop when [nixpkgs#547532](https://github.com/NixOS/nixpkgs/issues/547532) is fixed. Re-check on each `nix flake update`: revert the overlay and confirm `gt`/`gtsummary` still **build** (not just eval). |
| prefect fastapi lower-bound relax | overlay in `modules/prefect-server/system.nix` (imported by BOTH machines) | prefect 3.8.3 declares `fastapi>=0.139.0` but 26.05 ships 0.136.3; the runtime-deps check would fail every rebuild on both hosts. The pin is metadata-only (verified: the API app starts under 0.136.3). Drop when `nixpkgs#python3Packages.fastapi.version` >= 0.139.0 or prefect relaxes; re-check by deleting the overlay and building `.#nixosConfigurations.homeserver.pkgs.prefect`. |
| immich source = nixpkgs-unstable | `pkgsUnstable.immich` in `machines/homeserver/default.nix`; `package` option in `modules/cloud-suite` | 26.05's 2.7.5 is EOL + marked insecure (an eval failure for the whole host, and it serves photos.acpuchades.com publicly). Cross-channel is safe: same NixOS module either side, ML follows via passthru, both substitute from cache. Note 2.x→3.x migrates the DB irreversibly on first start. Drop on the next NixOS release: delete the `package =` line. |
| linux-firmware `yellow_carp_dmcub.bin` pin | overlay in `machines/homeserver/settings.nix` | linux-firmware 20260910 ships an *older* DMCUB (0x0400004A) that this board's PSP rejects — DMUB never starts, display-core errors log ~5×/s, a kworker pins a core and the fan runs full. Overlay swaps in the 20260810 blob (0x0400004C). Drop when upstream ships >= 0x0400004C (`xxd -s 16 -l 4`, little-endian). Re-check requires a **reboot** (firmware loads at amdgpu probe) + `journalctl -b -k | grep -c 'Error queueing DMUB'` = 0. Don't use `amdgpu.dc=0`: the iGPU serves Jellyfin/Immich transcoding and the local console. |
