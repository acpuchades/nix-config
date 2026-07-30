{ ... }:

{
  nix.settings = {
    extra-substituters = [ "https://rstats-on-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };

  # Upstream workaround: rPackages.V8 (pulled in transitively by gt →
  # juicyjuice → V8) fails to build. nixpkgs' nodejs-libv8 (which r-V8 compiles
  # against) is built with ICU 78, while the rest of nixpkgs is on ICU 76, so
  # V8.so is left with undefined `icu_78::*` symbols and the load-test aborts the
  # build. Force-link icu78 (icu4c-78.3, which IS packaged) to supply exactly
  # those symbols. Injected via the r-modules `overrides` hook so dependents
  # (juicyjuice/gt/gtsummary) rebuild against the fixed V8. Drop once nixpkgs
  # realigns ICU or ships a working r-V8.
  # Reported upstream: https://github.com/NixOS/nixpkgs/issues/547532
  # Drop condition: that issue fixed. Last checked: 2026-07-30.
  nixpkgs.overlays = [
    (final: prev: {
      rPackages = prev.rPackages.override {
        overrides = {
          V8 = prev.rPackages.V8.overrideAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ [ final.icu78 ];
            NIX_LDFLAGS = (old.NIX_LDFLAGS or "") + " -licui18n -licuuc -licudata";
          });
        };
      };
    })
  ];
}
