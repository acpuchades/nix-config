{ ... }:

# Package-level, not server-level: this fixes `pkgs.prefect` itself, which BOTH
# hosts install (the CLI, via home.packages and the homeserver's system
# packages), so both machines import this file even though only the homeserver
# imports `default.nix` beside it — the same split `modules/r-dev` uses.

{
  # Upstream workaround: nixpkgs-26.05 bumped python3Packages.prefect 3.7.0 →
  # 3.8.3 without the fastapi bump that release wants. Prefect 3.8.3 declares
  # `fastapi>=0.139.0,<1.0.0`; the branch still ships fastapi 0.136.3, so
  # `pythonRuntimeDepsCheckHook` fails the build outright:
  #     - fastapi<1.0.0,>=0.139.0 not satisfied by version 0.136.3
  # That takes down system-path, home-manager-path and prefect-server.service on
  # every rebuild. nixpkgs-unstable has the consistent pair (prefect 3.8.3 +
  # fastapi 0.141.1), so this is a stable-branch bump that landed half-done.
  #
  # Relax the lower bound rather than bump fastapi: the check is metadata-only,
  # and moving fastapi to 0.141 on the stable branch means rebuilding every
  # dependent against a version nothing else here was tested with. Verified that
  # the pin is conservative rather than load-bearing — with 0.136.3 the server
  # imports and `prefect.server.api.server.create_app(ephemeral=True)` returns a
  # populated FastAPI app.
  #
  # Drop when the branch carries a fastapi that satisfies prefect's own bound
  # (`nix eval nixpkgs#python3Packages.fastapi.version` >= 0.139.0), or when a
  # later prefect relaxes it. Re-check on each `nix flake update`: delete this
  # overlay and confirm `nix build .#nixosConfigurations.homeserver.pkgs.prefect`
  # still succeeds. Last checked: 2026-08-28.
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
        (pyFinal: pyPrev: {
          prefect = pyPrev.prefect.overridePythonAttrs (old: {
            pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "fastapi" ];
          });
        })
      ];
    })
  ];
}
