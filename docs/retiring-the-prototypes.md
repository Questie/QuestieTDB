# Retiring the prototypes

`Getters` and `toc-database` were the prototypes QuestieTDB was mined from. Everything worth
keeping has been ported, and nothing in this repository builds against them any more.

**Nothing has been moved.** This document is the runbook for the move, not a record of it —
see [Why this was not done automatically](#why-this-was-not-done-automatically).

---

## What was taken, and where it lives now

| From | To | Notes |
| --- | --- | --- |
| `Getters/GetterDB/Meta/DumpFunctions.lua` | `generator/serialize.lua` | One generic serializer replaces the domain-specific dumpers, which produced byte-identical output but iterated with `pairs()` and so were not deterministic. Sparse-array nil holes, compact number formatting and the no-trailing-separator discipline carried over. |
| `Getters/GetterDB/Corrections/Corrections.lua` | `src/corrections/registry.lua` | Load-order namespaces, corrections held behind functions, collision reporting. Registration became owner-scoped, and a collision no longer displaces the sitting entry. |
| `Getters/GetterDB/Corrections/Enum/`, `Icons.lua` | `src/corrections/enum/constants.lua` | **Extracted from Questie rather than copied from the prototype**, by `tools/port-corrections.lua`. Same discipline as the schema: derived, so it cannot drift. |
| `toc-database/src/lib.lua` | `generator/lib.lua` | Chunked metadata emission with UTF-8-safe splitting. |
| `toc-database/verify.lua` | `verify.lua` | Widened to run the shipped `src/` reader against the metadata emulator. |
| `toc-database/test.lua` | `test.lua` | Rewritten around negative controls — a check that cannot fail is not a check. |
| `toc-database/src/config.lua` | `src/config.lua` | Explicit enumeration of inputs, so no directory scanning and no `lfs`. |
| `Questie/cli/apiMocks.lua`, `loadTOC.lua` | `generator/loader.lua`, `emulator/client.lua` | Split by what they answer: one stands up the addon environment, the other the client. |

### What was deliberately rejected

* **`require("lfs")`.** A C module. Inputs are enumerated in `src/config.lua` instead, which
  keeps the option of shipping a bare `lua` binary for contributors. `validators/checks.lua`
  needed the same treatment when it moved.
* **The `.lua-table` intermediate stage.** `Getters/data/*.lua-table` is `GetterDB`'s output,
  with corrections **already applied** by the pipeline QuestieTDB replaces. Building on it would
  double-apply corrections from the wrong system. It is a dead end, not an asset — and
  `test.lua`'s `no-prototype-inputs` suite fails the build if any file so much as names it.
* **`Meta/*Meta.lua` field ordering.** It served the compiler's skip map. TOC storage is keyed
  by field index, so ordering is irrelevant, and the schema comes from Questie, which is
  current — `Getters`' quest schema is stale at 33 keys against Questie's 36, with
  `orderedObjectives` colliding on index 33.
* **`mangos_translation`, `translations`.** Questie's lookups are taken as-is.
* **The `EMPTY` sentinel.** A frozen table carrying `__newindex` redirects writes instead of
  failing, which is the exact trap freezing exists to avoid. Table getters return `nil`.

### Independence is enforced, not assumed

`test.lua` includes a `no-prototype-inputs` suite that scans every build input — `src/`,
`generator/`, `emulator/`, `validators/`, `tools/`, `.github/` and the top-level entry points —
for a path literal resolving into `Getters/`, `toc-database/`, or any `.lua-table`. It also
asserts every enumerated generation input exists inside this repository.

Provenance comments naming a prototype are fine and wanted: they record where a design came
from. What is forbidden is a path that resolves into one.

---

## The runbook

From the workspace root (the directory holding `QuestieTDB/`, `Questie/`, `Getters/` and
`toc-database/`):

```sh
mkdir -p .retired
git -C Getters/GetterDB remote -v          # MUST print a remote before continuing — see below
mv Getters .retired/Getters
mv toc-database .retired/toc-database
cp QuestieTDB/docs/retired-README.md .retired/README.md
```

`.retired` is already excluded from version control by the workspace `.gitignore`.

They are **moved, not deleted**. Nothing is removed from any remote, nothing is destroyed
locally, and retiring is reversible by moving a folder back.

---

## Why this was not done automatically

`Getters/GetterDB` is a nested git repository with **no remote**. Verified:

```
$ git -C Getters/GetterDB remote -v
(no output)

$ git -C Getters/GetterDB log --oneline | head -3
379801b refactor(generator): split offline environment into focused modules
e6c854c refactor(generator): move pipeline into top-level Generator directory
bdae9ce ci(repo): align workflows with generator-only pipeline
```

It exists **only on this machine**, and it holds the serializer and the corrections registry
this project was built from. Moving it into `.retired` protects it from the cleanup; it does
not protect it from machine loss.

`DESIGN.md` calls this "the only irreversible failure mode in the plan", and it is the one step
here that a mistake cannot undo.

**So: push `GetterDB` somewhere off this machine first.** Then run the runbook.

---

## Do not confuse this with removing Questie's compiler

Two independent retirements, easily conflated:

| | Removes | Gated on |
| --- | --- | --- |
| This document | the prototypes, `Getters` and `toc-database` | the serializer and the corrections registry being ported and in use |
| `DESIGN.md` step 13 | Questie's `compiler.lua`, its raw data files, the SavedVariables database, the SoD parallel database | the differential test running clean and its golden snapshot committed |

They gate on different things, live in different repositories, and must not be collapsed.
