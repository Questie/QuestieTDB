# QuestieTDB

The database Questie consumes. Stores entity data as WoW addon TOC metadata, readable at
runtime with no file I/O, and owns the offline generator that produces it.

Quests, NPCs, items and objects for Classic Era, TBC, Wrath, Cataclysm and Mists — with
corrections applied, nine locales, and the same values in a fresh clone as in a shipped build.

---

## Two modes, and the client picks

The client searches for flavour-suffixed TOCs first and falls back to `QuestieTDB.toc` only if
none are found. That rule selects the mode at no cost: **a generated artifact wins simply by
existing.**

| | Source mode | Baked mode |
| --- | --- | --- |
| TOC | `QuestieTDB.toc` (committed) | `QuestieTDB_Vanilla.toc` etc. (generated, gitignored) |
| Reads resolve from | raw entity data | the TOC metadata store |
| Static Corrections | applied live | already folded in |
| Requires | nothing but a clone | one bootstrap command, or `lua generate.lua` |

A fresh clone junctioned into `AddOns` is a working development environment — no download, no
Lua toolchain. Generating an artifact switches the same folder to baked mode with no code
change.

---

## For consumers

Start at **[`docs/api.md`](docs/api.md)**. It is written so a third-party addon author needs no
source reading.

```lua
QuestDB.name(2)                                  --> "Sharptalon's Claw"
QuestDB.Get(2, "requiredLevel")                  --> 20
NpcDB.spawns(30)                                 --> { [12] = { {36.43, 55.89}, ... } }

LibQuestieDB.l10n.SetLocale("deDE")
QuestDB.name(2)                                  --> "Klaue von Scharfkralle"

LibQuestieDB.GetRegistrar("MyAddon")
    .RegisterRuntimeCorrection("Quest", "fixes", function() ... end, 10)
```

Two behaviours to internalise before writing anything:

* **Numeric getters return `0`, never `nil`.** Test `~= 0`, not truthiness.
* **Every table read returns a fresh, deeply independent copy you own.** Mutate it freely;
  the next read is unaffected, and `CopyTable` is wasted work. `GetAllIds` is the one
  exception: it hands back a shared table, so treat that one as read-only.

---

## For contributors

```sh
lua5.1 generate.lua all           # every flavor            ~50s
lua5.1 verify.lua                 # round-trip verification ~96s
lua5.1 equivalence.lua            # source == baked, all read forms + self-proof
lua5.1 reconstruct.lua Vanilla    # artifact == byte-exact re-derivation ~8s
lua5.1 validators/run.lua         # cross-entity invariants  ~4s
lua5.1 test.lua                   # unit tests and negative controls

python3 tools/differential/golden.py check Vanilla    # composed reads == committed snapshot ~5s
python3 tools/differential/compiler_diff.py Vanilla  # composed reads == Questie's compiler ~10s
```

Or run the whole sweep at once:

```sh
tools/check.sh                    # verify, equivalence, reconstruct, validators, differential
tools/check.sh all                # + generate and the unit tests
tools/check.sh verify --flavors=Vanilla,Mists
```

25 jobs in **1m44s** against roughly 9½ minutes run one at a time. It parallelises by memory
budget rather than core count, because the jobs are wildly uneven — equivalence on Mists peaks
at 1.66 GB and 57 s, on Vanilla at 0.42 GB and 19 s — so a flat `-j N` either thrashes a
laptop or leaves a workstation idle. The budget comes from `MemAvailable` at startup;
`--budget-mb=N` overrides it and `--sequential` turns fan-out off. Per-job logs land in
`.out/checks/`.

The golden gate is the successor to the cross-implementation differential (built to
compare this tree against the independent `-pi` sibling, where it caught the Era-gating,
constants, and Titan Reforged defect chain). It guards the one class the other gates
cannot: generator and source mode being consistently wrong *together*. After an
intentional data change, `golden.py refresh <Flavor>` regenerates the snapshot for
review and commit.

`compiler_diff.py` is the reference-implementation differential DESIGN.md phase 6 called
for. It runs Questie's real compile path offline — the one `cli/validate-era.lua` already
drives — and compares `QuestieDB.Query<Type>Single` against this database's composed reads,
id by id and field by field. The golden snapshot can only catch drift from *this* tree;
this gate is the only one that can say whether the database still matches the thing it
replaces. It needs a Questie checkout (`--questie=../Questie`, the default) and `bit32` on
the Lua path, which it picks up from luarocks automatically. Accepted divergences live in
`tools/differential/compiler-baseline/`; `--update-baseline` re-records them for review.

Plain Lua 5.1, no `lfs`, no luarocks, no C dependency anywhere. Inputs are enumerated in
`src/config.lua` rather than discovered by scanning directories.

To refresh a local install instead of regenerating:

```sh
tools/bootstrap.sh "/path/to/Interface/AddOns"
```

### Re-syncing with Questie

Two things derive from Questie and are committed here, so drift is a build failure rather than
a discovery months later. CI runs both and fails on any diff.

```sh
lua5.1 generate.lua meta ../Questie          # schema -> src/meta/*Meta.lua
lua5.1 tools/port-corrections.lua ../Questie # corrections + constants
```

The ported correction files are **byte-identical copies** of Questie's; a compat shim supplies
the module surface they import. Re-syncing is a file copy, not a rewrite.

---

## Layout

```text
QuestieTDB.toc            base TOC — source mode (committed)
QuestieTDB_<Flavor>.toc   generated, baked mode (gitignored)

src/
  config.lua              flavors, entity types, file lists, l10n contract
  meta/                   schema, nil/empty semantics, the on-disk codec
  read/                   shared getters + the two backends that differ
  corrections/            registry, compat shim, ported correction sets
  l10n/                   the locale overlay
  support/                whole-table game reference data
  ui/                     the source-mode indicator

data/                     raw entity data
support/                  zones, quest XP, drop tables, faction templates

generate.lua              data + Static Corrections -> TOC
verify.lua                round-trip verification
equivalence.lua           source/baked equivalence, every read form, self-proving
reconstruct.lua           byte-exact artifact reconstruction against the generator
test.lua                  unit tests and negative controls
generator/                offline internals
emulator/                 metadata emulator, client stubs, freeze substitute
validators/               data-invariant checks
tools/                    port, package, bootstrap, differential golden gate
docs/                     api.md, storage-format.md, adr/
```

`src/read/` is the only place the two modes diverge — two functions wide.

---

## Documentation

| | |
| --- | --- |
| [`docs/api.md`](docs/api.md) | the public surface, for consumers |
| [`docs/storage-format.md`](docs/storage-format.md) | the on-disk contract and the nil/empty rules |
| [`DESIGN.md`](DESIGN.md) | architecture, locked decisions, rejected alternatives |
| [`CONTEXT.md`](CONTEXT.md) | vocabulary |
| [`docs/adr/`](docs/adr/) | decision records |
| [`docs/adr/0005-element-level-nil-semantics.md`](docs/adr/0005-element-level-nil-semantics.md) | never-nil structures and element-level nil→0, which amend the storage contract |
| [`docs/questie-handover.md`](docs/questie-handover.md) | every known divergence from Questie's compiler, its disposition, and the switch-over checklist |
| [`docs/read-performance.md`](docs/read-performance.md) | what a read costs and why, measured in a live client against the prototype and Questie's compiler |
| [`docs/client-metadata-probes.md`](docs/client-metadata-probes.md) | how the client's metadata store actually behaves |
| [`docs/table.freeze.md`](docs/table.freeze.md) | live-client freeze research |
| [`docs/retiring-the-prototypes.md`](docs/retiring-the-prototypes.md) | what was mined from `Getters` and `toc-database` |
