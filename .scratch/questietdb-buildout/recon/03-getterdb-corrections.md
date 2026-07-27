# Recon 03 — GetterDB Corrections registry, Enum/Icons constants, generator apply path, Meta layer

All paths absolute unless prefixed with `Corrections/`, which is relative to
`/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/`.

Prototype root: `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/`
Questie (schema source of truth): `/home/logon/projects/Questie-clones/Questie-toc/Questie/`

---

## 1. `Corrections/Corrections.lua` — full quote (220 lines)

File: `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Corrections/Corrections.lua`

```lua
---@class LibQuestieDB
---@field Corrections Corrections
local LibQuestieDB = select(2, ...)

---@class Corrections
local Corrections = LibQuestieDB.Corrections

-- Localized functions
local f = string.format
local tSort = table.sort
local pairs = pairs
local ipairs = ipairs

-- Base Load Orders
Corrections.EraBaseStaticOrder = 0
Corrections.EraBaseDynamicOrder = 100
Corrections.SoDBaseStaticOrder = 200
Corrections.SoDBaseDynamicOrder = 300
Corrections.TbcBaseStaticOrder = 400
Corrections.TbcBaseDynamicOrder = 500
Corrections.WotlkBaseStaticOrder = 600
Corrections.WotlkBaseDynamicOrder = 700
Corrections.CataBaseStaticOrder = 800
Corrections.CataBaseDynamicOrder = 900
Corrections.MoPBaseStaticOrder = 1000
Corrections.MoPBaseDynamicOrder = 1100

--? Lists of functions returning corrections
--? 1. The static lists are meant to be used for pre-compile or debugging
--? 2. The dynamic lists are applied on login for faction specific corrections etc.

-- ? Item
---@type table<number, CorrectionObject> @ A list of objects returning ItemCorrections
Corrections.ItemCorrectionsStatic = {}
---@type table<number, CorrectionObject> @ A list of objects returning ItemCorrections
Corrections.ItemCorrectionsDynamic = {}

-- ? Npc
---@type table<number, CorrectionObject> @ A list of objects returning NpcCorrections
Corrections.NpcCorrectionsStatic = {}
---@type table<number, CorrectionObject>
Corrections.NpcCorrectionsDynamic = {}

-- ? Object
---@type table<number, CorrectionObject> @ A list of functions returning ObjectCorrections
Corrections.ObjectCorrectionsStatic = {}
---@type table<number, CorrectionObject> @ A list of functions returning ObjectCorrections
Corrections.ObjectCorrectionsDynamic = {}

-- ? Quest
---@type table<number, CorrectionObject> @ A list of functions returning QuestCorrections
Corrections.QuestCorrectionsStatic = {}
---@type table<number, CorrectionObject> @ A list of functions returning QuestCorrections
Corrections.QuestCorrectionsDynamic = {}

---@param datatype "item"|"npc"|"object"|"quest"
---@param name string @ Optional name for the correction functio
---@param func fun(): table<AllIdTypes, Correction[]>>
---@param loadOrder number? @ The order in which the correction should be applied
function Corrections.RegisterCorrectionDynamic(datatype, name, func, loadOrder)
  assert(datatype == "item" or datatype == "npc" or datatype == "object" or datatype == "quest", "Invalid type", datatype)
  assert(type(func) == "function", "Invalid function", func)
  assert(type(name) == "string" or type(name) == "number" or name == nil, "Invalid name", name)

  -- Capitalize datatype
  local capitalizedDatatype = LibQuestieDB.Capitalized(datatype) .. "CorrectionsDynamic"

  -- Check if loadOrder is specified
  if loadOrder ~= nil then
    -- Check if loadOrder is a number
    assert(type(loadOrder) == "number", "Invalid loadOrder", loadOrder)

    -- Check if loadOrder already exists
    -- If it does, increment until we find an empty slot
    if Corrections[capitalizedDatatype][loadOrder] then
      local oldLoadOrder = loadOrder
      while Corrections[capitalizedDatatype][loadOrder] do
        loadOrder = loadOrder + 1
      end
      LibQuestieDB.ColorizePrint("yellow", f("Warning: Order index %d already exists for corrections %s, changed to index %d.", oldLoadOrder, name, loadOrder))
    end

    -- Set correction function at specified index
    Corrections[capitalizedDatatype][loadOrder] = {
      name = name,
      func = func,
      loadOrder = loadOrder,
    }
  else
    -- Add to end by default
    local implicitLoadOrder = #Corrections[capitalizedDatatype] + 1
    Corrections[capitalizedDatatype][implicitLoadOrder] = {
      name = name,
      func = func,
      loadOrder = implicitLoadOrder,
    }
  end
end

---@param datatype "item"|"npc"|"object"|"quest" @ The type of correction
---@param name string @ Optional name for the correction functio
---@param func fun(): table<AllIdTypes, Correction[]>> @ Function returning a table of corrections (Dependency Injection-ish)
---@param loadOrder number? @ The order in which the correction should be applied
function Corrections.RegisterCorrectionStatic(datatype, name, func, loadOrder)
  assert(datatype == "item" or datatype == "npc" or datatype == "object" or datatype == "quest", "Invalid type", datatype)
  assert(type(func) == "function", "Invalid function", func)
  assert(type(name) == "string" or type(name) == "number" or name == nil, "Invalid name", name)

  -- Capitalize datatype
  local capitalizedDatatype = LibQuestieDB.Capitalized(datatype) .. "CorrectionsStatic"

  -- Check if loadOrder is specified
  if loadOrder ~= nil then
    -- Check if loadOrder is a number
    assert(type(loadOrder) == "number", "Invalid loadOrder", loadOrder)

    -- Check if loadOrder already exists
    -- If it does, increment until we find an empty slot
    if Corrections[capitalizedDatatype][loadOrder] then
      local oldLoadOrder = loadOrder
      while Corrections[capitalizedDatatype][loadOrder] do
        loadOrder = loadOrder + 1
      end
      LibQuestieDB.ColorizePrint("yellow", f("Warning: Order index %d already exists for corrections %s, changed to index %d.", oldLoadOrder, name, loadOrder))
    end

    -- Set correction function at specified index
    Corrections[capitalizedDatatype][loadOrder] = {
      name = name,
      func = func,
      loadOrder = loadOrder,
    }
  else
    -- Add to end by default
    local implicitLoadOrder = #Corrections[capitalizedDatatype] + 1
    Corrections[capitalizedDatatype][implicitLoadOrder] = {
      name = name,
      func = func,
      loadOrder = implicitLoadOrder,
    }
  end
end

do
  local staticDynamicLoadOrder = { "static", "dynamic", }
  --- Returns a list of corrections for the given type, keyed by Name or Index, useful for getting a specific correction
  ---@param type "item"|"npc"|"object"|"quest"
  ---@param includeStatic boolean @ If true, the static corrections will be included
  ---@param includeDynamic boolean? @ If true, the dynamic corrections will be included
  ---@return {static: table<number, CorrectionObject>, dynamic: table<number, CorrectionObject>}
  ---@return { [1]: "static", [2]: "dynamic" } @ The load order of the corrections
  function Corrections.GetCorrections(type, includeStatic, includeDynamic)
    if includeDynamic == nil then
      includeDynamic = true
    end

    local capitalizedTypeStatic = LibQuestieDB.Capitalized(type) .. "CorrectionsStatic"
    local capitalizedTypeDynamic = LibQuestieDB.Capitalized(type) .. "CorrectionsDynamic"

    local staticCorrections
    if includeStatic and Corrections[capitalizedTypeStatic] then
      ---@param i number Load order
      ---@param correctionObject CorrectionObject
      for i, correctionObject in ipairs(Corrections.SortCorrectionsByLoadOrder(Corrections[capitalizedTypeStatic])) do
        if not staticCorrections then
          staticCorrections = {}
        end
        staticCorrections[i] = correctionObject
      end
    end

    local dynamicCorrections
    if includeDynamic and Corrections[capitalizedTypeDynamic] then
      ---@param i number Load order
      ---@param correctionObject CorrectionObject
      for i, correctionObject in ipairs(Corrections.SortCorrectionsByLoadOrder(Corrections[capitalizedTypeDynamic])) do
        if not dynamicCorrections then
          dynamicCorrections = {}
        end
        dynamicCorrections[i] = correctionObject
      end
    end
    -- TODO: How do i remove this and keep the possiblity to load new corrections?
    -- Corrections[capitalizedTypeStatic] = nil
    -- Corrections[capitalizedTypeDynamic] = nil
    return {
      dynamic = dynamicCorrections,
      static = staticCorrections,
    }, staticDynamicLoadOrder
  end

  --- A function to sort corrections by load order to work around the fact that lua tables are unordered
  ---@package
  ---@param unsortedCorrections table<number, CorrectionObject> @ Unsorted corrections, index is loadOrder which can be any number
  ---@return table<number, CorrectionObject> sortedCorrections @ Index in this table is always 1..n
  function Corrections.SortCorrectionsByLoadOrder(unsortedCorrections)
    -- Create tables to map between sparse loadOrder and dense indices
    local indexToLoadOrder = {}
    local loadOrderToIndex = {}

    -- Iterate over unsortedCorrections to build mapping
    local index = 1
    for loadOrder, correctionObject in pairs(unsortedCorrections) do
      indexToLoadOrder[index] = loadOrder
      loadOrderToIndex[loadOrder] = correctionObject
      index = index + 1
    end

    -- Sort index table to get correct order
    tSort(indexToLoadOrder)

    -- Create sorted corrections table using mapping
    local sortedCorrections = {}
    for i, loadOrder in ipairs(indexToLoadOrder) do
      sortedCorrections[i] = loadOrderToIndex[loadOrder]
    end

    return sortedCorrections
  end
end
```

### 1a. Public API summary

| Symbol | Signature | Semantics |
| --- | --- | --- |
| `Corrections.RegisterCorrectionStatic` | `(datatype: "item"\|"npc"\|"object"\|"quest", name: string\|number\|nil, func: fun():table<id, table<fieldIndex, any>>, loadOrder: number?)` | Stores `{name=, func=, loadOrder=}` at key `loadOrder` in `Corrections[Capitalized(datatype).."CorrectionsStatic"]`. |
| `Corrections.RegisterCorrectionDynamic` | identical | Same, into `...CorrectionsDynamic`. |
| `Corrections.GetCorrections` | `(type, includeStatic: boolean, includeDynamic: boolean?) -> {static=list?, dynamic=list?}, {"static","dynamic"}` | `includeDynamic` defaults to `true` when `nil`. Returns dense 1..n lists sorted ascending by `loadOrder`; a list is **`nil`** (not `{}`) when empty. Second return value is a **shared, module-level table** `{"static","dynamic"}` — the apply order, static before dynamic. |
| `Corrections.SortCorrectionsByLoadOrder` | `(unsorted: table<number, CorrectionObject>) -> table<1..n, CorrectionObject>` | `---@package`. Collects sparse numeric keys, `table.sort`s them, re-emits densely. |
| `Corrections.Icons` | table (set in `Corrections/Icons.lua`) | Lazy `Questie.ICON_TYPE_*` accessor, see §2. |

Type aliases, `Corrections/Corrections.t.lua` (4 lines, `---@meta`):

```lua
---@meta
---@alias Correction table<number, string|table|number>

---@alias CorrectionObject {name: string, loadOrder: number, func: fun():table<AllIdTypes, Correction[]>}
```

### 1b. Load-order namespace scheme

The 12 constants declared at `Corrections.lua:15-26` (this is the **complete** set of load-order
constants anywhere in GetterDB — verified by `grep -rn "Order" Corrections Helpers Meta Generator`):

| Constant | Value |
| --- | --- |
| `Corrections.EraBaseStaticOrder` | `0` |
| `Corrections.EraBaseDynamicOrder` | `100` |
| `Corrections.SoDBaseStaticOrder` | `200` |
| `Corrections.SoDBaseDynamicOrder` | `300` |
| `Corrections.TbcBaseStaticOrder` | `400` |
| `Corrections.TbcBaseDynamicOrder` | `500` |
| `Corrections.WotlkBaseStaticOrder` | `600` |
| `Corrections.WotlkBaseDynamicOrder` | `700` |
| `Corrections.CataBaseStaticOrder` | `800` |
| `Corrections.CataBaseDynamicOrder` | `900` |
| `Corrections.MoPBaseStaticOrder` | `1000` |
| `Corrections.MoPBaseDynamicOrder` | `1100` |

Convention: each expansion gets a 100-wide window; files add a small offset inside it
(`+9`, `+10`, `+29`, `+30`, `+49`, `+50`, `+51`, `+60`, `+80`). Auto-generated/derived sets sit
one below the hand-maintained set (`+9` vs `+10`, `+29` vs `+30`, `+49` vs `+50`) so they apply
**first** and hand corrections win.

Registries are **per datatype and per static/dynamic** — 8 independent tables. A load order of
`10` in `ItemCorrectionsStatic` never collides with `10` in `NpcCorrectionsStatic`.

### 1c. Collision detection and resolution

`Corrections.lua:75-81` (dynamic) / `:119-125` (static), byte-identical logic:

```lua
    if Corrections[capitalizedDatatype][loadOrder] then
      local oldLoadOrder = loadOrder
      while Corrections[capitalizedDatatype][loadOrder] do
        loadOrder = loadOrder + 1
      end
      LibQuestieDB.ColorizePrint("yellow", f("Warning: Order index %d already exists for corrections %s, changed to index %d.", oldLoadOrder, name, loadOrder))
    end
```

Linear probe upward until a free integer slot; emits a yellow warning naming both orders.
It never rejects and never overwrites. Consequence: a collision **cascades** — the displaced
entry can take a slot the next registrant wanted, silently reordering things.

### 1d. Corrections held behind functions

Nothing is ever registered as a data table. Every registrant passes a **function** that
*returns* the correction table. The table is only materialised when `correctionObject.func()`
is called during apply (`Generator/env/corrections.lua:52`). Two properties fall out:

1. The multi-MB literal never lives in memory between load and apply.
2. Locals resolved inside the function body (`QuestMeta.questKeys`, `ZoneMeta.zoneIDs`,
   `Enum.raceKeys`, `Corrections.Icons.ICON_TYPE_*`) are read **at apply time**, not load
   time, so the Meta/Enum modules only need to exist by then.

### 1e. Where `wipe()` is called

Every correction file wraps registration in `C_Timer.After(0, function() ... end)` and, as the
last statement of that callback, wipes its own module table. The registry already holds the
function values, so wiping the table that *hosted* them is harmless — it only drops the
`Load`/`LoadFactionFixes` name bindings.

Complete list (21 call sites):

| File | Line | Statement |
| --- | --- | --- |
| `Corrections/Era/classicQuestFixes.lua` | 33 | `QuestFixes = wipe(QuestFixes)` |
| `Corrections/Era/classicNPCFixes.lua` | 27 | `NpcFixes = wipe(NpcFixes)` |
| `Corrections/Era/classicItemFixes.lua` | 26 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Era/classicObjectFixes.lua` | 25 | `ObjectFixes = wipe(ObjectFixes)` |
| `Corrections/Era/static/classicItemQuestStartFixes.lua` | 19 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Era/static/questReputationFixes.lua` | 23 | `QuestFixes = wipe(QuestFixes)` |
| `Corrections/Tbc/tbcQuestFixes.lua` | 32 | `QuestFixes = wipe(QuestFixes)` |
| `Corrections/Tbc/tbcNPCFixes.lua` | 27 | `NpcFixes = wipe(NpcFixes)` |
| `Corrections/Tbc/tbcItemFixes.lua` | 25 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Tbc/tbcObjectFixes.lua` | 25 | `ObjectFixes = wipe(ObjectFixes)` |
| `Corrections/Tbc/static/tbcItemQuestStartFixes.lua` | 20 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Wotlk/wotlkQuestFixes.lua` | 27 | `QuestFixes = wipe(QuestFixes)` |
| `Corrections/Wotlk/wotlkNPCFixes.lua` | 32 | `NpcFixes = wipe(NpcFixes)` |
| `Corrections/Wotlk/wotlkItemFixes.lua` | 26 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Wotlk/wotlkObjectFixes.lua` | 25 | `ObjectFixes = wipe(ObjectFixes)` |
| `Corrections/Wotlk/static/wotlkItemQuestStartFixes.lua` | 20 | `ItemFixes = wipe(ItemFixes)` |
| `Corrections/Sod/base/sodBaseQuests.lua` | 25 | `QuestBase = wipe(QuestBase)` |
| `Corrections/Sod/base/sodBaseNPCs.lua` | 24 | `NpcBase = wipe(NpcBase)` |
| `Corrections/Sod/base/sodBaseObjects.lua` | 24 | `ObjectBase = wipe(ObjectBase)` |
| `Corrections/Sod/base/sodBaseItems.lua` | 24 | `ItemBase = wipe(ItemBase)` |
| `Corrections/Sod/static/sodItemQuestStartFixes.lua` | 22 | `ItemFixes = wipe(ItemFixes)` |

In SoD files the `wipe` sits **outside** the `if LibQuestieDB.IsSoD then` guard — it runs
whether or not registration happened.

`wipe` is stubbed offline at `Generator/env/globals.lua:181` → `_G.wipe = wipeTable`
(`globals.lua:5-10`, nils every key and returns the same table).

---

## 2. `Corrections/Icons.lua` — full quote (72 lines)

File: `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Corrections/Icons.lua`

```lua
---@class LibQuestieDB
local LibQuestieDB = select(2, ...)

--*---- Extend Module --------

---@class Corrections
local Corrections = LibQuestieDB.Corrections

--- This is a manual copy of the Icons from Questie.
--- See https://github.com/Questie/Questie/blob/master/Questie.lua#L208
---@class QuestieIcons
local QuestieLocalTable = {
  ICON_TYPE_SLAY = 1,
  ICON_TYPE_LOOT = 2,
  ICON_TYPE_EVENT = 3,
  ICON_TYPE_OBJECT = 4,
  ICON_TYPE_TALK = 5,
  ICON_TYPE_AVAILABLE = 6,
  ICON_TYPE_AVAILABLE_GRAY = 7,
  ICON_TYPE_COMPLETE = 8,
  ICON_TYPE_GLOW = 9,
  ICON_TYPE_REPEATABLE = 10,
  ICON_TYPE_REPEATABLE_COMPLETE = 11,
  ICON_TYPE_INCOMPLETE = 12,
  ICON_TYPE_EVENTQUEST = 13,
  ICON_TYPE_EVENTQUEST_COMPLETE = 14,
  ICON_TYPE_PVPQUEST = 15,
  ICON_TYPE_PVPQUEST_COMPLETE = 16,
  ICON_TYPE_INTERACT = 17,
  ICON_TYPE_SODRUNE = 18,
  ICON_TYPE_MOUNT_UP = 19,
  ICON_TYPE_NODE_FISH = 20,
  ICON_TYPE_NODE_HERB = 21,
  ICON_TYPE_NODE_ORE = 22,
  ICON_TYPE_CHEST = 23,
}

---@type QuestieIcons
local Icons = setmetatable({}, {
  __index = function(t, k)
    if type(k) ~= "string" then
      return nil -- Only allow string keys
    end

    -- Use rawget to check cache
    local cached = rawget(t, k)
    if cached ~= nil then
      return cached
    end

    -- Try fetching from the Questie global object first
    ---@diagnostic disable-next-line: undefined-global
    if Questie and Questie[k] and type(Questie[k]) == "number" then
      ---@diagnostic disable-next-line: undefined-global
      local valueFromQuestie = Questie[k]
      rawset(t, k, valueFromQuestie) -- Cache the value
      return valueFromQuestie
    end

    -- If not found in Questie, try fetching from QuestieLocalTable
    local valueFromLocalTable = QuestieLocalTable[k]
    if valueFromLocalTable ~= nil then
      rawset(t, k, valueFromLocalTable) -- Cache the value
      return valueFromLocalTable
    end

    -- If not found in either source, return nil
    return nil
  end,
})

Corrections.Icons = Icons
```

Semantics: `Corrections.Icons.ICON_TYPE_X` prefers the live `_G.Questie` table when the
addon is present, else falls back to the hard-coded copy; the result is `rawset`-cached on
first read. In the generator `_G.Questie` is never set (`Generator/env/globals.lua` sets
`_G.QuestieDB` but not `_G.Questie`), so the local table is always used offline.

---

## 3. `Corrections/Enum/*` — every constant

### 3.1 `Enum/Enum.t.lua` (3 lines) — annotations only

```lua
---@meta
---@class LibQuestieDB
---@field Enum Enum
```

### 3.2 `Enum/Npc.lua` (34 lines) — `Enum.npcFlags`

Expansion-conditional via `LibQuestieDB.IsClassic` / `IsWotlk` / `IsCata`.

| Key | Classic | TBC+ |
| --- | --- | --- |
| `NONE` | 0 | 0 |
| `GOSSIP` | 1 | 1 |
| `QUEST_GIVER` | 2 | 2 |
| `VENDOR` | 4 | 128 |
| `FLIGHT_MASTER` | 8 | 8192 |
| `TRAINER` | 16 | 16 |
| `SPIRIT_HEALER` | 32 | 16384 |
| `SPIRIT_GUIDE` | 64 | 32768 |
| `INNKEEPER` | 128 | 65536 |
| `BANKER` | 256 | 131072 |
| `PETITIONER` | 512 | 262144 |
| `TABARD_DESIGNER` | 1024 | 524288 |
| `BATTLEMASTER` | 2048 | 1048576 |
| `AUCTIONEER` | 4096 | 2097152 |
| `STABLEMASTER` | 8192 | 4194304 |
| `REPAIR` | 16384 | 4096 |
| `BARBER` | `(IsWotlk or IsCata) and 16777216 or nil` | |
| `ARCANE_REFORGER` | `IsCata and 134217728 or nil` | |
| `TRANSMOGRIFIER` | `IsCata and 268435456 or nil` | |

### 3.3 `Enum/Flags.lua` (64 lines) — THREE tables, one is misplaced

- **`LibQuestieDB.npcFlags`** (`Flags.lua:16`) — note: assigned to `LibQuestieDB`, **not**
  `Enum`. A near-duplicate of `Enum.npcFlags` from `Enum/Npc.lua`, differing only in that
  `BARBER`/`ARCANE_REFORGER`/`TRANSMOGRIFIER` are gated by `Expansions.Current >= Expansions.Wotlk`
  / `>= Expansions.Cata` instead of the `Is*` booleans. Same numeric values throughout.
  **Dead — no correction file references `LibQuestieDB.npcFlags`.** Do not port both.
- **`Enum.questFlags`** (`Flags.lua:42`):
  `NONE=0, STAY_ALIVE=1, PARTY_ACCEPT=2, EXPLORATION=4, SHARABLE=8, UNUSED1=16, EPIC=32,
  RAID=64, UNUSED2=128, UNKNOWN=256, HIDDEN_REWARDS=512, AUTO_REWARDED=1024, DAILY=4096,
  WEEKLY=32768`
- **`Enum.specialFlags`** (`Flags.lua:61`): `NONE=0, REPEATABLE=1`

Load-order hazard: `Enum/Npc.lua` is loaded **after** `Enum/Flags.lua` in
`Generator/env/module_loader.lua` CORE_FILES, so `Enum.npcFlags` ends up being the `Npc.lua`
version. Correction files use `Enum.npcFlags`.

### 3.4 `Enum/Item.lua` (88 lines) — `Enum.itemClasses`

```lua
Enum.itemClasses = {
  QUEST = 12,
}
```
Exactly one constant. Lines 14-88 are a comment block documenting all class/subClass pairs.

### 3.5 `Enum/Player.lua` (223 lines) — `Enum.classKeys`, `Enum.raceKeys`

`Enum.classKeys` (bitmask `2^(ChrClasses.ID-1)`):

```
NONE=0, WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, DEATH_KNIGHT=32,
SHAMAN=64, MAGE=128, WARLOCK=256, MONK=512, DRUID=1024
```

`Enum.raceKeys` (bitmask `2^PlayableRaceBit`):

```
NONE=0, HUMAN=1, ORC=2, DWARF=4, NIGHT_ELF=8, UNDEAD=16, TAUREN=32, GNOME=64,
TROLL=128, GOBLIN=256, BLOOD_ELF=512, DRAENEI=1024, WORGEN=2097152,
PANDAREN_NEUTRAL=8388608, PANDAREN_ALLIANCE=16777216, PANDAREN_HORDE=33554432
```

plus two IIFE-computed, expansion-dependent aggregates (`Player.lua:38-66`):

| | Classic | TBC/Wotlk | Cata | MoP | fallback |
| --- | --- | --- | --- | --- | --- |
| `ALL_ALLIANCE` | 77 | 1101 | 2098253 | 18875469 | 77 + `print("Unknown expansion for ALL_ALLIANCE")` |
| `ALL_HORDE` | 178 | 690 | 946 | 33555378 | 178 + `print("Unknown expansion for ALL_HORDE")` |

Lines 88-224 are commented-out alternate implementations; ignore.

### 3.6 `Enum/Profession.lua` (92 lines)

`Enum.professionKeys` (skillIDs):
```
FIRST_AID=129, BLACKSMITHING=164, LEATHERWORKING=165, ALCHEMY=171, HERBALISM=182,
COOKING=185, MINING=186, TAILORING=197, ENGINEERING=202, ENCHANTING=333, FISHING=356,
SKINNING=393, JEWELCRAFTING=755, RIDING=762, INSCRIPTION=773, ARCHAEOLOGY=794
```

`Enum.specializationKeys` (spellIDs, except the plain-profession aliases):
```
ALCHEMY=171, ALCHEMY_ELIXIR=28677, ALCHEMY_POTION=28675, ALCHEMY_TRANSMUTATION=28672,
BLACKSMITHING=164, BLACKSMITHING_ARMOR=9788, BLACKSMITHING_WEAPON=9787,
BLACKSMITHING_WEAPON_AXE=17041, BLACKSMITHING_WEAPON_HAMMER=17040,
BLACKSMITHING_WEAPON_SWORD=17039, ENGINEERING=202, ENGINEERING_GNOMISH=20219,
ENGINEERING_GOBLIN=20222, LEATHERWORKING=165, LEATHERWORKING_DRAGONSCALE=10656,
LEATHERWORKING_ELEMENTAL=10658, LEATHERWORKING_TRIBAL=10660, TAILORING=197,
TAILORING_MOONCLOTH=26798, TAILORING_SHADOWEAVE=26801, TAILORING_SPELLFIRE=26797
```

Both tables are declared auto-generated from CSV, with empty `professionKeysOverride` /
`specializationKeysOverride` tables merged in at the bottom (`Profession.lua:85-92`).

### 3.7 `Enum/Sort.lua` (93 lines) — `Enum.sortKeys` (values for `questKeys.zoneOrSort`)

```
EPIC=-1, HALLOWS_END=-21, SEASONAL=-22, CATACLYSM=-23, HERBALISM=-24, BATTLEGROUND=-25,
DAY_OF_THE_DEAD=-41, WARLOCK=-61, WARRIOR=-81, SHAMAN=-82, FISHING=-101,
BLACKSMITHING=-121, PALADIN=-141, MAGE=-161, ROGUE=-162, ALCHEMY=-181,
LEATHERWORKING=-182, ENGINEERING=-201, TREASURE_MAP=-221, TOURNAMENT=-241, HUNTER=-261,
PRIEST=-262, DRUID=-263, TAILORING=-264, SPECIAL=-284, COOKING=-304, FIRST_AID=-324,
LEGENDARY=-344, DARKMOON_FAIRE=-364, AHNQIRAJ_WAR=-365, LUNAR_FESTIVAL=-366,
REPUTATION=-367, INVASION=-368, MIDSUMMER=-369, BREWFEST=-370, INSCRIPTION=-371,
DEATH_KNIGHT=-372, JEWELCRAFTING=-373, NOBLEGARDEN=-374, PILGRIMS_BOUNTY=-375,
LOVE_IS_IN_THE_AIR=-376, ARCHAEOLOGY=-377, CHILDRENS_WEEK=-378, FIRELANDS_INVASION=-379,
THE_ZANDALARI=-380, ELEMENTAL_BONDS=-381, PANDAREN_BREWMASTERS=-391, SCENARIO=-392,
BATTLE_PETS=-394, MONK=-395, LANDFALL=-396, PANDAREN_CAMPAIGN=-397, RIDING=-398,
BRAWLERS_GUILD=-399, PROVING_GROUNDS=-400
```

Plus a **non-empty** override table merged at `Sort.lua:91-93` (dummy IDs for professions
without a real QuestSort):
```
MINING=-667, ENCHANTING=-668, SKINNING=-666
```

### 3.8 `Enum/Waypoints.lua` (17 lines) — `Enum.waypointPresets`

Three keys, each a `{ [ZoneMeta.zoneIDs.X] = { { {x,y}, ... } } }` polyline:
`ORGRIMS_HAMMER` (ICECROWN), `THE_SKYBREAKER` (ICECROWN), `ALLIANCE_GUNSHIP` (DEEPHOLM).
Currently referenced nowhere in the correction files (`waypointPresets` appears only as a
commented-out local in `Corrections/Era/classicNPCFixes.lua:37`). Duplicated verbatim as a
commented-out `NpcMeta.waypointPresets` at `Meta/NpcMeta.lua:105-109`.

### 3.9 `Enum/Factions.lua` (162 lines) — `Enum.factions`

One override merged at the end (`Factions.lua:12-19`, `:117-120`):
```lua
WILDHAMMER_CLAN = Expansions.Current >= Expansions.Cata and 1174 or 471,
```
(Blizzard reuses the name; pre-Cata it is The Hinterlands' 471.)

Full generated table (from `wago.tools/db2/Faction/csv?build=5.5.0.60700`):

```
BOOTY_BAY=21, IRONFORGE=47, GNOMEREGAN=54, THORIUM_BROTHERHOOD=59, UNDERCITY=68,
DARNASSUS=69, SYNDICATE=70, STORMWIND=72, ORGRIMMAR=76, THUNDER_BLUFF=81,
BLOODSAIL_BUCCANEERS=87, GELKIS_CLAN_CENTAUR=92, MAGRAM_CLAN_CENTAUR=93,
ZANDALAR_TRIBE=270, RAVENHOLDT=349, GADGETZAN=369, RATCHET=470,
DEPRECATED_WILDHAMMER_CLAN_DEPRECATED=471, THE_LEAGUE_OF_ARATHOR=509, THE_DEFILERS=510,
ARGENT_DAWN=529, DARKSPEAR_TROLLS=530, TIMBERMAW_HOLD=576, EVERLOOK=577,
WINTERSABER_TRAINERS=589, CENARION_CIRCLE=609, FROSTWOLF_CLAN=729, STORMPIKE_GUARD=730,
HYDRAXIAN_WATERLORDS=749, SHENDRALAR=809, WARSONG_OUTRIDERS=889, SILVERWING_SENTINELS=890,
DARKMOON_FAIRE=909, BROOD_OF_NOZDORMU=910, SILVERMOON_CITY=911, TRANQUILLIEN=922,
EXODAR=930, THE_ALDOR=932, THE_CONSORTIUM=933, THE_SCRYERS=934, THE_SHATAR=935,
THE_MAGHAR=941, CENARION_EXPEDITION=942, HONOR_HOLD=946, THRALLMAR=947, THE_VIOLET_EYE=967,
SPOREGGAR=970, KURENAI=978, KEEPERS_OF_TIME=989, THE_SCALE_OF_THE_SANDS=990, LOWER_CITY=1011,
ASHTONGUE_DEATHSWORN=1012, NETHERWING=1015, SHATARI_SKYGUARD=1031, ALLIANCE_VANGUARD=1037,
OGRILA=1038, VALIANCE_EXPEDITION=1050, HORDE_EXPEDITION=1052, THE_TAUNKA=1064,
THE_HAND_OF_VENGEANCE=1067, EXPLORERS_LEAGUE=1068, THE_KALUAK=1073,
SHATTERED_SUN_OFFENSIVE=1077, WARSONG_OFFENSIVE=1085, KIRIN_TOR=1090,
THE_WYRMREST_ACCORD=1091, THE_SILVER_COVENANT=1094, FRENZYHEART_TRIBE=1104, THE_ORACLES=1105,
ARGENT_CRUSADE=1106, THE_SONS_OF_HODIR=1119, THE_SUNREAVERS=1124, THE_FROSTBORN=1126,
BILGEWATER_CARTEL=1133, GILNEAS=1134, THE_EARTHEN_RING=1135, THE_ASHEN_VERDICT=1156,
GUARDIANS_OF_HYJAL=1158, GUILD=1168, THERAZANE=1171, DRAGONMAW_CLAN=1172, RAMKAHEN=1173,
WILDHAMMER_CLAN=1174, BARADINS_WARDENS=1177, HELLSCREAMS_REACH=1178, AVENGERS_OF_HYJAL=1204,
SHANG_XIS_ACADEMY=1216, FOREST_HOZEN=1228, PEARLFIN_JINYU=1242, HOZEN=1243, GOLDEN_LOTUS=1269,
SHADO_PAN=1270, ORDER_OF_THE_CLOUD_SERPENT=1271, THE_TILLERS=1272, JOGU_THE_DRUNK=1273,
ELLA=1275, OLD_HILLPAW=1276, CHEE_CHEE=1277, SHO=1278, HAOHAN_MUDCLAW=1279, TINA_MUDCLAW=1280,
GINA_MUDCLAW=1281, FISH_FELLREED=1282, FARMER_FUNG=1283, THE_ANGLERS=1302, THE_KLAXXI=1337,
THE_AUGUST_CELESTIALS=1341, THE_LOREWALKERS=1345, THE_BREWMASTERS=1351, HUOJIN_PANDAREN=1352,
TUSHUI_PANDAREN=1353, NOMI=1357, NAT_PAGLE=1358, THE_BLACK_PRINCE=1359, BRAWLGAR_ARENA=1374,
DOMINANCE_OFFENSIVE=1375, OPERATION_SHIELDWALL=1376, KIRIN_TOR_OFFENSIVE=1387,
SUNREAVER_ONSLAUGHT=1388, AKAMAS_TRUST=1416, BIZMOS_BRAWLPUB=1419, SHADO_PAN_ASSAULT=1435,
DARKSPEAR_REBELLION=1440, EMPEROR_SHAOHAO=1492
```

`Enum/.generate/` holds the Python generators (`functions.py`, `data_Faction.py`,
`data_Sort.py`, `data_Profession.py`) — not Lua, not loaded.

### 3.10 Which key namespaces the correction files actually reference

`grep -rhoE "<x>Keys\.[A-Za-z]+" Corrections/` over all correction files:

- `questKeys.*` (30 distinct): `childQuests, exclusiveTo, extraObjectives, finishedBy,
  inGroupWith, name, nextQuestInChain, objectives, objectivesText, parentQuest,
  preQuestGroup, preQuestSingle, questFlags, questLevel, reputationReward, requiredClasses,
  requiredLevel, requiredMaxLevel, requiredMaxRep, requiredMinRep, requiredRaces,
  requiredSkill, requiredSourceItems, requiredSpecialization, requiredSpell, sourceItemId,
  specialFlags, startedBy, triggerEnd, zoneOrSort`
- `itemKeys.*` (14): `ammoType, class, flags, itemDrops, itemLevel, name, npcDrops,
  objectDrops, questRewards, relatedQuests, requiredLevel, startQuest, subClass, vendors`
- `npcKeys.*` (14): `factionID, friendlyToFaction, maxLevel, maxLevelHealth, minLevel,
  minLevelHealth, name, npcFlags, questEnds, questStarts, spawns, subName, waypoints, zoneID`
- `objectKeys.*` (6): `factionID, name, questEnds, questStarts, spawns, zoneID`
- `zoneIDs.*`: **174 distinct constants** (see §7 gotcha).
- `Enum` namespaces used: `Enum.raceKeys`, `Enum.classKeys`, `Enum.sortKeys`,
  `Enum.professionKeys`, `Enum.specializationKeys`, `Enum.npcFlags`, `Enum.itemClasses`.
  Never used: `Enum.questFlags`, `Enum.specialFlags`, `Enum.factions`, `Enum.waypointPresets`,
  `LibQuestieDB.npcFlags` — those are referenced only by *numeric literal* today.

---

## 4. Every correction file — register call, load order, static/dynamic, size

`entries~` = count of top-level `[<id>] = {` lines (approximate; includes both the main and the
faction sub-tables). `bytes` = file size on disk.

### Era — `Corrections/Era/`

| File | Lines | bytes | entries~ | Register call | loadOrder expr | value | S/D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `static/questReputationFixes.lua` | 12797 | 312582 | 4254 | `RegisterCorrectionStatic("quest", "QuestFixes-Reputation-Era", QuestFixes.LoadQuestReputationFixes, ...)` @ L16 | `EraBaseStaticOrder + 9` | **9** | STATIC |
| `static/classicItemQuestStartFixes.lua` | 1079 | 46519 | 210 | `RegisterCorrectionStatic("item", "ItemFixes-QuestStarts-Era-Automatic", ItemFixes.LoadItemQuestStarts, ...)` @ L13 | `EraBaseStaticOrder + 9` | **9** | STATIC |
| `classicItemFixes.lua` | 1396 | 38131 | 334 | `RegisterCorrectionStatic("item", "ItemFixes-Era", ItemFixes.Load, ...)` @ L15 | `EraBaseStaticOrder + 10` | **10** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("item", "ItemFixes-Faction-Era", ItemFixes.LoadFactionFixes, ...)` @ L20 | `EraBaseDynamicOrder + 20` | **120** | DYNAMIC |
| `classicNPCFixes.lua` | 2729 | 206570 | 689 | `RegisterCorrectionStatic("npc", "NpcFixes-Era", NpcFixes.Load, ...)` @ L16 | `EraBaseStaticOrder + 10` | **10** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("npc", "NpcFixes-Faction-Era", NpcFixes.LoadFactionFixes, ...)` @ L21 | `EraBaseDynamicOrder + 20` | **120** | DYNAMIC |
| `classicObjectFixes.lua` | 417 | 56493 | 92 | `RegisterCorrectionStatic("object", "ObjectFixes-Era", ObjectFixes.Load, ...)` @ L14 | `EraBaseStaticOrder + 10` | **10** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("object", "ObjectFixes-Faction-Era", ObjectFixes.LoadFactionFixes, ...)` @ L19 | `EraBaseDynamicOrder + 20` | **120** | DYNAMIC |
| `classicQuestFixes.lua` | 4177 | 142565 | 1178 | `RegisterCorrectionStatic("quest", "QuestFixes-Era", QuestFixes.Load, ...)` @ L22 | `EraBaseStaticOrder + 10` | **10** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("quest", "QuestFixes-Faction-Era", QuestFixes.LoadFactionFixes, ...)` @ L27 | `EraBaseDynamicOrder + 20` | **120** | DYNAMIC |

`questReputationFixes.lua` is the only conditional Era registration:

```lua
C_Timer.After(0, function()
  if Expansions.Current < Expansions.Cata then
    Corrections.RegisterCorrectionStatic("quest",
                                         "QuestFixes-Reputation-Era",
                                         QuestFixes.LoadQuestReputationFixes,
                                         Corrections.EraBaseStaticOrder + 9)
  end
  ...
```

Note **`9` is used twice in the Era window** — but for different datatypes
(`quest` vs `item`), so the two registries never collide.

### Tbc — `Corrections/Tbc/`

| File | Lines | bytes | entries~ | Register call | loadOrder expr | value | S/D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `static/tbcItemQuestStartFixes.lua` | 450 | 17730 | 84 | `RegisterCorrectionStatic("item", "ItemFixes-QuestStarts-Tbc-Automatic", ItemFixes.LoadItemQuestStarts, ...)` @ L14 | `TbcBaseStaticOrder + 29` | **429** | STATIC |
| `tbcItemFixes.lua` | 551 | 12301 | 160 | `RegisterCorrectionStatic("item", "ItemFixes-Tbc", ItemFixes.Load, ...)` @ L14 | `TbcBaseStaticOrder + 30` | **430** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("item", "ItemFixes-Faction-Tbc", ItemFixes.LoadFactionFixes, ...)` @ L19 | `TbcBaseDynamicOrder + 40` | **540** | DYNAMIC |
| `tbcNPCFixes.lua` | 1106 | 73186 | 284 | `RegisterCorrectionStatic("npc", "NpcFixes-Tbc", NpcFixes.Load, ...)` @ L16 | `TbcBaseStaticOrder + 30` | **430** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("npc", "NpcFixes-Faction-Tbc", NpcFixes.LoadFactionFixes, ...)` @ L21 | `TbcBaseDynamicOrder + 40` | **540** | DYNAMIC |
| `tbcObjectFixes.lua` | 750 | 32969 | 167 | `RegisterCorrectionStatic("object", "ObjectFixes-Tbc", ObjectFixes.Load, ...)` @ L14 | `TbcBaseStaticOrder + 30` | **430** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("object", "ObjectFixes-Faction-Tbc", ObjectFixes.LoadFactionFixes, ...)` @ L19 | `TbcBaseDynamicOrder + 40` | **540** | DYNAMIC |
| `tbcQuestFixes.lua` | 5405 | 214538 | 1204 | `RegisterCorrectionStatic("quest", "QuestFixes-Tbc", QuestFixes.Load, ...)` @ L21 | `TbcBaseStaticOrder + 30` | **430** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("quest", "QuestFixes-Faction-Tbc", QuestFixes.LoadFactionFixes, ...)` @ L26 | **`TbcBaseStaticOrder + 40`** ← bug | **440** | DYNAMIC |

### Wotlk — `Corrections/Wotlk/`

| File | Lines | bytes | entries~ | Register call | loadOrder expr | value | S/D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `static/wotlkItemQuestStartFixes.lua` | 440 | 18245 | 82 | `RegisterCorrectionStatic("item", "ItemFixes-QuestStarts-Wotlk-Automatic", ItemFixes.LoadItemQuestStarts, ...)` @ L14 | `WotlkBaseStaticOrder + 49` | **649** | STATIC |
| `wotlkItemFixes.lua` | 790 | 41250 | 230 | `RegisterCorrectionStatic("item", "ItemFixes-Wotlk", ItemFixes.Load, ...)` @ L15 | `WotlkBaseStaticOrder + 50` | **650** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("item", "ItemFixes-Faction-Wotlk", ItemFixes.LoadFactionFixes, ...)` @ L20 | `WotlkBaseDynamicOrder + 60` | **760** | DYNAMIC |
| `wotlkNPCFixes.lua` | 3395 | 202187 | 770 | `RegisterCorrectionStatic("npc", "NpcFixes-Wotlk", NpcFixes.Load, ...)` @ L16 | `WotlkBaseStaticOrder + 51` | **651** | STATIC |
| ” | | | | `RegisterCorrectionStatic("npc", "NpcFixes-Spawns-Wotlk-Automatic", NpcFixes.LoadSpawnFixes, ...)` @ L21 | `WotlkBaseStaticOrder + 50` | **650** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("npc", "NpcFixes-FactionWotlk", NpcFixes.LoadFactionFixes, ...)` @ L26 | `WotlkBaseDynamicOrder + 60` | **760** | DYNAMIC |
| `wotlkObjectFixes.lua` | 868 | 61812 | 172 | `RegisterCorrectionStatic("object", "ObjectFixes-Wotlk", ObjectFixes.Load, ...)` @ L14 | `WotlkBaseStaticOrder + 50` | **650** | STATIC |
| ” | | | | `RegisterCorrectionDynamic("object", "ObjectFixes-Faction-Wotlk", ObjectFixes.LoadFactionFixes, ...)` @ L19 | `WotlkBaseDynamicOrder + 60` | **760** | DYNAMIC |
| `wotlkQuestFixes.lua` | 7112 | 309943 | 1569 | `RegisterCorrectionStatic("quest", "QuestFixes-Wotlk", QuestFixes.Load, ...)` @ L21 | `WotlkBaseStaticOrder + 50` | **650** | STATIC |

`wotlkQuestFixes.lua` registers **only** static — it has no `LoadFactionFixes` function at all.
`wotlkNPCFixes.lua` is the only file registering two statics for one datatype; the
auto-generated spawn set is deliberately at 650, one *below* the hand set at 651.

### Sod — `Corrections/Sod/`

Every SoD registration is wrapped in `if LibQuestieDB.IsSoD then ... end`.

| File | Lines | bytes | entries~ | Register call | loadOrder expr | value | S/D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `base/sodBaseItems.lua` | 16829 | 646169 | 2099 | `RegisterCorrectionDynamic("item", "Item-Base-Sod", ItemBase.LoadBaseItems, ...)` @ L17 | **literal `70`** | **70** | DYNAMIC |
| `base/sodBaseNPCs.lua` | 10079 | 427428 | 900 | `RegisterCorrectionDynamic("npc", "Npc-Base-Sod", NpcBase.LoadBaseNPCs, ...)` @ L17 | **literal `70`** | **70** | DYNAMIC |
| `base/sodBaseObjects.lua` | 2195 | 66004 | 258 | `RegisterCorrectionDynamic("object", "Object-Base-Sod", ObjectBase.LoadBaseObjects, ...)` @ L17 | **literal `70`** | **70** | DYNAMIC |
| `base/sodBaseQuests.lua` | 4858 | 245024 | 438 | `RegisterCorrectionDynamic("quest", "Quest-Base-Sod", QuestBase.LoadBaseQuests, ...)` @ L18 | **literal `70`** | **70** | DYNAMIC |
| `static/sodItemQuestStartFixes.lua` | 142 | 5756 | 22 | `RegisterCorrectionDynamic("item", "ItemFixes-QuestStarts-Sod-Automatic", ItemFixes.LoadItemQuestStarts, ...)` @ L15 | `SoDBaseDynamicOrder + 80` | **380** | **DYNAMIC** (in a `static/` folder) |

### 4a. Resulting effective apply order per registry

| Registry | Sorted (loadOrder → name) |
| --- | --- |
| `ItemCorrectionsStatic` | 9 QuestStarts-Era → 10 ItemFixes-Era → 429 QuestStarts-Tbc → 430 ItemFixes-Tbc → 649 QuestStarts-Wotlk → 650 ItemFixes-Wotlk |
| `ItemCorrectionsDynamic` | **70 Item-Base-Sod** → 120 Faction-Era → 380 QuestStarts-Sod → 540 Faction-Tbc → 760 Faction-Wotlk |
| `NpcCorrectionsStatic` | 10 Era → 430 Tbc → 650 Spawns-Wotlk-Automatic → 651 Wotlk |
| `NpcCorrectionsDynamic` | **70 Npc-Base-Sod** → 120 Faction-Era → 540 Faction-Tbc → 760 Faction-Wotlk |
| `ObjectCorrectionsStatic` | 10 Era → 430 Tbc → 650 Wotlk |
| `ObjectCorrectionsDynamic` | **70 Object-Base-Sod** → 120 Faction-Era → 540 Faction-Tbc → 760 Faction-Wotlk |
| `QuestCorrectionsStatic` | 9 Reputation-Era (conditional) → 10 Era → 430 Tbc → 650 Wotlk |
| `QuestCorrectionsDynamic` | **70 Quest-Base-Sod** → 120 Faction-Era → **440 Faction-Tbc** |

No two entries in any single registry share a load order, so the collision-probe path
(`Corrections.lua:75-81` / `:119-125`) is **never exercised in the shipped data**.

---

## 5. The two known defects — verified, with quoted lines

### Defect A — `Sod/base/*.lua` passes literal `70` instead of `SoDBaseDynamicOrder` (300)

`Corrections/Sod/base/sodBaseItems.lua:13-25` (the other three are structurally identical):

```lua
--? This is the "static" database for SOD, out of ALL SoD fixes it should always load first.
--? SoD as "expansion" should ALWAYS load last.
C_Timer.After(0, function()
  if LibQuestieDB.IsSoD then
    Corrections.RegisterCorrectionDynamic("item",
                                          "Item-Base-Sod",
                                          ItemBase.LoadBaseItems,
                                          70) -- The idea here is that Sod will always load last.
  end

  -- Clear the table to save memory
  ItemBase = wipe(ItemBase)
end)
```

Exact offending lines:

- `Corrections/Sod/base/sodBaseItems.lua:20`   → `                                          70) -- The idea here is that Sod will always load last.`
- `Corrections/Sod/base/sodBaseNPCs.lua:20`    → same text
- `Corrections/Sod/base/sodBaseObjects.lua:20` → same text
- `Corrections/Sod/base/sodBaseQuests.lua:21`  → same text

The comment on lines 13-15 of each file says "SoD … should ALWAYS load last", and the inline
comment says "Sod will always load last". **70 is the lowest dynamic order in the whole
system**, so SoD base data applies **first**, before Era faction fixes (120), Tbc (440/540)
and Wotlk (760). The intended constant is `Corrections.SoDBaseDynamicOrder` = **300**, which
would still put SoD before Tbc/Wotlk — so even the constant does not deliver "load last".
The two SoD-window constants are `SoDBaseStaticOrder = 200` and `SoDBaseDynamicOrder = 300`;
they sit *between* Era (0/100) and Tbc (400/500), i.e. the namespace layout itself encodes
"SoD after Era, before TBC", contradicting the comments.

### Defect B — `Sod/static/sodItemQuestStartFixes.lua` is dynamic despite the folder name

`Corrections/Sod/static/sodItemQuestStartFixes.lua:13-23`:

```lua
C_Timer.After(0, function()
  if LibQuestieDB.IsSoD then
    Corrections.RegisterCorrectionDynamic("item",
                                          "ItemFixes-QuestStarts-Sod-Automatic",
                                          ItemFixes.LoadItemQuestStarts,
                                          Corrections.SoDBaseDynamicOrder + 80)
  end

  -- Clear the table to save memory
  ItemFixes = wipe(ItemFixes)
end)
```

Contrast the identically-named files in the sibling `static/` folders, which all use
`RegisterCorrectionStatic`:
`Era/static/classicItemQuestStartFixes.lua:13`, `Tbc/static/tbcItemQuestStartFixes.lua:14`,
`Wotlk/static/wotlkItemQuestStartFixes.lua:14`, `Era/static/questReputationFixes.lua:16`.

**Folder name is not a category signal.** The registration call is the only authority.

### Defect C (additional, not in the brief) — `tbcQuestFixes.lua` uses the wrong base constant

`Corrections/Tbc/tbcQuestFixes.lua:20-33`:

```lua
C_Timer.After(0, function()
  Corrections.RegisterCorrectionStatic("quest",
                                       "QuestFixes-Tbc",
                                       QuestFixes.Load,
                                       Corrections.TbcBaseStaticOrder + 30)

  Corrections.RegisterCorrectionDynamic("quest",
                                        "QuestFixes-Faction-Tbc",
                                        QuestFixes.LoadFactionFixes,
                                        Corrections.TbcBaseStaticOrder + 40)   -- <-- Static, not Dynamic

  -- Clear the table to save memory
  QuestFixes = wipe(QuestFixes)
end)
```

Line 29 uses `TbcBaseStaticOrder + 40` = **440** for a *dynamic* registration; every sibling
uses `TbcBaseDynamicOrder + 40` = 540 (`tbcItemFixes.lua:22`, `tbcNPCFixes.lua:24`,
`tbcObjectFixes.lua:22`). No observable misorder today (440 still sorts after Era's 120), but
it lands in the SoD/Tbc boundary region and would collide if a `TbcBaseStaticOrder+40`
dynamic quest correction were ever added elsewhere.

---

## 6. Generator — exact apply pipeline

Files:
- `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Generator/main.lua` (87 lines)
- `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Generator/createStatic.lua` (236 lines)
- `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Generator/env/corrections.lua` (61 lines)
- `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Generator/env/init.lua`, `globals.lua`, `module_loader.lua`, `version.lua`
- `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Generator/data_loaders/{item,npc,object,quest}.lua`

### 6.1 `Generator/env/corrections.lua` — full quote

```lua
local M = {}

local function mergeCorrectionData(data, metaKeys, correctionData)
  local applied = 0

  for id, fields in pairs(correctionData) do
    local entry = data[id]
    if not entry then
      entry = {}
      data[id] = entry
    end

    for key, value in pairs(fields) do
      local index = type(key) == "number" and key or metaKeys[key]
      assert(index, "Unknown correction key: " .. tostring(key))

      if type(value) == "table" and next(value) == nil then
        entry[index] = "nil"
      else
        entry[index] = value
      end
      applied = applied + 1
    end
  end

  return applied
end

function M.attach(lib)
  ---Apply registered corrections directly to a raw source table.
  ---@param datatype "item"|"npc"|"object"|"quest"
  ---@param data table<number, table<number, any>>
  ---@param metaKeys table<string, number>
  ---@param includeStatic boolean?
  ---@param includeDynamic boolean?
  ---@return table<number, table<number, any>>, number
  function lib.ApplyCorrections(datatype, data, metaKeys, includeStatic, includeDynamic)
    if includeStatic == nil then
      includeStatic = true
    end
    if includeDynamic == nil then
      includeDynamic = false
    end

    local allCorrections, order = lib.Corrections.GetCorrections(datatype, includeStatic, includeDynamic)
    local applied = 0

    for _, correctionType in ipairs(order) do
      local correctionList = allCorrections[correctionType]
      if correctionList then
        for _, correctionObject in ipairs(correctionList) do
          applied = applied + mergeCorrectionData(data, metaKeys, correctionObject.func() or {})
        end
      end
    end

    return data, applied
  end
end

return M
```

### 6.2 Order of operations, end to end

1. **`main.lua:1-47`** — bootstraps `package.path` (project dir, `Generator/`, `.tooling/lua/`),
   `lfs.chdir` to project root, asserts `IMPLEMENTATION_PLAN.md` / `Generator/` markers exist.
2. **`main.lua:52-62`** — sets `Is_CLI = true`, `CLI_addonName = "QuestieDB"`,
   `CLI_addonTable = {}`, `DB_GEN_DEBUG_MODE = false`, `DB_C_TIMER_DEBUG = true`, then
   `require(".createStatic")` (which sets `Is_Create_Static = true` at `createStatic.lua:22`).
3. **`main.lua:75-79`** — loops `helpers.Expansions` and calls
   `DumpDatabase(Capitalized(localPrefix), questiePrefix, DB_GEN_DEBUG_MODE)`.
   `helpers.Expansions` (`Generator/db_helpers.lua:5-28`) is exactly:
   `{"Classic","era"}, {"TBC","tbc"}, {"Wotlk","wotlk"}, {"Cata","cata"}, {"MoP","mop"}` —
   **there is no `Sod` entry**, so SoD is never generated.
4. **`createStatic.lua:59-72`** — `DumpDatabase(questiedb_version, questie_version, debug)`;
   `LibQuestieDBTable = env.create(capitalizedQuestieDBVersion)`.
5. **`env/init.lua:8-21`** — `M.create(versionName)`:
   1. `version.get(versionName)` → `{wowProjectId, seasonId, locale}` (`env/version.lua:10-41`;
      `Sod` maps to `WOW_PROJECT_CLASSIC` + `seasonId = 2`, but is unreachable per step 3).
   2. `globals.setup(versionConfig)` — installs the WoW API surface (details in §6.3).
   3. `globals.createNamespace()` — a table whose `__index` **auto-vivifies** `{}` on any miss
      and `rawset`s it. This is why `LibQuestieDB.Corrections`, `.Meta`, `.Enum`,
      `.Expansions` all exist before their defining files run.
   4. `module_loader.load(lib, versionName)`.
   5. `corrections.attach(lib)` — defines `lib.ApplyCorrections`.
6. **`env/module_loader.lua:112-125`** — loads `CORE_FILES` in this exact order, then
   `VERSION_FILES[versionName]`:

   ```
   Helpers/Helpers.lua, Helpers/VersionCheck.lua, Helpers/Expansions.lua,
   Meta/DumpFunctions.lua, Meta/Meta.lua, Meta/ZoneMeta.lua, Meta/ItemMeta.lua,
   Meta/NpcMeta.lua, Meta/ObjectMeta.lua, Meta/QuestMeta.lua, Meta/L10nMeta.lua,
   Corrections/Corrections.lua, Corrections/Icons.lua,
   Corrections/Enum/Factions.lua, Corrections/Enum/Flags.lua, Corrections/Enum/Npc.lua,
   Corrections/Enum/Item.lua, Corrections/Enum/Player.lua, Corrections/Enum/Profession.lua,
   Corrections/Enum/Sort.lua, Corrections/Enum/Waypoints.lua
   ```

   `VERSION_FILES` (`module_loader.lua:30-62`):

   | Version | Files |
   | --- | --- |
   | `Era` | `Corrections/Era/static/classicItemQuestStartFixes.lua`, `Corrections/Era/static/questReputationFixes.lua`, `Corrections/Era/classicItemFixes.lua`, `Corrections/Era/classicNPCFixes.lua`, `Corrections/Era/classicObjectFixes.lua`, `Corrections/Era/classicQuestFixes.lua` |
   | `Sod` | `Corrections/Sod/base/sodBaseItems.lua`, `.../sodBaseNPCs.lua`, `.../sodBaseObjects.lua`, `.../sodBaseQuests.lua`, `Corrections/Sod/static/sodItemQuestStartFixes.lua` |
   | `Tbc` | `Corrections/Tbc/static/tbcItemQuestStartFixes.lua`, `Corrections/Tbc/tbcItemFixes.lua`, `.../tbcNPCFixes.lua`, `.../tbcObjectFixes.lua`, `.../tbcQuestFixes.lua` |
   | `Wotlk` | `Corrections/Wotlk/static/wotlkItemQuestStartFixes.lua`, `.../wotlkItemFixes.lua`, `.../wotlkNPCFixes.lua`, `.../wotlkObjectFixes.lua`, `.../wotlkQuestFixes.lua` |
   | `Cata` | `{}` |
   | `Mop` | `{}` |

   Each file is loaded via `loadfile(abs)` then `pcall(chunk, "QuestieDB", lib)` — so the
   file's `select(2, ...)` is `lib`. **After every file**, `globals.flushPendingTimers()` runs,
   which drains `_G.__QUESTIEDB_PENDING_TIMERS` — i.e. the `C_Timer.After(0, ...)` registration
   block executes immediately after its own file finishes loading. Registration order therefore
   equals file order, but the *apply* order is governed purely by `loadOrder`.

   Version files are **not cumulative** — a `Tbc` run loads only Tbc corrections, never Era's.
   `Cata`/`Mop` runs apply **zero** corrections.
7. **`createStatic.lua:81`** — `Meta.DumpFunctions.testDumpFunctions()` self-test.
8. **`createStatic.lua:112-124`** — the four data loaders run, one per entity type.
   Each (`Generator/data_loaders/item.lua:16-45` and siblings):
   1. `FindFile(f("%sItemDB.lua", lowerQuestieVersion), nil, {}, helpers.get_script_dir())`
      where `lowerQuestieVersion = questie_version:lower()` → `classic`/`tbc`/`wotlk`/`cata`/`mop`.
   2. `CLI_Helpers.loadFile(file)` → populates `QuestieDB.itemData` (a *string*).
   3. `itemOverride = loadstring(QuestieDB.itemData)()` → raw base table.
   4. ```lua
      local _, appliedCorrections = LibQuestieDBTable.ApplyCorrections(
        "item", itemOverride, Meta.ItemMeta.itemKeys, true, false)
      ```
      i.e. **`includeStatic = true`, `includeDynamic = false`** for all four types.
   5. `if appliedCorrections > 0 then assert(next(itemOverride), ...) end`.
9. **`ApplyCorrections`** → `GetCorrections(datatype, true, false)` → iterates
   `{"static","dynamic"}`; `dynamic` is `nil` so only statics run; within static, ascending
   `loadOrder`; each `correctionObject.func()` is invoked exactly once and its result merged.
10. **`createStatic.lua:135`** — l10n data loaded/merged; **`:143-159`** output dirs created;
    **`:165-233`** each type is serialised with `helpers.dumpData(data, keys, dumpFuncs, combine?)`
    and written to `Output/<Type>/<Version>/<Type>Data.lua-table`.

### 6.3 `env/globals.lua` stubs that the corrections depend on

| Global | Definition | Line |
| --- | --- | --- |
| `C_Timer.After(delay, cb)` | pushes `cb` onto `_G.__QUESTIEDB_PENDING_TIMERS`; returns a cancel handle. **Never fires on its own** — only `flushPendingTimers()` drains it. | `globals.lua:111-119` |
| `wipe(tbl)` | nils every key, returns the same table | `globals.lua:5-10, 181` |
| `UnitFactionGroup()` | returns `_G.CLI_PlayerFaction`, default **`"Horde"`** | `globals.lua:61, 159-161` |
| `UnitClass()` | `unpack(_G.CLI_PlayerClass)` = `{"Druid","DRUID",11}` | `globals.lua:62, 163-165` |
| `UnitLevel()` | `_G.CLI_PlayerLevel` = 60 | `globals.lua:60, 167-169` |
| `C_Seasons.HasActiveSeason/GetActiveSeason` | derived from `versionConfig.seasonId` | `globals.lua:95-102` |
| `C_GameRules.IsHardcoreActive` | `false` | `globals.lua:104-108` |
| `WOW_PROJECT_ID` and the `WOW_PROJECT_*` constants | 2 / 5 / 11 / 14 / 19 / 1 | `globals.lua:87-93`, `version.lua:3-8` |
| `_G.QuestieDB` | `{}` (the raw DB strings get assigned onto it by `CLI_Helpers.loadFile`) | `globals.lua:66` |
| `_G.Questie` | **not set** — so `Corrections.Icons` always falls back to its local table | — |

### 6.4 The correction table shape: `id -> fieldIndex -> value`

A correction function returns:

```lua
{
  [<entityId>] = {
    [<fieldIndexOrName>] = <value>,
    ...
  },
  ...
}
```

`mergeCorrectionData` (`env/corrections.lua:3-27`):

- Iterates ids with `pairs`. If `data[id]` does not exist it **creates** `data[id] = {}` —
  so a correction can **add a brand-new entity**, which is exactly how `Sod/base/*.lua` inject
  SoD-only quests/NPCs/items/objects.
- Per field: `local index = type(key) == "number" and key or metaKeys[key]` — numeric keys are
  used verbatim as the field index; string keys are resolved through the Meta keys table.
  Every shipped correction file writes numeric keys (`[questKeys.startedBy] = ...`), so the
  string branch is a convenience only. `assert(index, "Unknown correction key: " .. tostring(key))`
  is the sole validation.
- **Last write wins** — plain assignment, no deep merge. A later `loadOrder` completely replaces
  the earlier value for that `(id, fieldIndex)` pair.
- `applied` counts *fields*, not entities.

### 6.5 How nil-ing out a field is expressed

**An empty table `{}` is the "delete this field" sentinel.**

```lua
      if type(value) == "table" and next(value) == nil then
        entry[index] = "nil"
      else
        entry[index] = value
      end
```

The stored value is the **four-character string `"nil"`**, not Lua `nil` — Lua tables cannot
store nil, so a sentinel is required. Downstream, `Generator/db_helpers.lua:174-186` treats
`"nil"` and `nil` identically and emits the literal token `nil` into the artifact:

```lua
      ---@see Database._nil
      -- Because we set Database._nil to "nil" we have to check for "nil" here, if the value is nil we just print "nil"
      if data ~= "nil" and data ~= nil then
        ...
      else
        resulttable[dataKey] = "nil"
      end
```

`Meta/DumpFunctions.lua` has matching guards at `:56-57`, `:74-76`, `:102-104`, `:187`, `:197`,
`:310`, `:314`. `db_helpers.lua:203-207` also strips trailing `,nil` from each row.

Author-side example: `Corrections/Era/classicQuestFixes.lua:79` —
`[questKeys.preQuestSingle] = {}, -- #1198` clears the prerequisite.
`Corrections/Era/static/questReputationFixes.lua` tail —
`[questKeys.reputationReward] = {}` for quests 65603/65604/65610.

**Trap:** writing `[key] = nil` inside a Lua table constructor is a **no-op** — the key is
simply absent, and `pairs` never sees it. `Corrections/Sod/base/*.lua` is full of these
(`sodBaseNPCs.lua:40-43`: `[npcKeys.spawns] = nil, [npcKeys.friendlyToFaction] = nil,
[npcKeys.questStarts] = nil, [npcKeys.questEnds] = nil`; `sodBaseItems.lua:38-42`;
`sodBaseObjects.lua:38-40`). They document intent but do nothing. They are also harmless
*there*, because those ids are new entities whose fields are absent anyway.

---

## 7. l10n stubbing and `Questie.ICON_TYPE_*` supply

### 7.1 l10n

Exactly three files define the stub, all identical in effect:

- `Corrections/Era/classicQuestFixes.lua:15-19`

  ```lua
  --? We are doing translations differently so l10n is not needed
  --? But for copy simplicity we are keeping it here
  local function l10n(string)
    return string
  end
  ```

- `Corrections/Tbc/tbcQuestFixes.lua:15-18`

  ```lua
  --TODO: Add actual l10n support
  local function l10n(string)
    return string
  end
  ```

- `Corrections/Wotlk/wotlkQuestFixes.lua:15-18` — byte-identical to the Tbc version.

It is a **file-local** function, shadowing nothing; there is no shared l10n module for
corrections. Note the parameter is literally named `string`, shadowing the `string` library
inside the function body (harmless here).

Occurrences of `l10n(`:

| File | Count |
| --- | --- |
| `Corrections/Wotlk/wotlkQuestFixes.lua` | 469 (incl. the 1 definition) |
| `Corrections/Tbc/tbcQuestFixes.lua` | 202 |
| `Corrections/Era/classicQuestFixes.lua` | 65 |

No other correction file references `l10n` at all. Every call site is inside a
`[questKeys.extraObjectives]` value.

### 7.2 `Questie.ICON_TYPE_*`

Correction files never touch the `Questie` global. They pull from `Corrections.Icons`
(§2) into function-local upvalues at the top of `Load`:

- `Corrections/Era/classicQuestFixes.lua:68-71`

  ```lua
    local ICON_TYPE_EVENT = Corrections.Icons.ICON_TYPE_EVENT
    local ICON_TYPE_OBJECT = Corrections.Icons.ICON_TYPE_OBJECT
    local ICON_TYPE_SLAY = Corrections.Icons.ICON_TYPE_SLAY
    local ICON_TYPE_TALK = Corrections.Icons.ICON_TYPE_TALK
  ```

- `Corrections/Tbc/tbcQuestFixes.lua:54-58` — same four plus `ICON_TYPE_LOOT`.
- `Corrections/Wotlk/wotlkQuestFixes.lua:60-64` — same five.

Only **5 of the 23** icon constants are ever used: `ICON_TYPE_EVENT (3)`, `ICON_TYPE_OBJECT (4)`,
`ICON_TYPE_LOOT (2)`, `ICON_TYPE_SLAY (1)`, `ICON_TYPE_TALK (5)`.

Canonical `extraObjectives` shape combining both
(`Corrections/Era/classicQuestFixes.lua:109` and `:427`):

```lua
      [questKeys.extraObjectives] = { { { [zoneIDs.MOONGLADE] = { { 36.5, 41.7, }, }, }, ICON_TYPE_EVENT, l10n("Combine the Pendant halves at the Shrine of Remulos."), }, },
      [questKeys.extraObjectives] = { { nil, ICON_TYPE_EVENT, l10n("Summon Dagun the Ravenous using an Enchanted Sea Kelp"), 2, { { "object", 2871, }, }, }, },
```

Element layout: `{ spawnlist, iconFile, text, objectiveIndex?, {{dbReferenceType, id}, ...}? }`
(matches Questie's own comment at `Database/questDB.lua:46`).

Per-file `ICON_TYPE` occurrence counts: `wotlkQuestFixes.lua` 473, `tbcQuestFixes.lua` 206,
`classicQuestFixes.lua` 68, `Icons.lua` 23 (the definitions).

---

## 8. Meta layer — shape, and what to port vs reject

Files under `/home/logon/projects/Questie-clones/Questie-toc/Getters/GetterDB/Meta/`:

| File | Lines |
| --- | --- |
| `Meta.lua` | 20 |
| `QuestMeta.lua` | 298 |
| `NpcMeta.lua` | 160 |
| `ItemMeta.lua` | 115 |
| `ObjectMeta.lua` | 79 |
| `ZoneMeta.lua` | 300 |
| `L10nMeta.lua` | 146 |
| `DumpFunctions.lua` | 407 |

### 8.1 `Meta/Meta.lua` (full, 20 lines)

```lua
---@class LibQuestieDB
---@field Meta Meta
local LibQuestieDB = select(2, ...)

---@class Meta
local Meta = LibQuestieDB.Meta


---Create a shallow copy of the given keys table.
---Used to make a copy of the keys table to avoid modifying the original.
---@generic T
---@param keys T
---@return T
function Meta.CloneKeys(keys)
  local DBKeys = {}
  for k, v in pairs(keys) do
    DBKeys[k] = v
  end
  return DBKeys
end
```

`Meta` is purely a namespace object; every `*Meta.lua` file does
`local X = {}; LibQuestieDB.Meta.XMeta = X`. `Meta.CloneKeys` is referenced nowhere in
`Corrections/` or `Generator/`.

### 8.2 Common shape of each `<Type>Meta.lua`

Five parallel members, mechanically derived from one another:

1. **`<type>Keys`** — `name -> fieldIndex` (the schema).
2. **`NameIndexLookupTable`** — bidirectional: `for key, index in pairs(<type>Keys) do
   T[index] = key; T[key] = index end`.
3. **`<type>Types`** — `name -> "string"|"number"|"table"`, then augmented with the numeric
   indices pointing at the same type strings.
4. **`dumpFuncs`** — `name -> DumpFunctions.*`, the per-field serializer.
5. **`combine`** — set inside a `do ... end` block; if the file's local `combineValues` table
   is empty, `combine` is explicitly **set to `nil`** so `db_helpers.dumpData` skips the step.

`QuestMeta` additionally defines `QuestMeta.objectiveKeys`:
`CREATURE=1, OBJECT=2, ITEM=3, REPUTATION=4, KILLCREDIT=5, SPELL=6`.

### 8.3 `combineValues` — the packed-string artifact

| Meta | `combineValues` | Effect |
| --- | --- | --- |
| `ItemMeta` (`ItemMeta.lua:91-99`) | `{[7]='flags',[8]='foodType',[9]='itemLevel',[10]='requiredLevel',[11]='ammoType',[12]='class',[13]='subClass'}` | 7 fields collapse into one `;`-joined string at index 7 |
| `NpcMeta` (`NpcMeta.lua:134-144`) | `{[2]='minLevelHealth',[3]='maxLevelHealth',[4]='minLevel',[5]='maxLevel',[6]='rank',[9]='zoneID',[12]='factionID',[13]='friendlyToFaction',[15]='npcFlags'}` | 9 fields collapse into one string at index 2 |
| `QuestMeta` (`QuestMeta.lua:282`) | `{}` → `QuestMeta.combine = nil` | none |
| `ObjectMeta` (`ObjectMeta.lua:63`) | `{}` → `ObjectMeta.combine = nil` | none |

This packing is an artifact of the `.lua-table` intermediate format. `DESIGN.md:107` rejects
that stage outright ("The `.lua-table` intermediate stage … QuestieTDB goes raw → corrections
→ TOC in one pass"), so `combine`/`combineValues` should **not** be ported.

### 8.4 Verdict per member (against `DESIGN.md`)

`DESIGN.md:110` rejects:

> `Meta/*Meta.lua` field ordering | Served the compiler's skip-map. TOC is keyed by field index,
> so ordering is irrelevant — and the schema itself comes from Questie, which is more current.

`DESIGN.md:100-101` takes:

> `Meta/DumpFunctions.lua` | GetterDB | The Lua serializer …
> `dumpCoordinatesV2`, `dumpTriggerEndV2`, `dumpExtraObjectivesV2` | GetterDB | Domain-specific compaction …

| Member | Verdict | Reason |
| --- | --- | --- |
| `Meta.CloneKeys` | drop | unused |
| `<type>Keys` | **re-derive from Questie**, do not copy | Questie's `QuestieDB.*Keys` are authoritative and the GetterDB copy has drifted (§8.5) |
| `NameIndexLookupTable` | port (trivially regenerate) | needed to resolve string keys in `mergeCorrectionData` and to name fields when serialising; Questie already ships `QuestieDB.*KeysReversed` |
| `<type>Types` | port, but derive | GetterDB's coarse `"string"/"number"/"table"` exists only to feed `DumpFunctions.combine`. Questie's richer `*CompilerTypes` (`"u8string"`, `"spawnlist"`, `"questgivers"`, …) is the better source if per-field typing is wanted at all |
| `dumpFuncs` | **port** | the per-field serializer map; this is exactly what `DESIGN.md` says to take |
| `combine` / `combineValues` | **reject** | packed-string artifact of the `.lua-table` stage |
| `QuestMeta.objectiveKeys` | port | genuine domain enum; Questie has the same values commented in `Database/questDB.lua:22-27` |
| `QuestMeta.questFlags/factionIDs/sortKeys/professionKeys/specializationKeys` (`QuestMeta.lua:132-239`) | ignore | all commented out; live copies are in `Corrections/Enum/` |
| `NpcMeta.npcFlags`, `NpcMeta.waypointPresets` (`NpcMeta.lua:67-109`) | ignore | commented out; live copies in `Enum/Npc.lua` and `Enum/Waypoints.lua` |
| `ItemMeta.lua:14-88` class/subClass comment block | keep as documentation | duplicated verbatim in Questie `Database/itemDB.lua:29-88` |
| `ZoneMeta.zoneIDs` | **reject; take Questie's `ZoneDB.zoneIDs`** | 32 numeric conflicts, see §8.6 |
| `L10nMeta` | out of scope here | `DESIGN.md:108` rejects `mangos_translation`/`translations` |

### 8.5 Schema drift: GetterDB Meta vs Questie (source of truth)

Compared against `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/{quest,npc,item,object}DB.lua`.

- **`itemKeys` — identical.** 16 fields, `name=1 … teachesSpell=16`.
  (`Meta/ItemMeta.lua:16-33` vs `Database/itemDB.lua:5-22`.)
- **`npcKeys` — identical.** 15 fields, `name=1 … npcFlags=15`.
  (`Meta/NpcMeta.lua:18-35` vs `Database/npcDB.lua:7-24`.)
- **`objectKeys` — identical.** 7 fields, `name=1 … waypoints=7`.
  (`Meta/ObjectMeta.lua:16-24` vs `Database/objectDB.lua:5-13`.)
- **`questKeys` — DIVERGENT.** Indices 1-32 match exactly. Then:

  | Index | GetterDB `Meta/QuestMeta.lua` | Questie `Database/questDB.lua` |
  | --- | --- | --- |
  | 33 | `orderedObjectives` | `availableUntilCompleted` |
  | 34 | — | `availableStartingWith` |
  | 35 | — | `requiredRanks` |
  | 36 | — | `disabledByQuest` |

  `orderedObjectives` **does not exist anywhere in the Questie repo** (verified by
  `grep -rn "orderedObjectives" Questie/` → no matches). GetterDB's `QuestMeta` has 33 fields;
  Questie's has 36.

  **Mitigation:** no correction file references `questKeys.orderedObjectives` (verified by
  grep). All 30 quest field names used by the corrections live in indices 1-32, where the two
  schemas agree. So porting the corrections *while sourcing the schema from Questie* is safe.

  Questie also ships `questCompilerTypes` (`Database/questDB.lua:61-98`) and
  `questCompilerOrder` (`:100-109`) — the latter is precisely the compiler skip-map ordering
  `DESIGN.md:110` says to reject.

### 8.6 `ZoneMeta.zoneIDs` vs Questie `ZoneDB.zoneIDs` — 32 numeric conflicts, 26 of them live

`Meta/ZoneMeta.lua:15+` defines **267** constants; Questie
`Database/Zones/data/zoneIds.lua:8+` defines **414**. The correction files reference **174**
distinct `zoneIDs.*` names.

**32 names exist in both with different values.** GetterDB uses raw AreaTable IDs; Questie uses
synthetic ≥10000 IDs for dungeon sub-maps (and the reverse for a few):

| Name | GetterDB | Questie |
| --- | --- | --- |
| `NAXXRAMAS_CONSTRUCT_QUARTER` | 4838 | 10062 |
| `NAXXRAMAS_ARACHNID_QUARTER` | 4839 | 10063 |
| `NAXXRAMAS_MILITARY_QUARTER` | 4840 | 10064 |
| `NAXXRAMAS_PLAGUE_QUARTER` | 4841 | 10065 |
| `NAXXRAMAS_FROSTWYRM_LAIR` | 4842 | 10066 |
| `ICECROWN_CITADEL_UPPER_SPIRE` | 4830 | 10067 |
| `ICECROWN_CITADEL_QUEEN_LANA_THEL` | 4831 | 10068 |
| `ICECROWN_CITADEL_SINDRAGOSA` | 4834 | 10069 |
| `ICECROWN_CITADEL_RAMPART_OF_SKULLS` | 4835 | 10070 |
| `ICECROWN_CITADEL_DEATHBRINGERS_RISE` | 4836 | 10071 |
| `ICECROWN_CITADEL_THE_FROZEN_THRONE` | 4837 | 10072 |
| `THE_DESCENT_OF_MADNESS` | 4659 | 10050 |
| `THE_SPARK_OF_IMAGINATION` | 4660 | 10051 |
| `THE_INNER_SANCTUM_OF_ULDUAR` | 4661 | 10052 |
| `THE_TERRESTRIAL_WATCHTOWER` | 4274 | 10054 |
| `THE_BROOD_PIT` | 4301 | 10055 |
| `HADRONOXS_LAIR` | 4806 | 10056 |
| `BAND_OF_ACCELERATION` | 4802 | 10047 |
| `BAND_OF_TRANSMUTATION` | 4803 | 10048 |
| `BAND_OF_ALIGNMENT` | 4804 | 10049 |
| `THE_CULLING_OF_STRATHOLME_CITY` | 4814 | 10059 |
| `UTGARDE_PINNACLE_LOWER_LEVEL` | 4816 | 10053 |
| `UTGARDE_KEEP_MIDDLE_LEVEL` | 4819 | 10057 |
| `UTGARDE_KEEP_UPPER_LEVEL` | 4821 | 10058 |
| `DRAKTHARON_KEEP_UPPER_LEVEL` | 4823 | 10060 |
| `GUNDRAK_LOWER_LEVEL` | 4825 | 10061 |
| `BLACKROCK_DEPTHS_SHADOWFORGE_CITY` | 10002 | 1585 |
| `END_TIME_AZURE_DRAGONSHRINE` | 10034 | 5793 |
| `END_TIME_RUBY_DRAGONSHRINE` | 10035 | 5790 |
| `END_TIME_OBSIDIAN_DRAGONSHRINE` | 10036 | 5792 |
| `END_TIME_EMERALD_DRAGONSHRINE` | 10037 | 5794 |
| `END_TIME_BRONZE_DRAGONSHRINE` | 10038 | 5795 |

**26 of these 32 are actually referenced by correction files**: `BAND_OF_ACCELERATION`,
`BAND_OF_ALIGNMENT`, `BAND_OF_TRANSMUTATION`, `DRAKTHARON_KEEP_UPPER_LEVEL`,
`GUNDRAK_LOWER_LEVEL`, `HADRONOXS_LAIR`, all 6 `ICECROWN_CITADEL_*`, all 5 `NAXXRAMAS_*`,
`THE_BROOD_PIT`, `THE_CULLING_OF_STRATHOLME_CITY`, `THE_DESCENT_OF_MADNESS`,
`THE_INNER_SANCTUM_OF_ULDUAR`, `THE_SPARK_OF_IMAGINATION`, `THE_TERRESTRIAL_WATCHTOWER`,
`UTGARDE_KEEP_MIDDLE_LEVEL`, `UTGARDE_KEEP_UPPER_LEVEL`, `UTGARDE_PINNACLE_LOWER_LEVEL`.

**15 names exist only in GetterDB**, 14 of which the corrections reference — porting the
corrections against Questie's `ZoneDB.zoneIDs` alone would make these evaluate to `nil`:
`ACHERUS_THE_EBON_HOLD (4281)`, `AHNKAHET_MAP (4808)`, `BAND_OF_VARIANCE (4801)`,
`DRAKTHARON_KEEP_LOWER_LEVEL (4822)`, `GUNDRAK_UPPER_LEVEL (4824)`,
`HALLS_OF_STONE_MAP (4810)`, `LOWER_BLACKROCK_SPIRE (1583)`, `SOUTH_SEAS (2317)`,
`THE_CULLING_OF_STRATHOLME_VILLAGE (4811)`, `THE_GILDED_GATE (4807)`, `THE_NEXUS_MAP (4805)`,
`UPPER_BLACKROCK_SPIRE (7307)`, `UTGARDE_KEEP_LOWER_LEVEL (4818)`,
`UTGARDE_PINNACLE_UPPER_LEVEL (4817)`. (`EASTERN_KINGDOM = 0` is the 15th, also used.)

**This must be resolved name-by-name before the corrections are trusted.** Silently swapping
zone tables moves spawn coordinates onto wrong maps.

### 8.7 `Meta/DumpFunctions.lua` exports (for reference)

`tblMaxIndex`, `tblCount`, `dump`, `dumpAsArray`, `dumpAsArraySortSubTables`,
`dumpAsArraySorted`, `dumpCoordiates` (v1, sic), `dumpCoordinatesV2`, `dumpTriggerEnd` (v1),
`dumpTriggerEndV2`, `dumpExtraObjectives` (v1), `dumpExtraObjectivesV2`, `combine`,
`testDumpFunctions`. `DESIGN.md:100-101` says to take this file and the three `*V2` functions;
the v1 variants are superseded and referenced by no `dumpFuncs` map.

---

## 9. Porting checklist (derived)

1. Take `Corrections.lua` largely as-is: 8 registries, 12 load-order constants,
   linear-probe collision handling with a warning, function-held corrections, `wipe()` after
   deferred registration. Add owner scoping per `DESIGN.md:322-336`.
2. Replace the literal `70` in the four `Sod/base/*.lua` with the intended constant, and decide
   what "SoD loads last" should actually mean (the current 200/300 window puts SoD before TBC).
3. Fix `tbcQuestFixes.lua:29` `TbcBaseStaticOrder` → `TbcBaseDynamicOrder`.
4. Do not infer static/dynamic from folder names; read the register call.
5. Source `*Keys` from Questie's `QuestieDB.*Keys`, not from `Meta/*Meta.lua`
   (`questKeys[33]` conflict).
6. Reconcile `ZoneMeta.zoneIDs` against Questie's `ZoneDB.zoneIDs` per name (32 conflicts,
   15 GetterDB-only names).
7. Keep the empty-table (`{}`) → delete-field convention; the `"nil"` string is an artifact of
   the `.lua-table` writer and can be replaced by whatever sentinel the TOC writer wants —
   but the **author-facing** convention (`= {}`) must not change or ~4260 correction entries
   need editing.
8. Note that `[key] = nil` in correction sources is inert; consider linting for it.
9. Keep the `l10n(s) return s end` stub convention (`DESIGN.md:366-369`).
10. Keep `Corrections.Icons` as-is (lazy Questie-first, local-fallback, cached).
11. Do not port `combine`/`combineValues`; do port `dumpFuncs` and the `*V2` dump functions.
12. Do not port `require("lfs")` (`DESIGN.md:108`) — the module loader
    (`Generator/env/module_loader.lua`) depends on it; replace with an explicit config list.
