# toolkit skill generator: a capability INVENTORY (distinct from policy's security
# BOUNDARY). Purely informational; derived from icfg.toolkit so it cannot drift.
{ pkgs, lib, icfg, homeDir, ... }:

let
  toolkitBullets = items: lib.concatMapStringsSep "\n" (i: "- `${i}`") items;
in
pkgs.writeTextDir "toolkit/SKILL.md" ''
        ---
        name: toolkit
        description: Inventory of the Python libraries, R packages and CLI tools already installed for you. Consult it before assuming something is missing, before proposing a `pip install` / `install.packages`, or when choosing how to read/convert a document or build a quick model — reach for what is already here.
        ---

        # Your installed toolkit

        Everything below is ALREADY installed and importable. This is YOUR OWN
        interpreter set — a fixed, read-only Nix closure you cannot extend at runtime,
        so `pip install` / `install.packages` into it will not work. Never try to
        install into a global or user-wide library. If you genuinely need something
        that is not listed here for your everyday work, ASK THE OWNER to add it to the
        Nix config; do not attempt a workaround.

        This applies to the tools you reach for by default. It is NOT a rule against
        project environments: inside a repository that declares its own (a `.envrc`,
        `pyproject.toml`, `default.nix`, `renv.lock`), you SHOULD use that environment
        and add dependencies to it the normal way. The prohibition is on polluting
        your own closure or any system-wide library, not on a project managing its own
        dependencies.

        This list is only about what EXISTS — actually running the interpreters/tools
        (e.g. `python3`, `R`) still follows the security policy and may require
        approval (see the `policy` skill).

        It also covers only what Nix installs for you. Access to an external service
        the owner has given you a token for is NOT listed here: those live in
        `${homeDir}/workspace/TOOLS.md`, one section per service, which is where you
        record every credential you are handed (see the `policy` skill). Check that
        file before concluding you cannot reach a service.
        ${lib.optionalString (icfg.toolkit.python != [ ]) ''

          ## Python libraries

          ${toolkitBullets icfg.toolkit.python}''}
        ${lib.optionalString (icfg.toolkit.r != [ ]) ''

          ## R packages

          ${toolkitBullets icfg.toolkit.r}''}
        ${lib.optionalString (icfg.toolkit.cli != [ ]) ''

          ## CLI tools

          ${toolkitBullets icfg.toolkit.cli}''}
        ${lib.optionalString (icfg.toolkit.notes != "") ''

          ## Notes

          ${icfg.toolkit.notes}''}
      ''
