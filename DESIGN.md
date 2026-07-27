# QuestieTDB — Questie TOC Database

Design document. No implementation yet.

Vocabulary is defined in [`CONTEXT.md`](./CONTEXT.md) and used precisely here.

## Mission

Replace Questie's binary/SavedVariables database with a TOC-metadata-backed database
delivered as a companion addon. Questie becomes a **consumer** of the database rather than
its owner, while retaining the ability to register Corrections.

## Locked decisions

| Decision | Value |
| --- | --- |
| Data source | **Questie's existing data.** No VibeQuest data, schema, or coordinates. |
| Schema | Questie's existing `questKeys` / `npcKeys` / `itemKeys` / `objectKeys`, unchanged. |
| Domain | QuestieTDB's domain is *Questie's data model*, including Questie-specific fields. |
| Ownership | QuestieTDB owns the database. Questie owns what to do with it. |
| Repos | Two repos, two addons, two independent version streams. |
| Dependency | Hard `## Dependencies: QuestieTDB`. The client's red warning covers absence; the contract version covers mismatch. |
| Runtime modes | **Source mode** and **Baked mode**, selected automatically by TOC suffix precedence. |
| Variants | SoD / Classic+ are Dynamic Correction sets over the Era database, not separate databases. |
| Localization | Baked into the TOC alongside entity data. |
| Value ownership | Database-owned. Reads return **Frozen values**. |
| Engine base | `toc-database`'s generator, retargeted at Questie's schema. |
| Schema reference | `Getters` — already encodes Questie's field layout, though **stale** (32 fields vs Questie's current 36). |

`toc-database` and `Getters` are prototypes to mine, then delete. **Questie is the source of
truth for the data model.**

## Ownership

### Moves into QuestieTDB

| What | Today |
| --- | --- |
| Raw entity data | `Database/{Classic,TBC,Wotlk,Cata,MoP}/*DB.lua` (20 files, git-tracked) |
| Schema / field keys | `Database/{quest,npc,item,object}DB.lua` → a `Meta` layer |
| Data corrections | most of `Database/Corrections/*Fixes.lua` |
| Corrections registry | `QuestieCorrections:Initialize` / `MinimalInit` |
| Entity localization | `Localization/lookups/<Expansion>/lookup{Quests,Npcs,Objects,Items}/*` |
| Support data | `Database/Zones/data/`, `QuestXP/DB/`, `DropTables/data/`, `FactionTemplates/` |
| Data validators | `cli/validators.lua`, `cli/validate-*.lua` |
| Icon / enum constants used by corrections | `Questie.ICON_TYPE_*` |

### Deleted outright

- `Database/compiler.lua` (1367 lines)
- The SavedVariables database — `Questie.db.global.{npc,quest,obj,item}{Bin,Ptrs}`
- The entire parallel SoD database — `Questie.db.global.sod.*`
- `dbIsCompiled`, `dbCompiledOnVersion`, `dbCompiledLang`, `dbCompiledExpansion`,
  `dbCompiledCount`, and the `QUESTIE_DATABASE_ERROR` recompile dialog
- The `*CompilerTypes` / `*CompilerOrder` tables
- The in-game "Questie DB is updating" compile pass

### Stays in Questie

| What | Why |
| --- | --- |
| `QuestieDB.lua` semantic layer — `GetQuest`, `IsDoable`, `IsComplete`, tag info, race/class masks | Game logic, not storage |
| Support **logic** — `zoneDB.lua`, `QuestieXP.lua`, `dropDB.lua` | `QuestieLoader` modules with runtime behaviour; they read data from the lib |
| Blacklists — `hiddenQuests`, `questItemBlacklist`, `questNPCBlacklist`, `HardcoreBlacklist` | Hiding is consumer policy, not a database fact |
| Policy corrections — `QuestieEvent`, `SeasonOfDiscovery`, `ContentPhases`, `IsleOfQuelDanas` | Read `Questie.db`; moving them would invert the dependency |
| `Localization/Translations/*` and `l10n("...")` | UI text |
| `lookupZones`, `lookupQuestCategories`, `lookupOverrides` | Zone/category names, not entity data |
| `Constants.lua`, `MeetingStones.lua` | Small, and Questie's own concepts |
| Map, tracker, tooltips, everything above the seam | Unaffected |

### Generation inputs

QuestieTDB reads **Questie's tracked source files directly**. There is no intermediate
export format.

| Input | Shape | Loading |
| --- | --- | --- |
| `Database/<Exp>/<x>{Quest,Npc,Item,Object}DB.lua` | `QuestieDB.questData = [[return {...}]]` | mock `QuestieLoader`, execute, `loadstring` the inner string |
| `Localization/lookups/<Exp>/lookup*/<locale>.lua` | guarded by `if GetLocale() ~= "deDE" then return end` | stub `GetLocale()` once per locale |
| `Database/Zones/data/`, `QuestXP/DB/`, `DropTables/data/`, `FactionTemplates/` | `QuestieLoader:ImportModule(...)` then table assignment | same mock |

Every input is already Lua, so this is a **mocked-environment loader, not a parser**. Questie's
`cli/apiMocks.lua` and `cli/loadTOC.lua` (172 lines together) already do exactly this — it is
how `validate-era.lua` loads the database today — and they move here with the validators.

`questKeys` is defined *inside* each data file, so schema and data arrive together. This is
the mechanical reason Questie is the schema source of truth.

**Do not build on the prototypes' intermediate format.** `Getters/data/*.lua-table` is
`GetterDB`'s output, with corrections **already applied** by a pipeline QuestieTDB replaces.
Using it would double-apply corrections from the wrong system. It is a dead end, not an asset.

### What to mine from the prototypes

`GetterDB` has the better *functions*; `toc-database` and `Getters` have the better *shape*.
Take accordingly.

| Take | From | Why |
| --- | --- | --- |
| `Meta/DumpFunctions.lua` | GetterDB | The Lua serializer. TOC metadata stores tables as Lua source, so **serialization is generation**. Already solves compact output, sparse arrays with `nil` holes, and deterministic ordering via `dumpAsArraySorted`. |
| `dumpCoordinatesV2`, `dumpTriggerEndV2`, `dumpExtraObjectivesV2` | GetterDB | Domain-specific compaction for the fields that dominate artifact size. |
| `Corrections/Corrections.lua`, `Enum/`, `Icons.lua` | GetterDB | The registry, load-order namespaces, and the constants corrections reference. |
| Config-driven pipeline shape, TOC emission, chunking, `verify.lua` | toc-database | Explicit type/version enumeration instead of directory scanning. |

| Reject | Why |
| --- | --- |
| The `.lua-table` intermediate stage | Produces the dead-end format above. QuestieTDB goes raw → corrections → TOC in one pass. |
| `require("lfs")` | GetterDB depends on LuaFileSystem, a **C module**. `Getters/generate.lua` is pure Lua and proves it is avoidable by enumerating inputs in config. Keeping the generator dependency-free preserves the option of shipping a bare `lua` binary for contributors. |
| `mangos_translation`, `translations` | Questie's lookups are taken as-is. |
| `Meta/*Meta.lua` field ordering | Served the compiler's skip-map. TOC is keyed by field index, so ordering is irrelevant — and the schema itself comes from Questie, which is more current. |

Deterministic serialization is a requirement, not a preference: without it, every regeneration
produces a spuriously different 85 MB artifact, making releases unreviewable and checksums
meaningless.

### The boundary rule

> **QuestieTDB owns what is true about game entities. Questie owns what to do with that truth.**

A Correction fixes what is *true* — a wrong coordinate, a missing prerequisite. Deciding an
entity should not be shown is consumer policy. Quest 7462 genuinely exists in
`quest_template`; that Questie hides it as a duplicate is Questie's decision, and another
consumer may legitimately want it.

## The seam

Questie's runtime database surface, by call-site count (raw grep, includes tests):

| Surface | Sites |
| --- | --- |
| `Query*Single(id, key)` | ~290 |
| `Query*(id, keys)` | ~10 |
| `*Pointers[id]` | ~22 |

Raw `questData` / `npcData` / `itemData` / `objectData` access (~530 sites) sits in `cli/`,
`Database/Corrections/`, and `Localization/` — all compile-time paths that are moving or
being deleted.

The replaceable surface is **12 functions**: `QuerySingle`, `Query`, and `pointers`, per
entity type. Nothing above the seam changes.

### Nil and empty semantics — match Questie exactly

**Decided: reproduce Questie's current compiler semantics precisely.** ~290 call sites have
been written against them, so any deviation is a silent behaviour change.

| Source value | Read back as |
| --- | --- |
| number `nil` | **`0`** — writers emit `value or 0`; lossy and deliberate |
| string `nil` | `nil` |
| string `""` | `""` — distinct from nil, must survive |
| table `nil` **or** `{}` | **`nil`** — empty tables never come back |
| pair `{0, 0}` | `nil` — Questie's documented hack |
| unknown entity ID | `nil` |

Two implementation consequences:

- **Numeric getters default to `0`, never `nil`.** `0` is truthy in Lua, so consumers already
  test `~= 0`; returning `nil` would change behaviour at every one of those sites.
- **Table getters return `nil`, never an empty table.** The prototypes' `EMPTY` sentinel
  (`{"startedBy", "table", EMPTY}`) contradicts this and is removed. It is independently
  disqualified anyway — a frozen table carrying `__newindex` redirects writes rather than
  failing.

This remains the highest-risk class of bug, so the rule is enforced by exhaustive differential
testing rather than trusted to review. Full detail in
[`docs/storage-format.md`](./docs/storage-format.md).

## Two runtime modes

The client searches for suffixed TOCs first and falls back to `AddonName.toc` only if none
are found. That rule selects the mode automatically.

| | Source mode | Baked mode |
| --- | --- | --- |
| TOC | base `QuestieTDB.toc` (committed) | `QuestieTDB_Vanilla.toc` etc. (gitignored, generated) |
| Reads resolve from | raw entity data | TOC metadata store |
| Static Corrections | applied live | already folded in; files absent |
| Requires | nothing but a clone | a bootstrap download or local Generation |

A fresh clone junctioned into `AddOns` is a working development environment with **no
download and no Lua toolchain**. Generating or bootstrapping the suffixed TOC switches the
same folder to Baked mode.

**Mode must be unmistakable in-game.** Source mode gets a permanent visible indicator — on
the map or in Questie's settings — not just a login message.

### Sharing the code path

Only two functions differ between modes:

| Shared, written once | Differs per mode |
| --- | --- |
| Named getters (generated from schema) | `readField(id, fieldIndex)` |
| Generic `Get(id, fieldIdx)` | `getAllIds()` |
| Correction Overlay lookup | |
| Decoded field cache | |
| Field defaults | |
| l10n overlay | |
| Schema / Meta | |

Source: `rawData[id][fieldIndex]`. Baked: `decode(getMetadata(id, fieldIndex))`.

Source mode and Generation apply Static Corrections through the *same* path, so "what I see
in dev is what ships" follows from shared code rather than from a test.

## Corrections

### Model

Two categories, declared by the author. There is no automatic promotion, and therefore
nothing that can misfire.

- **Static Correction** — folded in during Generation. Never shipped to end users.
- **Dynamic Correction** — conditional, or otherwise not knowable before Generation.
  Applied at query time through the **Correction Overlay**.

`GetterDB/Corrections/Corrections.lua` is the starting point and most of it survives: the
registry, per-expansion load-order namespaces, collision handling, corrections held behind
functions so data materialises only on apply, and `wipe()` after deferred registration.

Fix while porting: `Sod/base/*.lua` passes a literal `70` rather than `SoDBaseDynamicOrder`
(300), so despite the comment "Sod will always load last" it applies *before* Era's faction
fixes at 120. Also `Sod/static/sodItemQuestStartFixes.lua` sits in a folder named `static`
but registers dynamic — folder names are not a reliable category signal.

### Read semantics — one shared view

Every consumer reads the same data. There is no per-consumer view.

```
                base data (raw or baked)
                          |
   layer: QuestieTDB Dynamic Corrections   (faction, SoD)
                          |
   layer: Questie                          (events, phases, Quel'Danas)
                          |
   layer: SomeOtherAddon
                          |
                  composed view  <--  every consumer reads this
```

A Correction fixes wrong source data — that is not one consumer's opinion. And a third-party
addon registers a Correction *precisely so Questie displays it*.

Corrections never write into base data at runtime; the Overlay is a read-time lookup, so an
untainted base exists by construction. Writing into data happens only during Generation,
offline.

### Owner scoping

Registration is owner-scoped, and application is too:

```lua
LibQuestieDB.ApplyRegisteredCorrections()           -- every pending owner
LibQuestieDB.ApplyRegisteredCorrections("Questie")  -- one owner
```

This is required by load order, not a convenience: third-party addons declare
`## Dependencies: Questie` and therefore register *after* Questie has already applied.

The owner parameter selects **which layer is being refreshed**, never which layers are
visible. Recomposition always includes every live layer.

Precedence is two-level — outer by owner apply order, inner by `loadOrder` within an owner —
with **last applied wins**. This follows load order naturally
(`QuestieTDB` < `Questie` < third-party), and must be documented, because `loadOrder` changes
meaning from "global sequence" to "sequence within an owner".

### Layers, recomposed on apply

Keep per-owner layers and **recompose** the composed view on apply, rather than resolving
layers at read time:

- Read path stays a single lookup behind the `Decoded field cache`.
- Recomposition is O(total corrections) but runs only on init and setting changes.
- **Idempotent by construction** — re-applying rebuilds from the registry instead of
  accumulating into it.

That last property fixes a latent weakness in today's `addOverride`, which merges into the
override table and can only add or replace, never *remove*. It also composes cleanly with
freezing: a fresh object per recomposition can be frozen without conflict.

### Correction origin

The generator runs offline with only QuestieTDB present, so it bakes only corrections owned
by QuestieTDB. Anything registered by Questie or a third party is Dynamic by definition, and
the generator can enforce this rather than trusting convention.

### `extraObjectives` and translated text

`l10n(...)` appears ~100 times in `classicQuestFixes.lua` and ~207 times in
`tbcQuestFixes.lua`, always inside `extraObjectives`, alongside `Questie.ICON_TYPE_*`.

**Store the enUS string, translate at render time.** Questie's `l10n()` is keyed by the
English string, so output is identical. `GetterDB` already anticipated this — its correction
files stub `local function l10n(s) return s end`.

### Conflict visibility

Recomposition is the natural place to detect silent clobbering. A debug mode should log
`owner "MyAddon" overrode "Questie" on quest 123 field objectivesText`, with `GetOwners()`
exposing applied order.

## Public API

```lua
-- Data access (the 12-function seam)
LibQuestieDB.Quest.Get(id, key) / .GetAll(id, keys) / .GetAllIds(hashmap)
-- × Npc, Item, Object

LibQuestieDB.Quest.GetRaw(id, key)             -- base data only, bypasses layers
LibQuestieDB.GetProvenance(datatype, id, key)  -- which owner supplied the winning value

-- Schema
LibQuestieDB.Meta.QuestMeta.questKeys

-- Corrections
LibQuestieDB.Corrections.RegisterCorrection(owner, datatype, name, func, loadOrder)
LibQuestieDB.Corrections.RegisterRuntimeCorrection(owner, datatype, name, func, loadOrder)
LibQuestieDB.Corrections.GetRegistrar(owner)   -- optional wrapper

-- Lifecycle
LibQuestieDB.ApplyRegisteredCorrections(owner?)
LibQuestieDB.InvalidateCache(datatype, id)

-- Contract
LibQuestieDB.contractVersion
```

### Initialization order

QuestieTDB loads before Questie, so it cannot apply Questie's Corrections at its own load
time:

1. **QuestieTDB loads.** Registry available, base data queryable immediately.
2. **Questie loads and registers** its policy Corrections.
3. **Questie calls `ApplyRegisteredCorrections("Questie")`** in its staged init — roughly
   where `QuestieCorrections:MinimalInit()` sits today — then queries.

Prefer this explicit call over `GetterDB`'s `C_Timer.After(0, …)` frame timing. Registering
later must remain legal, which is what `InvalidateCache` is for.

### Contract version

Independent release cycles make skew inevitable. The hard `## Dependencies` covers *absence*;
it does not cover *presence with the wrong version*. Questie checks `contractVersion` at init
and fails with a specific message. This replaces `QUESTIE_DATABASE_ERROR` as the "your
database is wrong" path.

## Value ownership

Reads return **Frozen values**. The database owns them; callers must not mutate. A caller
needing a mutable working copy calls `CopyTable` explicitly.

Enforced with `table.freeze`, which is a **VM-level flag, not a metatable proxy** — reads are
completely unaffected, `rawset` is blocked, and `getmetatable` still returns `nil`.
Measurements from [`docs/table.freeze.md`](./docs/table.freeze.md), which records live-client
verification on Classic Era 1.15.9: deep-freeze allocates **0 KiB** against `CopyTable`'s
~357 KiB, and runs 8–20% faster.

| | |
| --- | --- |
| Source-mode base data | frozen after load |
| Scalar fields | cached unconditionally, both modes — strings and numbers are immutable, so no hazard |
| Table fields (17 of 32 quest fields) | cached **and** frozen, both modes |
| Genuine mutation needs | explicit `CopyTable` at the call site |

Three consequences:

- **The audit is self-executing.** `GetQuest` writes `creatureObjective[3] = nil` into its
  query results — safe today only because the compiler decodes fresh tables per call. Turning
  freezing on surfaces every such site as
  `attempted to perform indexed assignment on a frozen table`.
- **That particular mutation should be fixed in the data.** It exists to normalise "0 means no
  icon". Normalise during Generation so the reader never needs to write.
- **`__newindex` sentinels must go.** A frozen table *with* `__newindex` redirects writes to
  the metamethod instead of failing. `Getters`' `EMPTY` sentinel uses exactly that pattern;
  replace it with a plain frozen table.

`table.freeze` does not exist in standard Lua 5.1, which is what the generator, `verify.lua`,
and Questie's `cli/` harness run on. Capability detection is mandatory, and the offline
harness needs a pure-Lua substitute so CI stays strict.

## Localization

Questie today bakes locale into the compiled binary: `l10n:Initialize()` writes translated
strings into `questData` *before* compile, and `dbCompiledLang` forces a full recompile when
the UI locale changes.

Replace with the l10n overlay: locale-joined values, `SetLocale()` at runtime, getters
wrapped with enUS fallback. **This deletes the recompile-on-locale-change entirely.**

l10n stays **inside** the QuestieTDB TOC rather than becoming a separate addon. TOC metadata
lives in client-side storage, not the Lua heap — nothing materialises until a getter decodes
it, so a German user never touches the other eight locales' strings and they never cost Lua
memory or GC pressure.

Sizing, for the record: l10n is ~72% of the artifact (`{l10n}-Mists` is 61 MB of the 84.5 MB
combined), across 9 locales — `deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN, zhTW` — with
**no enUS**, since base data is already English. In-client testing confirms this loads fast at
full size, so keeping all locales in the store is validated rather than assumed. Splitting l10n
out stays available as a mitigation at the same seam, only finer, if the artifact ever grows
substantially.

Field coverage already matches exactly: quest `name` + `objectivesText`, npc `name` +
`subName`, item `name`, object `name`.

## Variants: SoD, Classic+

SoD and Classic+ are an in-game flag over Era, not separate clients. They are Dynamic
Correction sets over the Era database — which is what `Sod/base/sodBase*.lua` already does.
No separate generated database.

This deletes Questie's entire parallel compiled database for SoD, halving both compile time
and SavedVariables footprint. The cost is SoD base tables staying resident rather than baked.
Accepted: performance loss is fine for variants that are only a flag apart.

## Packaging and release

Two repos, two addons, two version streams. Questie's `build.py` already does per-flavor
packaging (`ignorePatterns.append(expansionStrings[i])`) and emits a `release.json` multi-flavor
manifest — QuestieTDB mirrors that discipline rather than inventing one.

QuestieTDB ships **bundled** inside Questie's zip and may also publish standalone.
`release.json` already carries `"nolib": false`, which is CurseForge's mechanism for exactly
this case: a `-nolib` variant lets standalone installers avoid a folder collision.

### Release-backed data bootstrap

Baked TOCs are **never committed**. CI builds a pre-release on every commit and a release on
demand, publishing baked artifacts with a manifest carrying schema version, producer commit,
per-artifact SHA-256, and the contract version.

A bootstrap script — PowerShell or bash, no Lua — installs artifacts into the gitignored TOC
slot in the developer's clone. Deviations from the generic pattern: the install target is
`Interface/AddOns/QuestieTDB/` rather than a project cache dir, and **all flavors are
downloaded** so switching test clients needs no re-bootstrap.

### Measured sizes

| | Raw | Zipped |
| --- | ---: | ---: |
| All five flavors | 251 MB | **66 MB** |
| Vanilla | 20.4 MB | 5.3 MB |
| Mists | 84.5 MB | 22.0 MB |

### Generation cost

| | |
| --- | ---: |
| One entity type, all five flavors | **2.7 s** |
| Everything, including l10n and combined | 47 s |

Generation is pure Lua with no C dependencies. **Later, nice-to-have:** commit a small
`lua.exe` so contributors can generate and run tests locally without installing a toolchain.
Not needed now — source mode covers the dev loop, and CI has Lua.

## Module layout

```text
QuestieTDB/
  QuestieTDB.toc              base TOC — source mode (committed)
  QuestieTDB_<Flavor>.toc     generated, baked mode (gitignored)

  src/
    config.lua                flavors, entity types, l10n field contract
    meta/                     schema — field keys, types, per-field defaults
    read/
      shared.lua              getters, cache, overlay lookup, defaults, freezing
      source.lua              readField/getAllIds over raw tables
      baked.lua               readField/getAllIds over TOC metadata
    corrections/
      registry.lua            Register / Apply / load-order / recomposition
      <expansion>/            Static and Dynamic Corrections
      enum/, icons.lua        constants corrections reference
    l10n/                     locale-joined overlay
    types/                    LuaLS annotations

  data/                       raw entity data, moved from Questie
  support/                    zones, questXP, dropTables, factionTemplates

  generate.lua                data + Static Corrections -> TOC
  verify.lua                  round-trip verification
  validators/                 data-invariant checks, moved from Questie cli/
  emulator/                   metadata emulator + mocked-env loader
  test.lua                    decoder and equivalence tests

  docs/
    storage-format.md         the on-disk contract
    table.freeze.md           live-client freeze research
    adr/
```

`src/read/` is the only place the two modes diverge — `shared.lua` holds everything else, so
the seam stays two functions wide.

## Testing

Build on Questie's existing harness: `cli/loadTOC.lua`, `cli/apiMocks.lua`, busted,
`.types/busted`.

1. **Metadata emulator (shared library).** Parses a generated `.toc` into a key→value map and
   installs `C_AddOns.GetAddOnMetadata`, handling `~N~` chunk markers. Written once here,
   consumed from Questie.
2. **Round-trip verification.** Source table == decoded metadata, per field per id. Port
   `toc-database/verify.lua`.
3. **Data validators.** `cli/validators.lua` moves here wholesale — 16 cross-entity invariant
   checks over `(entities, keys)`. The expansion matrix moves with it, taking the heaviest job
   out of Questie's CI.
4. **Source/baked equivalence.** The two modes must read identically for every id × key. This
   is the **load-bearing test in the system** — it is what makes the dev loop trustworthy, and
   with two permanent backends it never retires.
5. **Compiled/TOC differential.** Migration-only, and it has a **deadline**: the compiler is
   the reference implementation, so before removing it, freeze its output as a committable
   golden snapshot (per-id hashes, not full values).
6. **Fake backend + fixture.** An in-memory implementation of the 12-function seam, seeded
   from a few hundred entities checked into Questie. Default for Questie's 15 DB-touching unit
   tests: hermetic, fast, no network. Affordable only because the seam is 12 functions wide.
7. **Pinned integration job.** One Questie CI job against a pinned QuestieTDB release, proving
   the real artifact loads and the contract matches. Pinned, not latest, so a QuestieTDB
   release can never spontaneously break Questie's CI.

## Open risks and gates

### 1. TOC size in the live client — CLEARED

Previously the blocking gate. **Resolved by prior in-client testing**: both `toc-database` and
`Getters` were tested deeply against real clients at full size and load fast, with no parse or
memory problem at the 20–85 MB range.

This also settles the l10n-in-TOC decision — keeping all nine locales in the store is
validated, not assumed. Splitting l10n out remains a known mitigation if the artifact grows
substantially beyond today's size, but it is not currently needed.

Consequence for the rest of the plan: **the prototypes' runtime behaviour is validated**, which
raises the value of extracting their format precisely — see
[`docs/storage-format.md`](./docs/storage-format.md).

Generated and intermediate data is disposable: `Getters/{Database}` and `Getters/data/` are
untracked derived output. `Getters` and `toc-database` themselves are recoverable from their
remotes. **`GetterDB` is not** — it is a nested repository with no remote, and must be
preserved before the folder around it is removed. See phase 11.

### 2. `*Pointers` semantics — audit

The ~22 `*Pointers` sites need checking to confirm they only test existence and iterate ids.
`GetAllIds(true)` returns a real hashmap and is a drop-in *if* that holds.

### 3. Schema drift

`Getters`' schema is already stale — 32 fields against Questie's current 36, missing
`availableUntilCompleted`, `availableStartingWith`, `requiredRanks`, `disabledByQuest`. Port
from Questie, not from the prototype, and expect the schema to keep moving.

### 4. Mutation audit

Freezing makes this self-executing, but the volume is unknown until it runs. `GetQuest` is one
site; there will be others, invisible today because current semantics forgive them.

## Rejected alternatives

Recorded so they are not re-derived. Each was seriously considered and rejected for a
specific reason.

**`hidden` as a schema field.** Blacklisting would become an ordinary Correction
(`[7462] = {hidden = true}`), collapsing two mechanisms into one and giving blacklists the
whole correction lifecycle including the dev loop. Genuinely more elegant, and the right
answer in a greenfield design. Rejected because `hiddenQuests[id]` is a single table index in
the hottest availability loops, and turning it into an overlay check plus a metadata decode
regresses the exact path this design protects. Separately, hiding is consumer policy and not a
database fact — see the boundary rule.

**Automatic promotion via an `X-TDB-BAKED` manifest.** Generation would record which
corrections it folded in, with per-correction hashes; the runtime would apply any registered
correction absent from the manifest, so a new correction worked immediately and "promotion"
was just regeneration. Rejected because it only existed to make promotion automatic, and once
the author simply declares Static or Dynamic there is no promotion step to automate. It would
have added per-correction hashing, a manifest format, and a `Pending` lifecycle state to solve
a problem that no longer exists.

**An overlay-based dev addon.** Static Corrections loaded through the Correction Overlay so
contributors could skip Generation. Superseded by source mode, which is strictly better on
two counts: an overlay can add and change but **never remove**, so deleting a correction is
untestable through it; and source mode shares the generator's correction path rather than
being a parallel one.

**Fresh-per-read values.** Every read returns a new table, matching today's semantics exactly
and requiring no consumer changes. Rejected because it forces a `loadstring` per read in
`IsDoable`'s availability loops and discards the Decoded field cache — paying a Lua parse on
the hottest path to accommodate a small number of fixable mutation sites.

**Splitting localization into its own addon.** Would let English users — who need none of the
9 locales — skip ~72% of the artifact. Rejected because TOC metadata lives in client-side
storage rather than the Lua heap, so unused locales are never decoded and cost no Lua memory
or GC pressure. Download size remains the only real cost, and this stays the first lever to
pull if the size gate is unfavourable.

**Keeping raw data in Questie.** Rejected: the generator would need Questie checked out to
build, and support-data validators such as
`checkNpcSpawnAreaIds(npcs, npcKeys, getUiMapIdByAreaId)` could not run without it.

## Verified findings

Checks already performed, recorded so they are not repeated.

**Event corrections do not depend on display settings — no boundary violation.** All three
uses of `Questie.db.profile.showEventQuests` in `Holidays/QuestieEvent.lua` gate only `print`
statements. The correction data itself (`npcDataOverrides`, `hiddenQuests`) is conditioned on
calendar date and Darkmoon Faire location — real game state. `QuestieEvent` is already a clean
Dynamic Correction and needs no untangling.

**The mutation hazard is aliasing, not copying.** `QuestieDB.GetQuest` assigns
`QO[stringKey] = rawdata[intKey]`, so the Quest object holds a *reference* to the query
result rather than a copy. That is what lets `creatureObjective[3] = nil` reach the database.
When auditing under freezing, this assignment pattern — not the `= nil` write — is what to
search for.

## Phasing

The ordering constraint that matters: **the compiler is the reference implementation, so it is
removed last** — after the differential test runs clean and its golden snapshot is committed.

1. **Tracer bullet.** One entity type, one flavor, end to end: generate `QuestieTDB_Vanilla.toc`
   from Questie's `classicQuestDB.lua`, load it in-game, and read `QuestDB.name(2)` →
   `"Sharptalon's Claw"`. Pierces loader, serializer, TOC emission, decoder, and in-client read
   in one thin slice. Every later phase widens it.
2. Port the `toc-database` engine here, retargeted at Questie's schema. Move the `Meta` layer.
3. Build the metadata emulator and round-trip verification.
4. Build source mode and baked mode behind the shared getter API. Establish the equivalence test.
5. Introduce the backend interface in Questie behind a flag; the compiler stays default.
6. Differential test until clean. **Commit the golden snapshot.**
7. Move data corrections, Support data, and validators here. Build the registry and dev loop.
8. Expose the public API; convert Questie's policy corrections to registered Dynamic Corrections.
9. Move entity l10n to the overlay; delete the `dbCompiledLang` recompile trigger.
10. Set up CI, release-backed bootstrap, and the pinned integration job.
11. **Retire the prototypes to `.retired`.** Once the engine (step 2) and the corrections
    registry (step 7) are ported, move `Getters` and `toc-database` into a gitignored
    `.retired` folder at the workspace root. They are moved, not deleted — retiring is
    reversible, and nothing is removed from any remote.

    **`GetterDB` still needs an off-machine copy.** It is a nested git repository with **no
    remote**, holding the serializer and the corrections registry. `.retired` protects it from
    the cleanup; it does not protect it from machine loss. Push it somewhere independently —
    this is worth doing now rather than at phase 11, since it is the only irreversible failure
    mode in the plan.

    `.retired` is reference material, never a build input. In particular, nothing may consume
    the prototypes' intermediate export format — see Generation inputs.
12. Flip the default. Keep the compiler one release cycle.
13. Remove `compiler.lua`, the raw data files, the SavedVariables database, and the SoD
    parallel database. Questie is now a pure consumer.

Two independent retirements, easily confused: **step 11 removes the prototypes**
(`Getters`, `toc-database`), and **step 13 removes Questie's compiler**. They gate on
different things and must not be collapsed.
