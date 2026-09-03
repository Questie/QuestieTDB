# QuestieTDB Public API

Everything a consumer needs, without reading the source.

QuestieTDB publishes a single global, `LibQuestieDB`, plus the shorthand Entity globals
`QuestDB`, `NpcDB`, `ItemDB` and `ObjectDB`. Declare a hard dependency:

```toc
## Dependencies: QuestieTDB
```

The client's red missing-dependency warning covers *absence*. It does not cover *presence with
the wrong version* — see [Contract version](#contract-version).

---

## LuaLS declarations

Release zips include analysis-only declarations in `QuestieTDB/Types`. They cover the root
`LibQuestieDB` global, all entity methods, and every schema-backed named getter. WoW does not
load these files because no TOC lists them.

Add the packaged folder to the consuming addon's `.luarc.json`. For sibling addon folders under
`Interface/AddOns`, use:

```json
{
  "workspace.library": [
    "../QuestieTDB/Types"
  ]
}
```

Adjust the relative path if your editor workspace uses another layout.

The declarations are a shipped API contract. Contributors must update `src/types/` when entity
schemas or getters change, or when a public signature, overload, return nilability, structured
value, or Corrections interface changes. Internal refactors that preserve those contracts do
not require a type edit; `AGENTS.md` contains the file-by-file maintenance checklist.

---

## Reading entity fields

Four Entity globals, one per entity type, with an identical surface:

```lua
LibQuestieDB.Quest   -- also the global QuestDB
LibQuestieDB.Npc     -- NpcDB
LibQuestieDB.Item    -- ItemDB
LibQuestieDB.Object  -- ObjectDB
```

### `Entity.Get(id, key) -> value`

`key` is a canonical field name or a positional index. Both return the same value. Prefer a
name for clarity, or the generated named getter on a hot path because it skips key resolution
entirely. Baked mode decodes the entity's scalar row on its first field read; later scalar
reads from that entity are cache lookups. See [`read-performance.md`](./read-performance.md).

```lua
QuestDB.Get(2, "name")           --> "Sharptalon's Claw"
QuestDB.Get(2, 1)                --> "Sharptalon's Claw"
NpcDB.Get(54, "subName")         --> "Weaponsmith"
```

### `Entity.<fieldName>(id) -> value`

A named getter per field, generated from the schema. Identical to `Get(id, "<fieldName>")`.

```lua
QuestDB.name(2)                  --> "Sharptalon's Claw"
QuestDB.requiredLevel(2)         --> 20
NpcDB.spawns(30)                 --> { [12] = { {36.43, 55.89}, ... } }
```

NPC health is no longer stored. The deprecated `NpcDB.minLevelHealth(id)` and
`NpcDB.maxLevelHealth(id)` getters return placeholder values `0` and `1` for a known NPC.
The same placeholders apply through `Get`, `GetByIndex`, `GetRaw`, and `GetAll`. Dynamic
Corrections cannot replace or delete them. Unknown NPC IDs still return `nil`; these values are
compatibility placeholders, not health estimates.

### `Entity.GetAll(id, keys) -> values | nil`

Bulk access. Values come back in the order the keys were requested, in a **packed** table
carrying `n` — because a nullable field leaves a hole, and a bare `unpack` over a table with
holes silently drops everything after the first one.

```lua
local values = QuestDB.GetAll(2, { "name", "triggerEnd", "requiredLevel" })
local name, trigger, level = unpack(values, 1, values.n)   -- always all three
```

Returns `nil` for an unknown entity id.

### `Entity.GetAllIds(hashmap) -> list | map`

```lua
QuestDB.GetAllIds()              --> { 2, 5, 7, 12, ... }   ascending
QuestDB.GetAllIds(true)          --> { [2] = true, [5] = true, ... }
QuestDB.Exists(2)                --> true
```

The hashmap form is a drop-in for an existence check.

The hashmap and list answer over the **composed view**: an entity a Dynamic Correction adds
is readable, enumerable, and exists — all three or none. Treat both returns as read-only;
they are shared, not copies.

### `Entity.IdsByName(name) -> list | nil`

The reverse of the `name` getter: every composed id whose **current** name equals `name`
exactly, ascending, or `nil` when none does. Current means what `Entity.name(id)` returns right
now — the active locale, a Correction outranking a translation, an overlay-added entity present —
because the index behind it is built from those reads and from nothing else.

```lua
ObjectDB.IdsByName("Old Lion Statue")    --> { 31 }
ObjectDB.IdsByName("Battered Chest")     --> { 2843, 2844, 2849, ... }   ascending
ObjectDB.IdsByName("No Such Name")       --> nil
```

The index is built on the first call and dropped whenever the cache is — a Correction apply, a
locale change, `InvalidateCache` — then rebuilt from scratch on the next call, never patched.
That is what makes a withdrawn Correction or an old locale unable to leave a stale name behind.

Building is a full pass over every entity's name: **23 ms for Vanilla's 6,666 objects** from a
cold cache in a live client, 3.5 µs per id, and it warms the name field cache for every id —
about 2.2 MB of heap for that type, kept for the session
([`client-metadata-probes.md` §9](./client-metadata-probes.md)). Mists' 20,326 objects are
unmeasured; expect roughly three times that. `Entity.BuildNameIndex()` does that pass on
demand — a no-op when the index already exists — so a consumer can pay for it where a stall is
invisible, its own init or a settings toggle, rather than on a hover path. After an
invalidation the next `IdsByName` call pays it again, and a per-entity
`InvalidateCache(datatype, id)` counts: it drops the whole index, because it can change a name.

Like `GetAllIds`, the returned list is shared and read-only.

This exists for the case where the client hands you a name and no id — a hovered world object.
It is not a substitute for a consumer's own bookkeeping: an addon that already knows which ids
it registered something for should index those, not scan the database (ADR 0008).

### `Entity.GetRaw(id, key) -> value`

Base data only, bypassing the Correction Overlay and localization. For tooling and
debugging — use `Get` for anything a player sees. An overlay-added entity has no raw row, so
`GetRaw` legitimately returns nil for it.

**`GetRaw` is not cached.** In Baked mode, every scalar call decodes the entity row again and
every table call performs a fresh CBOR decode. `Get` retains the scalar row and table producer,
so use it for loops and ordinary consumer reads.

---

## Nil and empty semantics

**These are load-bearing and match Questie's compiler exactly.** Consumers have been written
against them for years.

| Source value | Read back as |
| --- | --- |
| number nil | **`0`** — never nil |
| number `n` | `n` |
| string nil | `nil` |
| string `""` | `""` — distinct from nil |
| table nil | `nil` |
| table `{}` | **`nil`** — empty tables never come back… |
| …except `startedBy`, `finishedBy`, `objectives` | **`{}`** — these three are never nil for an entity that exists |
| pair `{0, 0}` | `nil` |
| unknown entity ID | **`nil` for every field** — including numerics |
| invalid id (`nil`, a string) | `nil`, never an error |

Three consequences worth stating plainly:

* **Numeric getters return `0`, never `nil` — for an entity that exists.** `0` is truthy in
  Lua, so test `~= 0` rather than truthiness.
* **An unknown id is `nil` everywhere.** A missing entity can never masquerade as a valid
  all-zero row; check `Exists(id)` when the distinction matters.
* **Table getters return `nil`, never an empty table — with three exceptions.** Quest
  `startedBy`, `finishedBy` and `objectives` return `{}` rather than nil when the quest has
  none, matching Questie's compiler, whose readers build those tables unconditionally. So a
  table getter is *not* a presence test for those three: check contents, not truthiness. Guard
  before indexing everywhere else.
* **Numeric slots inside structured values default to `0`, not nil.** The field-level rule
  applies element-wise: `objective[3]` (icon), `spellObjective[3]` (item),
  `killCredit[4]` and `extraObjective[4]` (objectiveIndex) are numbers, never nil. `0` is
  truthy, so test `~= 0`. String slots inside structures stay nil. See
  [`adr/0005-element-level-nil-semantics.md`](./adr/0005-element-level-nil-semantics.md).

Full detail in [`storage-format.md`](./storage-format.md).

---

## Value ownership

**Every table read returns a fresh mutable copy. You own it** (ADR 0003 Decision 10).

```lua
local spawns = NpcDB.spawns(30)
spawns[12] = nil                     --> fine: this copy is yours
local again = NpcDB.spawns(30)       --> a fresh, unmutated copy — your edit never persists
```

This matches the semantics Questie's compiler always had: every query decoded fresh tables,
so consumers that annotate or trim what they read keep working unchanged. Two reads are
never the same table. Do not use table identity to compare reads, and hold onto a value rather
than re-reading if you need stability. Baked mode gets the fresh tree from native CBOR decode;
Source mode, Corrections and translated values use deep-copy producers.

---

## Schema

```lua
LibQuestieDB.Meta.QuestMeta.questKeys        --> { name = 1, startedBy = 2, ... }
LibQuestieDB.Meta.NpcMeta.npcKeys
LibQuestieDB.Meta.ItemMeta.itemKeys
LibQuestieDB.Meta.ObjectMeta.objectKeys

LibQuestieDB.Meta.Quest.names[1]             --> "name"
LibQuestieDB.Meta.Quest.types[1]             --> "string"    -- number | string | table
LibQuestieDB.Meta.Quest.fieldCount           --> 36
```

Derived from Questie's own key enums, so a field added upstream appears here rather than
drifting.

### Objective ordering hints

Some Quest Corrections carry consumer hints about which objective type should be rendered first.
They are not entity fields, so QuestieTDB publishes the five read-only ID sets separately:

```lua
LibQuestieDB.ObjectiveFirst.killCreditObjectiveFirst
LibQuestieDB.ObjectiveFirst.objectObjectiveFirst
LibQuestieDB.ObjectiveFirst.itemObjectiveFirst
LibQuestieDB.ObjectiveFirst.eventObjectiveFirst
LibQuestieDB.ObjectiveFirst.spellObjectiveFirst
```

Each table has the shape `{ [questId] = true }`. These are consumer-must-not-mutate tables;
QuestieTDB currently publishes the underlying mutable values directly. Their contents are
intended to match the active flavor and season. Cross-expansion Source-mode leakage and SoD
hints leaking into plain Vanilla Baked mode are tracked in
[#17](https://github.com/Questie/QuestieTDB/issues/17).

---

## Corrections

A **Correction** fixes what is *true* about an entity — a wrong coordinate, a missing
prerequisite. Deciding an entity should not be *shown* is consumer policy and does not belong
here.

Two categories, declared by the author:

| | |
| --- | --- |
| **Static** | Folded in during Generation. Only QuestieTDB can register these usefully — the generator runs offline with nothing else present. |
| **Dynamic** | Applied at query time through the Correction Overlay. **This is what a third-party addon registers.** |

QuestieTDB-owned Dynamic Corrections may depend only on provider-owned data or generic
character/game facts QuestieTDB determines itself: class, race, faction, expansion, and season.
A Correction selected or constructed from consumer-owned runtime state or policy belongs to
that consumer. Display suppression, consumer phases/settings, projections/caches, and
asynchronous consumer-side repair are examples; register them through that consumer's
owner-scoped registrar.

### Registering

```lua
local registrar = LibQuestieDB.GetRegistrar("MyAddon")

registrar.RegisterRuntimeCorrection("Quest", "my-fixes", function()
    local questKeys = LibQuestieDB.Meta.QuestMeta.questKeys
    return {
        [2] = { [questKeys.name] = "A better name" },
        [5] = { [questKeys.preQuestSingle] = {} },   -- {} clears a field
    }
end, 10)

registrar.Apply()   -- or LibQuestieDB.ApplyRegisteredCorrections("MyAddon")
```

The long form, if you prefer not to hold a registrar:

```lua
LibQuestieDB.RegisterRuntimeCorrection(owner, datatype, name, func, loadOrder)
LibQuestieDB.RegisterCorrection(owner, datatype, name, func, loadOrder)
LibQuestieDB.Corrections.UnregisterCorrection(owner, datatype, name)
LibQuestieDB.ApplyRegisteredCorrections(owner)
```

`datatype` is `"Quest"`, `"Npc"`, `"Item"` or `"Object"` (lowercase accepted).

**The correction is a function returning the table, not the table itself.** The data
materialises only on apply, so a multi-megabyte literal never sits in memory between load and
apply, and constants the body reads are resolved at apply time.

### Correction shape

`id -> fieldIndex -> value`.

* `[key] = {}` **clears** the field — an empty table reads back as nil.
* `[key] = nil` is a **no-op**: Lua's table constructor drops it. It is documentation, not code.
* An id absent from the database is **created**, which is how a correction adds an entity.
  An added entity is fully first-class: readable, enumerable through `GetAllIds`, and
  `Exists(id)` is true, until the correction is withdrawn.
* **Correction coordinates preserve their supplied `x` and `y` values.** No compiler-grid
  quantization runs in production, so a coordinate read from the database may safely be reused.
  Ordinary tuple rules still apply: spawn phase `0` and waypoint third elements are omitted.

### Precedence

Two levels, the later-ranked writer wins:

* outer: the order owners **first** applied or first wrote a `Set` slot — an owner's rank is
  fixed at that first write, and re-applying or re-writing refreshes that owner's layer **in
  place**. A state refresh can therefore never hoist a layer above corrections registered later.
* inner: `loadOrder` within one owner

`loadOrder` means "sequence within an owner", not a global sequence. Load order makes the outer
level fall out naturally: `QuestieTDB` < `Questie` < third-party.

One idiom note: `[key] = {}` in a correction deletes the field for **every** field type — a
deleted string or table reads `nil`, a deleted number falls to the existence-gated `0`
default. A *non-empty* table written to a number- or string-typed field is an authoring
error: the write is reported and dropped.

### When to apply

QuestieTDB loads before its consumers, so it cannot apply their corrections at its own load
time:

1. **QuestieTDB loads.** Registry available, base data queryable immediately, QuestieTDB's own
   layer applied.
2. **Your addon loads and registers.**
3. **Your addon calls `ApplyRegisteredCorrections("MyAddon")`** in its init, then queries.

The owner parameter selects **which layer is being refreshed**, never which layers are visible —
recomposition always includes every live layer. Registering later stays legal; call
`ApplyRegisteredCorrections` again, or `LibQuestieDB.InvalidateCache(datatype, id)`.

Re-applying is **idempotent**: the composed view is rebuilt from the registry rather than
accumulated into, which is also what makes a *withdrawn* correction actually disappear.

Re-applying an owner re-runs **that owner's** provider functions; every other owner's layer
reuses its memoized materialization. Recomposition and cache invalidation are scoped to the
datatypes the refreshed entries touch — an Item-only apply leaves Quest, Npc, and Object read
caches, shared ID maps, and Name indexes untouched (ADR 0009).

### Data-shaped corrections: `Set`

For a correction that is a small state-driven table, skip the provider function and the
explicit apply entirely:

```lua
local registrar = LibQuestieDB.GetRegistrar("MyAddon")

registrar.Set("Npc", "darkmoon-location", {
    [14828] = { [npcKeys.spawns] = { [215] = { {37.24, 37.67} } } },
})   -- visible immediately; no Apply() call

registrar.Set("Npc", "darkmoon-location", nil)   -- removes the slot; the layer underneath shows through
```

The long form is `LibQuestieDB.Corrections.Set(owner, datatype, name, rows)`, also aliased as
`LibQuestieDB.SetCorrection`.

* Each `(owner, datatype, name)` is a **slot**. Writing it again replaces the previous rows;
  `nil` removes the slot; `{}` keeps the slot but contributes nothing.
* There is no `loadOrder`: within an owner, slots take effect in creation order. Owner
  precedence is unchanged — the owner's rank is fixed by its first write or apply.
* Recomposition is scoped to the written datatype: an Item write does not drop Quest, Npc, or
  Object read caches, shared ID maps, or Name indexes.
* A name already registered as a function-shaped correction is refused — update that
  correction's captured state and re-apply instead.
* Function-shaped registration remains the right form for large tables: held behind a
  function, a multi-megabyte literal materialises only on apply. Function results are
  memoized per entry and re-run only by their own owner's apply, so another owner's `Set`
  never re-materialises them.
* The provider keeps `rows` **by reference** until the slot is rewritten or removed. Hand over
  a table you only ever mutate through another `Set`: the accumulate-and-rewrite pattern
  (mutate your table, `Set` it again) is exactly right, while mutating it without a `Set`
  leaves the published view stale until some other write to the same datatype flushes.

### Corrections outrank localization

A corrected field is returned as corrected in **every** locale — the lookup translation is
skipped, because a copied lookup must not replace a fix with stale text. `GetProvenance`
therefore always names the owner whose value you actually received. An *uncorrected*
localizable field translates normally.

### Who won

```lua
LibQuestieDB.GetProvenance("Quest", 2, "name")   --> "MyAddon"
LibQuestieDB.GetOwners()                         --> { "QuestieTDB", "Questie", "MyAddon" }
LibQuestieDB.Corrections.debug = true            --> logs one owner overriding another
```

---

## Localization

```lua
LibQuestieDB.l10n.SetLocale("deDE")
QuestDB.name(2)                       --> "Klaue von Scharfkralle"
LibQuestieDB.l10n.SetLocale("enUS")
QuestDB.name(2)                       --> "Sharptalon's Claw"

LibQuestieDB.l10n.currentLocale
LibQuestieDB.l10n.IsAvailable()       --> false in Source mode
LibQuestieDB.l10n.onLocaleChanged[#… + 1] = function(locale) … end
```

Nine locales — `deDE esES esMX frFR koKR ptBR ruRU zhCN zhTW`. `enUS` means "no overlay",
because base data is already English. Missing translations fall back to English. Changing
locale needs no regeneration and no rebuild. A translated `objectivesText` remains a table;
element counts follow the upstream lookup and may differ where a locale combines objectives.
A field a Correction supplied is never overridden by a translation (see Corrections above).

Translated fields: quest `name` and `objectivesText`, npc `name` and `subName`, item `name`,
object `name`.

`extraObjectives` descriptions are different. Correction files author row slot `[3]` as an enUS
localization key, and QuestieTDB preserves that English string. The entity localization overlay
does not translate structured `extraObjectives` rows. Consumers must translate that description
at render time with their own string-keyed localization function.

---

## Support data

Game reference data consumed as whole tables rather than through the metadata store.

```lua
LibQuestieDB.Support.Get("ZoneDB").zoneIDs
LibQuestieDB.Support.Get("ZoneDB").private.areaIdToUiMapId   -- a string; loadstring it
LibQuestieDB.Support.Get("QuestXP").db
LibQuestieDB.Support.Get("DropDB")
LibQuestieDB.Support.Get("QuestieDB").factionTemplate
```

The modules that wrap this data — zone lookup, XP calculation, drop resolution — stay with the
consumer. Only the data ships from here.

---

## Read mode

```lua
LibQuestieDB.readMode                   --> "source" | "baked"
LibQuestieDB.ModeIndicator.GetText()    --> "QuestieTDB: SOURCE MODE (Classic)" or nil
LibQuestieDB.ModeIndicator.GetStatus()  --> { mode =, expansion =, contractVersion = }
```

**Source mode** reads from raw entity data with Static Corrections applied live — a working
development environment from a clone alone, no download and no Lua toolchain. **Baked mode**
reads from a generated TOC metadata store. The client picks by TOC suffix precedence, so a
generated artifact wins simply by existing.

A consumer should surface source mode somewhere permanent. QuestieTDB draws its own small
indicator as a fallback, but a consumer's own settings panel or map is the better home.

---

## Contract version

Independent release cycles make skew inevitable.

```lua
local ok, message = LibQuestieDB.RequireContract(1)
if not ok then
    print(message)
    return
end
```

`LibQuestieDB.contractVersion` is also readable directly. Contract 2 introduced CBOR scalar
rows, CBOR table values and compressed CBOR ID headers. The public read API did not change,
so `minSupportedContract` remains 1.

The check is a **range**: `RequireContract(v)` passes for any
`minSupportedContract <= v <= contractVersion`, so a consumer built against an older
contract keeps working across additive releases. The floor rises only when a breaking
change genuinely abandons older consumers.

---

## Cache

```lua
LibQuestieDB.InvalidateCache("Quest", 2)   -- one entity
LibQuestieDB.InvalidateCache("Quest")      -- one type ("quest" works too)
LibQuestieDB.InvalidateCache()             -- everything
```

Applying corrections and changing locale already invalidate what they need to, the Name index
included. Correction writes are scoped to their datatypes; a locale change covers all four.
This API is for a consumer that mutates state QuestieTDB cannot see. Every form drops the Name
index, including per-entity invalidation, because one entity's name can change.

In Baked mode, the first read of a known entity decodes its CBOR scalar row and adopts that
table as the cache row. Corrections and active scalar translations settle before the row is
installed. Table fields cache producers over decoded CBOR bytes, not decoded tables, so each
read still returns a fresh value. Presence-mask misses cache their nil or never-nil default
without a metadata call. Unknown IDs create no cache entry.
