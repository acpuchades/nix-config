{
  description = "Alejandro's nix-darwin system flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Nixpkgs Unstable — pulled ONLY for a newer openclaw than nixpkgs-26.05
    # ships. 26.05 freezes openclaw at 2026.5.7, whose claude-cli runtime cannot
    # answer Claude's exec permission protocol (control_request/can_use_tool), so
    # a non-allowlisted command hangs ~180s; unstable's 2026.6.33 adds the
    # responder (and fixes the bundled-surface hardlink guard). Scoped to
    # my.openclaw.package on the homeserver — nothing else consumes it.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Nix-Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Emacs Overlay — daily-regenerated MELPA/ELPA package set. nixpkgs only
    # snapshots Emacs packages once per release and freezes them, which routinely
    # ships packages broken against the bundled Emacs; this overlay tracks the
    # real upstream releases so we roll forward with `nix flake update` instead
    # of pinning per-package commit hashes.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # Sops-Nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Better Zen — Betterfox-derived privacy/security user.js for Zen browser
    better-zen.url = "github:Codextor/better-zen";
    better-zen.flake = false;

    # fugazi-web — PRIVATE repo for the homeserver's backtest service. It's a real
    # flake, and we consume BOTH of its outputs: `overlays.default` for the
    # packages (pkgs.fugazi-service + pkgs.fugazi-web-frontend, so the backend
    # wheel pin and the frontend npmDepsHash live upstream) and
    # `nixosModules.default` for the units (`services.fugazi-web`: uvicorn, the
    # maintenance timer, the per-frequency deployment ticks). modules/fugazi-web
    # is then just the host topology around it. Follows our nixpkgs so its
    # packages build against nixpkgs-26.05 and no second nixpkgs lands in the
    # lock. Bump with `nix flake update fugazi-web`.
    #
    # A tarball URL, NOT a `github:` input, on purpose: the `github:` fetcher
    # resolves refs through api.github.com and authenticates only via the
    # `access-tokens` setting (empty on the homeserver) — it ignores netrc, so it
    # 404s on a private repo. The tarball fetcher instead goes through Nix's
    # ordinary downloader, which honors nix.settings.netrc-file (github/token →
    # nix/netrc; see the modules/fugazi-web header and machines/homeserver). The
    # `refs/heads/main` URL means `nix flake update` rolls to the latest main.
    fugazi-web.url = "https://github.com/acpuchades/fugazi-web/archive/refs/heads/main.tar.gz";
    fugazi-web.inputs.nixpkgs.follows = "nixpkgs";

    # The SAME repo on its `testing` branch, feeding the staging instance
    # (testing.fugazitrade.com). Two inputs rather than two imported modules,
    # because there is no such thing as two imported modules: the NixOS module
    # declares its options at `services.fugazi-web`, and a second declaration of
    # an option is a hard eval error ("The option ... is already declared"), not a
    # conflict priorities can settle. So exactly ONE nixosModules.default is
    # imported — the one above — and the staging instance is handed this input's
    # `packages` output instead (my.fugazi-web.instances.testing.packages).
    #
    # The consequence worth knowing: the staging instance runs THIS branch's
    # application under MAIN's plumbing. Unit shape, the systemd sandbox and the
    # option surface all come from the imported module. That is fine while a
    # branch only changes the app, and it is the first thing to suspect when one
    # that changes how the service is launched misbehaves; once branches diverge
    # that far the staging deployment wants its own system (a NixOS container
    # importing this flake's own module) rather than an instance.
    #
    # Tracking `refs/heads/testing` means a push deploys on the next rebuild, with
    # no `nix flake update` in the loop. The cost is real and deliberate: this
    # input is evaluated as part of the whole homeserver config, so a testing
    # branch that does not evaluate blocks `nixos-rebuild` for EVERY service on
    # this box, not just its own. If that ever bites, pin this to a commit and
    # bump it by hand — the staging instance is the only consumer.
    fugazi-web-testing.url = "https://github.com/acpuchades/fugazi-web/archive/refs/heads/testing.tar.gz";
    fugazi-web-testing.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    outputs@{
      self,
      nix-darwin,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      sops-nix,
      better-zen,
      fugazi-web,
      fugazi-web-testing,
      emacs-overlay
    }:
  {
    # Build darwin flake using:
    # $ sudo darwin-rebuild switch --flake .#MacBook-Pro-de-Alejandro
    darwinConfigurations."MacBook-Pro-de-Alejandro" = import ./machines/macbookpro outputs;
    nixosConfigurations."homeserver" = import ./machines/homeserver outputs;
  };
}
