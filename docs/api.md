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

## Reading entity fields

Four Entity globals, one per entity type, with an identical surface:

```lua
LibQuestieDB.Quest   -- also the global QuestDB
LibQuestieDB.Npc     -- NpcDB
LibQuestieDB.Item    -- ItemDB
LibQuestieDB.Object  -- ObjectDB
```

### `Entity.Get(id, key) -> value`

`key` is a canonical field name or a positional index. Both return the same value, but the
name is the faster path as well as the clearer one: a name resolves in a single lookup, a
number misses that map and falls through to a type check. The gap is small, 0.55 µs against
0.63 µs warm, and `GetByIndex` closes most of it if you need positional access. See
[`read-performance.md`](./read-performance.md).

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

### `Entity.GetRaw(id, key) -> value`

Base data only, bypassing the Correction Overlay and localization. For tooling and
debugging — use `Get` for anything a player sees. An overlay-added entity has no raw row, so
`GetRaw` legitimately returns nil for it.

**`GetRaw` is not cached.** It reaches the backend on every call, so it stays at roughly
2.7 µs no matter how often you read the same field, where `Get` drops to 0.6 µs once warm.
Do not reach for it in a loop.

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
never the same table — do not use table identity to compare reads, and hold onto a value
rather than re-reading if you need stability. The copy costs 0.13–1.8 µs for typical field
shapes (measured live), the same class as a cache hit.

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
* **Coordinates in a correction must be authored values.** Quantization is deliberately
  non-idempotent (exactly like Questie's compiler), so never write back a coordinate you
  read out of the database — supply the original source coordinate.

### Precedence

Two levels, the later-ranked writer wins:

* outer: the order owners **first** called `ApplyRegisteredCorrections` — an owner's rank is
  fixed at first apply, and re-applying refreshes that owner's layer **in place**. A refresh
  (including `ApplyParameterized`, which re-applies the `QuestieTDB` owner) can therefore
  never hoist a layer above corrections registered later.
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

### Corrections outrank localization

A corrected field is returned as corrected in **every** locale — the lookup translation is
skipped, because a copied lookup must not replace a fix with stale text. `GetProvenance`
therefore always names the owner whose value you actually received. An *uncorrected*
localizable field translates normally.

### Parameterized corrections

A few correction sets need a runtime fact only the consumer knows — the Darkmoon Faire's
current location. These are never applied automatically:

```lua
LibQuestieDB.Corrections.ApplyParameterized("LoadDarkmoonFixes", faireLocation)
```

Registers and applies the recorded set as an ordinary QuestieTDB Dynamic layer. Calling it
again with a new argument **replaces** the previous application rather than accumulating.
Returns how many recorded sets matched (0 when none are recorded for this flavor).

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

`LibQuestieDB.contractVersion` is also readable directly. It is bumped when the API or the
storage format changes in a way a consumer can observe.

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

Applying corrections and changing locale already invalidate what they need to. This is for a
consumer that mutates state QuestieTDB cannot see.
