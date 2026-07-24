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

**Server modules** (homeserver only): `cloud-suite` (NextCloud, Collabora, Vaultwarden), `dns-filtering` (AdGuard Home + DNSCrypt), `web-server` (nginx + ACME), `vpn-server` (WireGuard + hostapd WiFi hotspot), `mail-relay` (Postfix SMTP relay).

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
