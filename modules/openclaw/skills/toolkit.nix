# toolkit skill generator: a capability INVENTORY (distinct from policy's security
# BOUNDARY). Purely informational; derived from icfg.toolkit so it cannot drift.
{ pkgs, lib, icfg, ... }:

let
  toolkitBullets = items: lib.concatMapStringsSep "\n" (i: "- `${i}`") items;
in
pkgs.writeTextDir "toolkit/SKILL.md" ''
        ---
        name: toolkit
        description: Inventory of the Python libraries, R packages and CLI tools already installed for you. Consult it before assuming something is missing, before proposing a `pip install` / `install.packages`, or when choosing how to read/convert a document or build a quick model — reach for what is already here.
        ---

        # Your installed toolkit

        Everything below is ALREADY installed and importable. Do NOT try to install
        packages — your environment is a fixed, read-only set you cannot extend at
        runtime (`pip install` / `install.packages` will not work). If you genuinely
        need something that is not listed, ASK THE OWNER to add it to the Nix config;
        do not attempt a workaround. This list is only about what EXISTS — actually
        running the interpreters/tools (e.g. `python3`, `R`) still follows the security
        policy and may require approval (see the `policy` skill).
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
