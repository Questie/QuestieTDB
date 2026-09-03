# QuestieTDB

The database Questie consumes. Stores entity data as WoW addon TOC metadata, readable at
runtime with no file I/O, and owns the offline generator that produces it.

Quests, NPCs, items and objects for Classic Era, TBC, Wrath, Cataclysm and Mists. Baked
artifacts include nine locales as compressed CBOR column blocks; Source and Baked modes return
the same base entity values.

---

## Two modes, and the client picks

The client searches for flavour-suffixed TOCs first and falls back to `QuestieTDB.toc` only if
none are found. That rule selects the mode at no cost: **a generated artifact wins simply by
existing.**

| | Source mode | Baked mode |
| --- | --- | --- |
| TOC | `QuestieTDB.toc` (committed) | `QuestieTDB_Vanilla.toc` etc. (generated, gitignored) |
| Reads resolve from | raw entity data | CBOR rows and tables in the TOC metadata store |
| Static Corrections | applied live | already folded in |
| Requires | nothing but a clone | one bootstrap command, or Generation against pinned Questie |

A fresh clone junctioned into `AddOns` is a working development environment — no download, no
Lua toolchain. Generating an artifact switches the same folder to baked mode with no code
change. Generation reads localization from the Questie commit recorded in `QUESTIE_COMMIT` and
fails before writing output if the checkout or required lookup files do not match. Use
`--no-l10n` only for an intentional partial artifact.

---

## For consumers

Start at **[`docs/api.md`](docs/api.md)**. It is written so a third-party addon author needs no
source reading. Release zips also include LuaLS declarations under `QuestieTDB/Types`; point the
consumer's `workspace.library` at that folder for completion and diagnostics.

```lua
QuestDB.name(2)                                  --> "Sharptalon's Claw"
QuestDB.Get(2, "requiredLevel")                  --> 20
NpcDB.spawns(30)                                 --> { [12] = { {36.43, 55.89}, ... } }

LibQuestieDB.l10n.SetLocale("deDE")
QuestDB.name(2)                                  --> "Klaue von Scharfkralle"

LibQuestieDB.GetRegistrar("MyAddon")
    .Set("Quest", "my-fix", { [2] = { [1] = "A better name" } })  -- data slot; publishes immediately

LibQuestieDB.GetRegistrar("MyAddon")
    .RegisterRuntimeCorrection("Quest", "fixes", function() ... end, 10)  -- function form, for large sets
```

Two behaviours to internalise before writing anything:

* **Numeric getters return `0`, never `nil`.** Test `~= 0`, not truthiness.
* **Every table read returns a fresh, deeply independent copy you own.** Mutate it freely;
  the next read is unaffected, and `CopyTable` is wasted work. `GetAllIds` is the one
  exception: it hands back a shared table, so treat that one as read-only.

---

## For contributors

Use the root command for generation and validation workflows:

```sh
./questietdb generate                    # generate every flavor
./questietdb generate Vanilla            # generate one flavor
./questietdb check Vanilla               # standard validation bundle for one flavor
./questietdb verify equivalence Vanilla Mists
./questietdb all                         # Generation, standard gates, Golden, and unit tests
```

Run `./questietdb --help` for every gate and option. It requires Bash 5.1 or newer and selects
`lua5.1`, or a `lua` command that reports Lua 5.1. `LUA` and `--lua=` can select another Lua
5.1-compatible executable explicitly. The `freeze` gate supports Vanilla and Mists.

The individual entry points remain useful while developing a gate:

```sh
lua5.1 generate.lua all
lua5.1 verify.lua
lua5.1 equivalence.lua
lua5.1 reconstruct.lua Vanilla
lua5.1 validators/run.lua
lua5.1 test.lua
lua-language-server --check=src/types --checklevel=Warning --check_format=pretty

python3 tools/differential/golden.py check Vanilla
python3 tools/differential/compiler_diff.py Vanilla

tools/check.sh                    # verify, equivalence, reconstruct, validators, differential
tools/check.sh all                # Generation, standard gates, Golden, and unit tests
tools/check.sh verify --flavors=Vanilla,Mists
tools/check.sh determinism freeze --flavors=Vanilla
```

### Keeping LuaLS declarations in sync

The files in `src/types/` are shipped to consumers and are part of the public API. Update them
when a change affects an entity schema or getter, a public function signature or overload,
return nilability, a structured value such as objectives or Correction entries, or the
`LibQuestieDB` and Corrections interfaces. Pure implementation changes that preserve those
contracts do not need a type edit.

Update `src/types/consumer.test.lua` when the changed contract needs a semantic LuaLS check.
Run the `lua-types` suite and LuaLS command above before packaging. `AGENTS.md` maps each kind
of public change to the declaration files that own it.

`tools/check.sh` remains the direct orchestration engine for automation and existing scripts.
It accepts the previous gate syntax and `--flavors=Vanilla,Mists`.

The sweep parallelises by memory budget rather than core count, because the jobs are wildly
uneven — equivalence on Mists peaks at 1.66 GB and 57 s, on Vanilla at 0.42 GB and 19 s — so a
flat `-j N` either thrashes a laptop or leaves a workstation idle. `all` finishes Generation
for every selected flavor before any artifact reader or unit test starts. Determinism and
freeze checks remain available as explicit gates. The budget comes from `MemAvailable` at
startup; `--budget-mb=N` overrides it with a value from 1 to 2147483647 MB, and `--sequential`
turns fan-out off. Per-job logs land in `.out/checks/`.

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

Generation and the addon tooling use plain Lua 5.1 with no `lfs`, luarocks, or C dependency.
Inputs are enumerated in `src/config.lua` rather than discovered by scanning directories. The
compiler differential is the one exception because Questie's mocks require `bit32`.
`tools/check.sh --questie=` propagates one checkout path through Generation, fidelity tests,
Reconstruction, and the compiler differential; `QUESTIE_PATH` provides the same default for
nested tools.

To refresh a local install instead of regenerating:

```sh
tools/bootstrap.sh "/path/to/Interface/AddOns"
```

### Re-syncing with Questie

Two things derive from Questie and are committed here, so drift is a build failure rather than
a discovery months later. CI runs both and fails on any diff.

```sh
git -C ../Questie checkout "$(cat QUESTIE_COMMIT)"
lua5.1 generate.lua meta --questie=../Questie # schema -> src/meta/*Meta.lua
lua5.1 tools/port-corrections.lua ../Questie  # corrections + constants
lua5.1 generate.lua toc                      # refresh the committed Source-mode file list
```

The ported correction files preserve Questie's bytes except for explicit whole-function
ownership exclusions in `tools/port-corrections.lua`; a compat shim supplies the module surface
they import. The fidelity test compares every non-excluded byte and the port fails if an
excluded block is absent or duplicated. To advance Questie, change `QUESTIE_COMMIT` first,
check out that commit, then review schema drift, the Correction re-port, validators, compiler
differential, and Golden snapshots in the same working tree. Automation reads the same pin
through `.github/actions/checkout-questie`.

The port requires Questie's four Titan entity files under `Database/Corrections/`. QuestieTDB
ports them under `src/corrections/Titan/` and applies every provider dynamically over the Wrath
base, gated by Wrath plus active season 109. Titan quest tags and availability blacklists remain
in Questie because they are consumer policy.

---

## Layout

```text
QuestieTDB.toc            base TOC — source mode (committed)
QuestieTDB_<Flavor>.toc   generated, baked mode (gitignored)

src/
  config.lua              flavors, entity types, file lists, l10n block contract
  meta/                   schema, nil/empty semantics, chunk markers
  types/                  distributable LuaLS declarations, never loaded by a TOC
  read/                   shared getters + the two backends that differ
  corrections/            registry, compat shim, ported correction sets
  l10n/                   eager active-locale block loading and lookup
  support/                whole-table game reference data
  ui/                     the source-mode indicator

data/                     raw entity data
support/                  zones, quest XP, drop tables, faction templates

questietdb                contributor command for generation and validation
generate.lua              data + Static Corrections -> TOC
verify.lua                round-trip verification
equivalence.lua           source/baked equivalence, every read form, self-proving
reconstruct.lua           byte-exact artifact reconstruction against the generator
test.lua                  unit tests and negative controls
generator/                offline internals, deterministic CBOR and vendored codecs
emulator/                 metadata and C_EncodingUtil stand-ins, client stubs, freeze substitute
validators/               data-invariant checks
tools/                    port, package, bootstrap, differential golden gate
docs/                     api.md, storage-format.md, adr/
```

`src/read/` is the only place the two modes diverge. Both backends expose field reads and ID
lists; Baked mode also exposes scalar rows and table producers for its cache fast paths.

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
