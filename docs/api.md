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

`key` is a canonical field name or a positional index. Both are equivalent; the name is
clearer and costs one table lookup.

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

### `Entity.GetAll(id, keys) -> values`

Bulk access. Values come back in the order the keys were requested.

```lua
local name, level = unpack(QuestDB.GetAll(2, { "name", "requiredLevel" }))
```

### `Entity.GetAllIds(hashmap) -> list | map`

```lua
QuestDB.GetAllIds()              --> { 2, 5, 7, 12, ... }   ascending
QuestDB.GetAllIds(true)          --> { [2] = true, [5] = true, ... }
QuestDB.Exists(2)                --> true
```

The hashmap form is a drop-in for an existence check.

### `Entity.GetRaw(id, key) -> value`

Base data only, bypassing the Correction Overlay. For tooling and debugging — use `Get` for
anything a player sees.

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
| table `{}` | **`nil`** — empty tables never come back |
| pair `{0, 0}` | `nil` |
| unknown entity ID | `nil` |

Two consequences worth stating plainly:

* **Numeric getters return `0`, never `nil`.** `0` is truthy in Lua, so test `~= 0` rather than
  truthiness.
* **Table getters return `nil`, never an empty table.** Guard before indexing.

Full detail in [`storage-format.md`](./storage-format.md).

---

## Value ownership

**Reads return frozen values. The database owns them.**

```lua
local spawns = NpcDB.spawns(30)
spawns[12] = nil                     --> error: indexed assignment on a frozen table
local mine = CopyTable(spawns)       --> take a copy, deliberately and visibly
mine[12] = nil                       --> fine
```

Freezing is a VM-level flag, not a metatable proxy: reads are completely unaffected and
`getmetatable` still returns nil. On a client without `table.freeze` the guard is absent and
mutation silently succeeds — so treat returned tables as read-only regardless.

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

### Precedence

Two levels, **last applied wins**:

* outer: the order owners called `ApplyRegisteredCorrections`
* inner: `loadOrder` within one owner

`loadOrder` means "sequence within an owner", not a global sequence. Load order makes the outer
level fall out naturally: `QuestieTDB` < `Questie` < third-party.

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
locale needs no regeneration and no rebuild.

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

---

## Cache

```lua
LibQuestieDB.InvalidateCache("Quest", 2)   -- one entity
LibQuestieDB.InvalidateCache("Quest")      -- one type
LibQuestieDB.InvalidateCache()             -- everything
```

Applying corrections and changing locale already invalidate what they need to. This is for a
consumer that mutates state QuestieTDB cannot see.
