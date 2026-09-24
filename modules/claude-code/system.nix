# System-level overlay taking claude-code from nixpkgs-unstable, imported by each
# host (cf. emacs-core/system.nix). Lives at the system layer because it sets
# `nixpkgs.overlays`, which home-manager refuses under `useGlobalPkgs` — and both
# hosts set that, so this is also what reaches the home-manager program in
# users/alex/programs/claude-code.nix, which takes the default `pkgs.claude-code`.
#
# nixpkgs-26.05 freezes claude-code at 2.1.148, too old for the Claude 5 family
# (sonnet-5/fable-5-1 need >= 2.1.251, opus-5-5 needs >= 2.1.280). Overriding
# `pkgs.claude-code` rather than `programs.claude-code.package` keeps the CLI on
# PATH and the home-manager program on one and the same build.
#
# Takes the unstable package set ALREADY INSTANTIATED by the calling machine
# rather than the flake input, so a host that has one anyway (the homeserver, for
# openclaw and immich) does not pay for a second nixpkgs evaluation. Two things
# are therefore the caller's job, at its own `import nixpkgs-unstable`: the
# target `system`, and permitting claude-code's unfree license — that instance
# does NOT inherit the host's `nixpkgs.config.allowUnfree`, which configures the
# module system's own pkgs and says nothing about a separate import.
{ pkgsUnstable }:
{
  nixpkgs.overlays = [ (final: prev: { claude-code = pkgsUnstable.claude-code; }) ];
}
