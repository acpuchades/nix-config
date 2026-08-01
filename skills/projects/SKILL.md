---
name: projects
description: How to work inside a Python or R project repository — use the project's own environment via .envrc/direnv, and create one with uv (Python) or rix (R) when it is missing. Consult it whenever you clone or pull a repository, before running python/R inside one, and before adding any dependency to a project.
---

# Working in a Python or R project

## First: is this a project, or is it scratch work?

This skill applies when you are working INSIDE a project repository — a
directory you cloned or pulled that contains any of `.envrc`, `pyproject.toml`,
`default.nix`, `flake.nix`, `renv.lock`, `DESCRIPTION`. Those declare an
environment, and that environment is the one to use.

It does NOT apply to ad-hoc work in your own workspace. For a quick script —
parse a PDF, tabulate a spreadsheet, fit a model — just run the `python3` and
`R` you already have. They carry a curated library set (see the `toolkit`
skill), they need no network and no setup, and wrapping them in a fresh
virtualenv would be slower and buy you nothing. Do not bootstrap an
environment for a one-off.

## If the project already has an `.envrc`

Use it. Do NOT hand-roll an environment beside it.

    cd <project>
    cat .envrc          # ALWAYS read it first — it tells you what the env is
    direnv allow        # only needed the first time, or after .envrc changes

`direnv allow` marks the file trusted and loads the environment on entry.
A common `.envrc` is one line:

| `.envrc` contains        | The environment is                      |
|--------------------------|-----------------------------------------|
| `use nix`                | `default.nix` / `shell.nix` in the repo |
| `use flake`              | `flake.nix` devShell                    |
| `source .venv/bin/activate` or `layout uv` | a uv virtualenv       |
| `layout python`          | a plain venv                            |

If `direnv` is not loaded in your shell, enter the environment directly
(`nix-shell`, `nix develop`, or `source .venv/bin/activate`) rather than
running the project's code against your own interpreter — the versions will
not match and the results will be wrong in ways that are hard to see.

## If the project has NO `.envrc`, create one

**Python — use `uv`:**

    cd <project>
    uv init             # only if there is no pyproject.toml yet
    uv venv
    echo "source .venv/bin/activate" > .envrc
    direnv allow
    uv add <package>    # NOT pip install

**R — use `rix`** to generate a pinned Nix environment, then let direnv load it:

    # in R, from the project directory
    rix(r_ver = "<date or version>",
        r_pkgs = c("dplyr", "gt"),
        ide = "none", project_path = ".", overwrite = TRUE)

    # then, in the shell
    echo "use nix" > .envrc
    direnv allow

`renv` is fine for a project that ALREADY uses it (`renv.lock` present) — use
`renv::restore()` and `renv::install()` there. Do not migrate an existing
`renv` project to `rix` unless asked.

## Adding dependencies

Add them to the file that DECLARES the environment, then re-enter it. Never
install into a live environment as a side effect of running something:

| Project type    | Add a dependency by                              |
|-----------------|--------------------------------------------------|
| uv / pyproject  | `uv add <pkg>` (edits pyproject.toml + uv.lock)  |
| Nix (`use nix`) | editing `default.nix` / `flake.nix`, then reload  |
| rix             | re-running `rix(...)` with the package added      |
| renv            | `renv::install(<pkg>)` then `renv::snapshot()`    |

## Never install into a global or user-wide library

This is the rule that does not bend. `pip install` outside an activated
virtualenv, `install.packages()` into a system or user library, and anything
under `sudo` are all wrong — they leak one project's dependencies into every
other project and into your own interpreter, and on this host they will fail
or be silently discarded anyway (the Nix store is read-only). If you cannot
get a project environment working, say so and stop; do not fall back to a
global install.

## Version control

COMMIT the files that pin the environment: `.envrc`, `default.nix`,
`flake.nix`, `flake.lock`, `pyproject.toml`, `uv.lock`, `renv.lock`.
Never commit the environment ITSELF — add `.direnv/` and `.venv/` to
`.gitignore` if they are not there already.

Keep clones under your own tree (`~`). Remember that `git pull` and every other
remote verb follows the normal approval rules in the `policy` skill.
