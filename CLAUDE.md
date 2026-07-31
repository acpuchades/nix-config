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

## Architecture Overview

This is a Nix flakes-based personal system configuration managing two machines:

- **MacBook-Pro-de-Alejandro** (`machines/macbookpro/`) — aarch64-darwin, managed by nix-darwin + home-manager
- **homeserver** (`machines/homeserver/`) — x86_64-linux, managed by NixOS + home-manager

### Key Flake Inputs

- `nixpkgs` (nixpkgs-25.11-darwin) — all package sets follow this
- `nix-darwin` — macOS system configuration
- `home-manager` — user environment for both machines
- `sops-nix` — age-encrypted secrets, integrated as `darwinModules` (mac) or `nixosModules` (linux)

### Module System (`modules/`)

Modules use a consistent pattern:
```nix
options.my.<module>.enable = lib.mkEnableOption "...";
config = lib.mkIf config.my.<module>.enable { ... };
```

**Emacs modules** (11 modules): `emacs-core`, `emacs-completion`, `emacs-ui`, `emacs-org`, `emacs-mu4e`, `emacs-dev`, `emacs-ess`, `emacs-python`, `emacs-nix`. Each has a `config/` subdirectory with ELisp files deployed via home-manager `home.file` symlinks.

**Development modules**: `python-dev` (Python 3, Jupyter, ruff, uv, pyright, conda/mamba), `r-dev` (R + devtools/renv/rix, uses rstats-on-nix cachix cache).

**Server modules** (homeserver only): `cloud-suite` (NextCloud, Collabora, Vaultwarden), `dns-filtering` (AdGuard Home + DNSCrypt), `web-server` (nginx + ACME), `vpn-server` (WireGuard + hostapd WiFi hotspot), `mail-server` (Postfix inbound receive → eva's Maildir + Mailjet relay for outbound, rspamd, ACME STARTTLS).

### User Configuration (`users/alex/`)

Home-manager config shared across both machines, with `host` arg for per-host conditionals:
```nix
home-manager.extraSpecialArgs = { host = "macbookpro"; }; # or "homeserver"
```

Programs configured: ghostty, git (with delta), gpg, ssh, tmux, zsh (oh-my-zsh + plugins), starship, gh.

### Secrets Management

`.sops.yaml` defines age key recipients by file path regex. Secrets are age-encrypted YAML files:
- `machines/homeserver/secrets/default.yml` — WireGuard keys, WiFi passwords, nginx auth, DB credentials
- `users/alex/secrets/default.yml` — GitHub/Anthropic/Prefect tokens, SSH keys
- Per-host user overrides: `users/alex/secrets/homeserver.yml`, `users/alex/secrets/macbookpro.yml`

Secrets are referenced in Nix as `config.sops.secrets.<name>.path` or via SOPS template rendering for config files.

### MacBook-specific

- Homebrew managed declaratively in `machines/macbookpro/homebrew.nix` (casks, taps, mas apps)
- macOS system preferences (dock, Finder, trackpad, Touch ID sudo) in `machines/macbookpro/settings.nix`
- User launchd agents in `users/alex/launchd.nix`

### Homeserver Services

Defined in `machines/homeserver/services.nix` and modules:
- Bitcoin (full node with tx indexing)
- Prefect (workflow engine + PostgreSQL)
- DDClient (dynamic DNS)
- Fail2ban
- WireGuard server with 5 peers (`machines/homeserver/networking.nix`)

## Upstream-Tracked Workarounds (check periodically; drop when possible)

These carry ongoing bookkeeping tied to external state. On each `nix flake update` (or every few months), re-check each one and remove it once its drop condition is met. Last reviewed: 2026-07-26.

| Workaround | Location | Drop condition | Status (2026-07-26) |
|---|---|---|---|
| Caddy Cloudflare-DNS plugin hash pin (`caddy.withPlugins`) | `modules/acme-cloudflare/default.nix` (~L21-26) | Intrinsic to `withPlugins`; no clean removal. Hash must be re-pinned (`lib.fakeHash` → copy real hash) on every caddy/nixpkgs/Go bump — has churned ~4× in 3 months. nixpkgs#450289 closed with community FOD tooling (`vincentbernat/caddy-nix`, `MichailiK/nix-caddy-withplugins`) that ends the churn — migrate to drop the manual hash. | **Keep** — churn ongoing; migration is the only real fix |
| OpenClaw hardlink-guard patch (`openclawPatched`) | `modules/openclaw/default.nix` | Structural on 2026.5.x: fought `auto-optimise-store` dedup vs upstream's `rejectHardlinks` boundary check. | **DROPPED 2026-07-27** — fixed upstream in 2026.6.x (plugin loaders pass `rejectHardlinks: false`). `openclawPatched = cfg.package` (unmodified). PENDING live confirmation that bundled surfaces load under our store settings; restore the `overrideAttrs` patch from git if "Unable to open bundled plugin public surface …" recurs on dispatch. |
| OpenClaw skills hardlink staging (`skillsStageSeed`) | `modules/openclaw/default.nix` (~L652, `skillsStageDir`/`skillsStageSeed`) | Drop when the *skills* loader stops enforcing `rejectHardlinks` (as the plugin loader already did in 2026.6.x). Re-check on each openclaw bump: point `extraDirs` back at the store dirs and confirm `openclaw skills check` still shows Total = N (not 0). | **Keep (added 2026-07-31)** — the skills loader silently drops any SKILL.md with nlink>=2, and `auto-optimise-store = true` hardlinks every store file, so store-path `extraDirs` loaded ZERO skills (incl. the always-on `policy`). ExecStartPre `cp`s each skill tree into `${stateDir}/nix-skills` (fresh inodes, nlink=1) and `extraDirs` points there. Verified via `openclaw skills check` → Total 5 (6 since eva's static `gtd`/`projects` skills moved to `my.openclaw.instances.eva.extraSkillDirs`, which stage the same way). Same root cause as the (dropped) plugin hardlink-guard row above. |
| OpenClaw source = nixpkgs-unstable | `flake.nix` (`nixpkgs-unstable` input) + `machines/homeserver/default.nix` (`my.openclaw.package`) | 26.05 freezes openclaw at 2026.5.7 (claude-cli exec approvals hang — no permission responder). | **Keep** — pinned to unstable's 2026.6.33 for the claude-cli permission responder + hardlink fix. Re-check when 26.05 catches up or unstable churns; `nix flake update nixpkgs-unstable` to bump. |
| OpenClaw `permittedInsecurePackages` pin | `modules/openclaw/default.nix` | Upstream's deliberate `knownVulnerabilities` (LLM prompt-injection). Won't be lifted. | **Keep** — now version-derived (`"openclaw-${cfg.package.version}"`), and the unstable pkgs instance uses an openclaw-only `allowInsecurePredicate`, so no version string to hand-bump. |
| Vaultwarden 1.37.0 `overrideAttrs` | `modules/cloud-suite/default.nix` (~L375-395) | Drop once `pkgs.vaultwarden >= 1.37.0`. | **Keep** — pinned nixpkgs still ships 1.36.0 |
| rPackages.V8 icu78 force-link | `modules/r-dev/system.nix` (`nixpkgs.overlays`) | Drop when [nixpkgs#547532](https://github.com/NixOS/nixpkgs/issues/547532) is fixed (nixpkgs realigns ICU — nodejs-libv8 on ICU 78 vs system ICU 76 — or ships a working `r-V8`). Re-check on each `nix flake update`: `git revert` the overlay and confirm `gt`/`gtsummary` still build. | **Keep (added 2026-07-30)** — `gt`→`juicyjuice`→`V8` failed with undefined `icu_78::*` symbols; overlay links `icu78` (icu4c-78.3) into V8 via the r-modules `overrides` hook so `gt`/`gtsummary` build. Reported upstream: nixpkgs#547532. |
