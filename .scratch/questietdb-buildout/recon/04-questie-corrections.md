# Recon 04 — Questie's live corrections system

Scope: `Questie/Database/Corrections/` (63 files, 62 `.lua` + 1 `.md`, ~10.47 MB total).
All paths below are relative to `/home/logon/projects/Questie-clones/Questie-toc/Questie/`.
Everything here is read from Questie (source of truth). Prototypes were not consulted.

---

## 1. `QuestieCorrections.lua` — the engine

File: `Database/Corrections/QuestieCorrections.lua`, 450 lines / 22 193 bytes.

### 1.1 Module surface

```lua
QuestieCorrections.killCreditObjectiveFirst = {}   -- L96
QuestieCorrections.objectObjectiveFirst    = {}    -- L97
QuestieCorrections.itemObjectiveFirst      = {}    -- L98
QuestieCorrections.eventObjectiveFirst     = {}    -- L99
QuestieCorrections.spellObjectiveFirst     = {}    -- L100
-- created later:
QuestieCorrections.questItemBlacklist  -- set in MinimalInit L183
QuestieCorrections.questNPCBlacklist   -- set in MinimalInit L184
QuestieCorrections.hiddenQuests        -- set in MinimalInit L185
```

`local filterExpansion = BlacklistFilter.filterExpansion` (L94).

Public functions: `MinimalInit()` (L125), `Initialize(validationTables)` (L258),
`OptimizeWaypoints(waypointData)` (L375), `PreCompile()` (L418).
Private: `addOverride(override_table, new_overrides)` (L107, inside `do..end` L102–224),
`_LoadCorrections(...)` (L232).

### 1.2 Two distinct merge primitives

**(a) `_LoadCorrections` — writes into the *raw* `QuestieDB.<table>` before compilation.**
`QuestieCorrections.lua:232-255`:

```lua
local _LoadCorrections = function(databaseTableName, corrections, reversedKeys, validationTables, noOverwrites, noNewEntries)
    for id, data in pairs(corrections) do
        for key, value in pairs(data) do
            -- Create the id if missing unless noNewEntries is set
            if not QuestieDB[databaseTableName][id] and not noNewEntries then
                QuestieDB[databaseTableName][id] = {}
            end
            if validationTables and QuestieDB[databaseTableName][id] then
                if value and QuestieLib.equals(QuestieDB[databaseTableName][id][key], value) and validationTables[databaseTableName][id] and
                    QuestieLib.equals(validationTables[databaseTableName][id][key], value) then
                    Questie:Warning("Correction of " ..
                                    databaseTableName .. " " .. tostring(id) .. "." .. reversedKeys[key] .. " matches base DB! Value:" .. tostring(value))
                end
            end
            if QuestieDB[databaseTableName][id] then
                if noOverwrites and QuestieDB[databaseTableName][id][key] == nil then
                    QuestieDB[databaseTableName][id][key] = value
                elseif not noOverwrites then
                    QuestieDB[databaseTableName][id][key] = value
                end
            end
        end
    end
end
```

* `databaseTableName` is one of the literal strings `"questData"`, `"npcData"`,
  `"itemData"`, `"objectData"`.
* `reversedKeys` is only used to render the CI warning message; it is
  `QuestieDB.questKeysReversed` / `npcKeysReversed` / `itemKeysReversed` /
  `objectKeysReversed` (built in `Database/questDB.lua:56-59` and siblings).
* `noOverwrites` / `noNewEntries` are used exactly once, by
  `QuestieItemStartFixes:LoadAutomaticQuestStarts()` (L311, both `true`).

**(b) `addOverride` — merges into the runtime override tables used against the *compiled* DB.**
`QuestieCorrections.lua:107-123`:

```lua
local function addOverride(override_table, new_overrides)
    assert(type(override_table) == "table", "Override table must be a table!")
    assert(type(new_overrides) == "table", "New overrides must be a table!")
    for id, data in pairs(new_overrides) do
        assert(type(id) == "number", "Override id must be a number!")
        assert(type(data) == "table", "Override data must be a table!")
        if not override_table[id] then
            override_table[id] = data           -- assigns the table BY REFERENCE
        else
            for key, value in pairs(data) do    -- shallow per-field merge
                override_table[id][key] = value
            end
        end
    end
end
```

Targets are `QuestieDB.itemDataOverrides`, `npcDataOverrides`, `objectDataOverrides`,
`questDataOverrides`, declared empty at `Database/QuestieDB.lua:234-237` and passed as the
5th argument to `QuestieDBCompiler:GetDBHandle(...)` at `Database/QuestieDB.lua:293/295/297/299`.

### 1.3 Correction table shape

`id (number) -> fieldIndex (number) -> value`. The field index comes from
`QuestieDB.questKeys` / `npcKeys` / `itemKeys` / `objectKeys` (e.g.
`Database/questDB.lua:6-54`: `name=1, startedBy=2, finishedBy=3, requiredLevel=4,
questLevel=5, requiredRaces=6, requiredClasses=7, objectivesText=8, triggerEnd=9,
objectives=10, sourceItemId=11, preQuestGroup=12, preQuestSingle=13, childQuests=14,
inGroupWith=15, exclusiveTo=16, zoneOrSort=17, requiredSkill=18, requiredMinRep=19,
requiredMaxRep=20, requiredSourceItems=21, nextQuestInChain=22, questFlags=23,
specialFlags=24, parentQuest=25, reputationReward=26, breadcrumbForQuestId=27,
breadcrumbs=28, extraObjectives=29, requiredSpell=30, requiredSpecialization=31,
requiredMaxLevel=32, availableUntilCompleted=33, availableStartingWith=34,
requiredRanks=35, disabledByQuest=36`).

Every correction file therefore returns a table literal shaped like:

```lua
return {
    [5] = {
        [questKeys.preQuestSingle] = {},
        [questKeys.breadcrumbs] = {163}, -- #1198
    },
    ...
}
```

(`classicQuestFixes.lua:52-56`.)

### 1.4 How a correction expresses "delete this field" / "set to nil"

**There is no nil sentinel — `= nil` in a correction table is a NO-OP.** Lua's table
constructor drops `[k] = nil`, and `_LoadCorrections` iterates with `pairs`, so the key is
never visited. Occurrences (`[questKeys.inGroupWith] = nil` at
`classicQuestFixes.lua:425, 704, 725, 2916`; 3 in `tbcQuestFixes.lua`; 1 in
`wotlkQuestFixes.lua`; 4 in `cataQuestFixes.lua`) are documentation only. The generated
SoD base files are riddled with them (`Automatic/sodBaseItems.lua` 27 509 occurrences,
`sodBaseNPCs.lua` 6 857, `sodBaseObjects.lua` 727, `sodBaseQuests.lua` 461,
`sodQuestFixes.lua` 321) — all dead weight.

**The real "delete" idiom is the empty table `{}`.** Counts of `= {},`:
`classicQuestFixes` 240, `tbcQuestFixes` 173, `wotlkQuestFixes` 503, `cataQuestFixes` 933.
Two mechanisms make this work:

1. Compile path: `{}` is written into `QuestieDB.questData[id][key]`, and the compiler
   serialises an empty table as "no data", so reads return nil.
2. Runtime override path: `Database/compiler.lua:1131-1142` explicitly maps empty table →
   nil:

```lua
handle.QuerySingle = function(id, key)
    local override = overrides[id]
    if override then
        local kti = keyToRootIndex[key]
        if kti and override[kti] ~= nil then
            if type(override[kti]) ~= "table" or next(override[kti]) then
                return override[kti]
            else
                -- We want to return nil if the table is empty, to match the compiler behavior
                return nil
            end
        end
    end
    ...
```

**Caveat:** `handle.Query` (`compiler.lua:1168-1218`) and `handle.QueryValidator`
(L1222+) do **not** apply the empty-table→nil rule; they only test `override[rootIndex] ~= nil`
and hand the empty table straight back. So `{}`-as-delete behaves differently between
`QuerySingle` and `Query`. This is a real inconsistency in Questie today.

Other deletion-ish idioms seen: scalar fields are zeroed (`[questKeys.nextQuestInChain] = 0`
in `classicQuestFixes.lua:6455`), and `_QuestieDB:DeleteGatheringNodes()`
(`Database/QuestieDB.lua:1827-1838`) nils `objectData[id][objectKeys.spawns]` directly for a
hardcoded prune list of 24 herb/mining node object IDs — that runs from
`QuestieInit.lua:130`, between `QuestieCorrections:Initialize()` and `PreCompile()`.

`QuestieQuestFixes:LoadMissingQuests()` and the `InsertMissing*Ids()` helpers create empty
entries directly (`QuestieDB.questData[5640] = {}`) so the compiler emits a row at all.

### 1.5 `MinimalInit()` — exact order (L125-223)

Runs when the compiled DB is reused (`QuestieInit.lua:174`) and also as the last statement
of `Initialize()` (L352). Applies corrections that must exist as *runtime overrides* on top
of the compiled binary — i.e. everything faction- or realm-dependent that must not be baked.

| # | L | Gate | Action |
|---|---|---|---|
| 1 | 127 | always | `addOverride(itemDataOverrides, QuestieItemFixes:LoadFactionFixes())` |
| 2 | 128 | always | `addOverride(npcDataOverrides, QuestieNPCFixes:LoadFactionFixes())` |
| 3 | 129 | always | `addOverride(objectDataOverrides, QuestieObjectFixes:LoadFactionFixes())` |
| 4 | 130 | always | `addOverride(questDataOverrides, QuestieQuestFixes:LoadFactionFixes())` |
| 5 | 134-137 | `Expansions.Current >= Expansions.Tbc` | TBC item / npc / object / quest `LoadFactionFixes()` |
| 6 | 142-145 | `Expansions.Current >= Expansions.Wotlk` | Wotlk **npc, item, object, quest** `LoadFactionFixes()` (note npc first here) |
| 7 | 148-150 | `... and Questie.IsTitanReforged` | `QuestieWotlkNpcFixes:LoadTitanReforgedFixes()`, `QuestieWotlkQuestFixes:LoadTitanReforgedFixes()`, `QuestieWotlkItemFixes:LoadTitanReforgedFixes()` |
| 8 | 153-155 | `... and GetLocale() == "zhCN"` | `addOverride(questDataOverrides, Questie.LoadTitanQuestLookupOverrides())` (defined `Localization/lookups/lookupOverrides.lua:107`) |
| 9 | 161-164 | `>= Expansions.Cata` | Cata quest / npc / item / object `LoadFactionFixes()` |
| 10 | 169-171 | `>= Expansions.MoP` | Mop quest / npc / object `LoadFactionFixes()` (**no item**) |
| 11 | 173-175 | `>= Expansions.MoP` | Mop quest / npc / object `LoadContentPhaseFixes()` (all three currently `return {}`) |
| 12 | 180 | `Questie.IsSoD` | `addOverride(questDataOverrides, SeasonOfDiscovery:LoadFactionQuestFixes())` |
| 13 | 183 | always | `QuestieCorrections.questItemBlacklist = filterExpansion(QuestieItemBlacklist:Load())` |
| 14 | 184 | always | `QuestieCorrections.questNPCBlacklist = filterExpansion(QuestieNPCBlacklist:Load())` |
| 15 | 185 | always | `QuestieCorrections.hiddenQuests = filterExpansion(QuestieQuestBlacklist:Load())` |
| 16 | 188-195 | `Questie.db.global.isleOfQuelDanasPhase == IsleOfQuelDanas.MAX_ISLE_OF_QUEL_DANAS_PHASES` (=9) | merge `IsleOfQuelDanas.quests[9]` into `hiddenQuests`, **only where `hiddenQuests[id] == nil`** |
| 17 | 198-205 | `>= Expansions.Wotlk` | merge `QuestieQuestBlacklist.LoadAutoBlacklistWotlk()` into `hiddenQuests`, nil-check only |
| 18 | 207-214 | `... and Questie.IsTitanReforged` | merge `QuestieQuestBlacklist.LoadAutoBlacklistIsTitanReforged()`, nil-check only |
| 19 | 218-222 | `Questie.IsHardcore` | `for id in pairs(HardcoreBlacklist:Load()) do hiddenQuests[id] = true end` (unconditional overwrite) |

Note the asymmetry: steps 16–18 use `if (QuestieCorrections.hiddenQuests[id] == nil)` — the
comment says *"This has to be a nil-check, because the value could be false"*. Step 19 does not.

### 1.6 `Initialize(validationTables)` — exact order (L258-354)

Runs only on a full DB (re)compile, from `QuestieInit.lua:119` inside `loadFullDatabase()`.

| # | L | Gate | Call |
|---|---|---|---|
| 1 | 259 | always | `QuestieQuestFixes:LoadMissingQuests()` (creates 12 empty `questData` rows: 5640, 5678, 7668, 7669, 7670, 65593, 65597, 65601, 65602, 65603, 65604, 65610) |
| 2 | 262-265 | `Questie.IsClassic` | `_LoadCorrections("questData", QuestieClassicQuestReputationFixes:Load(), ...)` — comment: *"This data is only correct for Era/SoX, for the other expansions we trust the base DB"* |
| 3 | 266 | always | `_LoadCorrections("questData", QuestieQuestFixes:Load(), ...)` |
| 4 | 267 | always | `_LoadCorrections("npcData", QuestieNPCFixes:Load(), ...)` |
| 5 | 268 | always | `_LoadCorrections("itemData", QuestieItemFixes:Load(), ...)` |
| 6 | 269 | always | `_LoadCorrections("objectData", QuestieObjectFixes:Load(), ...)` |
| 7 | 272-275 | `>= Tbc` | TBC quest, npc, item, object `:Load()` |
| 8 | 279 | `>= Wotlk` | `QuestieWotlkQuestFixes:Load()` |
| 9 | 280 | `>= Wotlk` | `QuestieWotlkNpcFixes:LoadAutomatics()` — **before** `:Load()` |
| 10 | 281 | `>= Wotlk` | `QuestieWotlkNpcFixes:Load()` |
| 11 | 282-283 | `>= Wotlk` | Wotlk item, object `:Load()` |
| 12 | 287-290 | `>= Cata` | `CataQuestFixes.Load()`, `CataNpcFixes.Load()`, `CataItemFixes.Load()`, `CataObjectFixes.Load()` (dot-call, not colon) |
| 13 | 294-297 | `>= MoP` | `MopQuestFixes.Load()`, `MopNpcFixes.Load()`, `MopItemFixes.Load()`, `MopObjectFixes.Load()` |
| 14 | 301-308 | `Questie.IsSoD` | in order: `LoadBaseQuests()`, `LoadQuests()`, `LoadBaseNPCs()`, `LoadNPCs()`, `LoadBaseItems()`, `LoadItems()`, `LoadBaseObjects()`, `LoadObjects()` — base always before fixes |
| 15 | 311 | always | `_LoadCorrections("itemData", QuestieItemStartFixes:LoadAutomaticQuestStarts(), ..., true, true)` — `noOverwrites=true, noNewEntries=true` |
| 16 | 313-350 | always | **Faction inference pass**: for every quest with `requiredRaces` nil or `0`, look at `startedBy[1]` NPC IDs, read `npcData[id][npcKeys.friendlyToFaction]` (`"H"`/`"A"`/`"AH"`); if exactly one faction can start it, set `requiredRaces = raceKeys.ALL_ALLIANCE` or `ALL_HORDE`. Counter `patchCount` is computed but never used. |
| 17 | 352 | always | `QuestieCorrections:MinimalInit()` |

Note side-effect ordering: the `QuestieCorrections.*ObjectiveFirst[...] = true` statements are
executed at **file load time** (top of each `*QuestFixes.lua`), not inside `Load()`.

### 1.7 `PreCompile()` and `OptimizeWaypoints()`

`PreCompile()` (L418-450) runs after `Initialize()` (`QuestieInit.lua:134`). For every
`npcData[id][npcKeys.waypoints]` and `objectData[id][objectKeys.waypoints]` it calls
`OptimizeWaypoints`, which per zone: runs `RamerDouglasPeucker(waypoints, 0.1, true)` and
then subdivides segments longer than `WAYPOINT_MIN_DISTANCE * (ZONE_SCALES[zone] or 1)`
where `WAYPOINT_MIN_DISTANCE = 1.5` (L356) and `ZONE_SCALES` = 0.5 for
`STORMWIND_CITY, IRONFORGE, TELDRASSIL, ORGRIMMAR, THUNDER_BLUFF, UNDERCITY` (L357-365).
It coroutine-yields every 500 NPCs (`yieldLimit = 500`). Note the object loop at L439-449
never increments `count` — a latent bug (yield never triggers for objects).

### 1.8 Blacklist mechanism vs. corrections

A **correction** is `id -> fieldIndex -> value` and mutates entity data.
A **blacklist** is `id -> boolean | "HIDE_ON_MAP"` and never touches entity data; it is a
separate visibility set consulted by consumers.

`BlacklistFilter.lua` (15 lines, whole file):

```lua
function BlacklistFilter.filterExpansion(blacklist)
    for questId, flag in pairs(blacklist) do
        if flag == false then
            blacklist[questId] = nil
        end
    end
    return blacklist
end
```

It mutates in place and returns the same table. Its whole purpose: blacklist files store
`[id] = <expansion expression>`, so entries evaluate to `false` on flavors where the quest
*should* be visible; `filterExpansion` strips those so the surviving keys are only truthy.
`"HIDE_ON_MAP"` survives (see `BlacklistFilter.test.lua:13-25`).

Blacklist consumers:
* `QuestieCorrections.hiddenQuests` — `Database/QuestieDB.lua:693`, `:971` (`~= HIDE_ON_MAP`
  check), `:1502` (`QO.isHidden = rawdata.hidden or QuestieCorrections.hiddenQuests[questId]`),
  `Database/Zones/zoneDB.lua:200-206`,
  `Modules/Journey/tabs/QuestsByFaction/QuestsByFactions.lua:246,272,422`, all `cli/validate-*.lua`.
* `QuestieCorrections.questItemBlacklist` — `Database/QuestieDB.lua:392` (`Hidden = ...`).
* `QuestieCorrections.questNPCBlacklist` — `Modules/QuestieMenu/QuestieMenu.lua:172`.
* `QuestieEvent` **un-blacklists** at runtime: `hiddenQuests[questId] = nil` at
  `Holidays/QuestieEvent.lua:242, 403, 418, 421, 432` and re-blacklists at `:428, 435`.

`HIDE_ON_MAP = "HIDE_ON_MAP"` is defined at `QuestieQuestBlacklist.lua:8` and re-exported as
`QuestieQuestBlacklist.HIDE_ON_MAP` (L10).

### 1.9 `ObjectiveFirst` tables (module-level side effects)

Read at `Database/QuestieDB.lua:1556` (object), `1577` (item), `1609` (killCredit),
`1630` (spell), `1649` (event). Populated at file scope:

| File | table | count |
|---|---|---|
| `classicQuestFixes.lua:16-17` | `itemObjectiveFirst` (503, 5088) | 2 |
| `tbcQuestFixes.lua:17` | `killCreditObjectiveFirst` (10503) | 1 |
| `wotlkQuestFixes.lua` | `killCreditObjectiveFirst` | 16 |
| `cataQuestFixes.lua:15-32` | `objectObjectiveFirst` 9, `killCreditObjectiveFirst` 9 | 18 |
| `mopQuestFixes.lua:15-…` | `spellObjectiveFirst` 92, `killCreditObjectiveFirst` 22, `objectObjectiveFirst` 7, `itemObjectiveFirst` 4 | 125 |
| `sodQuestFixes.lua:14-16` | `eventObjectiveFirst` (85304, 85386, 89567) | 3 |

---

## 2. Full file inventory + STATIC / DYNAMIC / STAYS-IN-QUESTIE classification

Classification rule applied (from `QuestieTDB/DESIGN.md:286-287`):
**STATIC** = data truth, knowable offline, foldable during Generation.
**DYNAMIC** = conditional at runtime (faction/season/date/setting), applied via the
Correction Overlay — may still be *owned* by QuestieTDB.
**STAYS-IN-QUESTIE** = consumer/display policy or Questie-internal machinery.

### 2.1 Per-expansion entity fix files

`entities` = distinct top-level ids per function (measured, 8-space-indent `[id] = {`).

| File | Bytes | Lines | Entity | Expansion gate | Functions & entities | Class | Reason |
|---|---|---|---|---|---|---|---|
| `classicQuestFixes.lua` | 277 240 | 7 026 | quest | always | `LoadMissingQuests` 12, `Load` **1 734**, `LoadFactionFixes` **86** | `Load` **STATIC**; `LoadFactionFixes` **DYNAMIC** | Load is flat data truth; FactionFixes branch on `UnitFactionGroup`/`UnitClassBase` |
| `classicNPCFixes.lua` | 248 265 | 3 773 | npc | always | `Load` **983**, `LoadFactionFixes` **9**, `LoadDarkmoonFixes(isInMulgore)` 2 branches × **6** npcs | STATIC / DYNAMIC / **DYNAMIC** | Darkmoon variant is calendar-driven |
| `classicItemFixes.lua` | 62 622 | 1 657 | item | always | `Load` **405**, `LoadFactionFixes` **5** | STATIC / DYNAMIC | |
| `classicObjectFixes.lua` | 62 528 | 636 | object | always | `Load` **134**, `LoadFactionFixes` **9** | STATIC / DYNAMIC | |
| `tbcQuestFixes.lua` | 383 250 | 8 841 | quest | `>= Tbc` | `Load` **1 874** (calls `_QuestieTBCQuestFixes:InsertMissingQuestIds()` at L21 → **113** empty `questData` rows), `LoadFactionFixes` **73** | STATIC / DYNAMIC | FactionFixes also reads `UnitRace` |
| `tbcNPCFixes.lua` | 125 021 | 2 148 | npc | `>= Tbc` | `Load` **532**, `LoadFactionFixes` **2**, `LoadDarkmoonFixes(isInMulgore,isInTerokkar)` 3 branches × **6** npcs | STATIC / DYNAMIC / DYNAMIC | |
| `tbcItemFixes.lua` | 18 095 | 628 | item | `>= Tbc` | `Load` **183**, `LoadFactionFixes` **5** | STATIC / DYNAMIC | |
| `tbcObjectFixes.lua` | 53 935 | 1 142 | object | `>= Tbc` | `Load` **221**, `LoadFactionFixes` **2** | STATIC / DYNAMIC | |
| `wotlkQuestFixes.lua` | 412 758 | 9 022 | quest | `>= Wotlk` | `Load` **1 802** (calls `_QuestieWotlkQuestFixes:InsertMissingQuestIds()` at L35 → **50** empty rows), `LoadFactionFixes` **25**, `LoadTitanReforgedFixes` **31** | STATIC / DYNAMIC / **DYNAMIC** | TitanReforged = realm flag |
| `wotlkNPCFixes.lua` | 214 063 | 3 992 | npc | `>= Wotlk` | `Load` **789**, `LoadAutomatics` **93**, `LoadTitanReforgedFixes` **2**, `LoadFactionFixes` **22** | STATIC / STATIC / DYNAMIC / DYNAMIC | |
| `wotlkItemFixes.lua` | 42 289 | 828 | item | `>= Wotlk` | `Load` **240** (calls `_QuestieWotlkItemFixes:InsertMissingItemIds()` at L12 → **7** empty rows: 199335, 199336, 199777, 199778, 200068, 211206, 211207), `LoadTitanReforgedFixes` **1** (item 22734), `LoadFactionFixes` **1** (item 49698) | STATIC / DYNAMIC / DYNAMIC | |
| `wotlkObjectFixes.lua` | 59 130 | 891 | object | `>= Wotlk` | `Load` **186**, `LoadFactionFixes` **5** | STATIC / DYNAMIC | |
| `cataQuestFixes.lua` | 726 593 | 15 901 | quest | `>= Cata` | `Load` **4 096**, `LoadFactionFixes` **41** | STATIC / DYNAMIC | largest single correction file |
| `cataNPCFixes.lua` | 502 074 | 9 090 | npc | `>= Cata` | `Load` **2 307**, `LoadFactionFixes` **35** | STATIC / DYNAMIC | |
| `cataItemFixes.lua` | 44 235 | 1 303 | item | `>= Cata` | `Load` **415**, `LoadFactionFixes` **3** | STATIC / DYNAMIC | |
| `cataObjectFixes.lua` | 109 200 | 1 793 | object | `>= Cata` | `Load` **493**, `LoadFactionFixes` **13** | STATIC / DYNAMIC | |
| `mopQuestFixes.lua` | 555 355 | 10 876 | quest | `>= MoP` | `Load` **2 225**, `LoadFactionFixes` **33**, `LoadContentPhaseFixes` **`return {}`** | STATIC / DYNAMIC / DYNAMIC(empty) | |
| `mopNPCFixes.lua` | 477 563 | 7 465 | npc | `>= MoP` | `Load` **1 414**, `LoadFactionFixes` **19**, `LoadContentPhaseFixes` `{}` | STATIC / DYNAMIC / DYNAMIC(empty) | |
| `mopItemFixes.lua` | 49 692 | 1 404 | item | `>= MoP` | `Load` **441** only (no faction fn) | **STATIC** | |
| `mopObjectFixes.lua` | 88 508 | 1 393 | object | `>= MoP` | `Load` **300**, `LoadFactionFixes` **1**, `LoadContentPhaseFixes` `{}` | STATIC / DYNAMIC / DYNAMIC(empty) | |
| `sodQuestFixes.lua` | 498 913 | 9 734 | quest | `Questie.IsSoD` | `LoadQuests` **1 292**, `LoadFactionQuestFixes` **53** | **DYNAMIC** (both) | SoD is a realm flag over Era — DESIGN.md:483 |
| `sodNPCFixes.lua` | 113 947 | 2 955 | npc | `Questie.IsSoD` | `LoadNPCs` **726** | DYNAMIC | |
| `sodItemFixes.lua` | 15 092 | 350 | item | `Questie.IsSoD` | `LoadItems` **110** | DYNAMIC | |
| `sodObjectFixes.lua` | 42 022 | 1 040 | object | `Questie.IsSoD` | `LoadObjects` **203** | DYNAMIC | |

### 2.2 `Automatic/`  (4 204 644 bytes total — 40 % of the whole Corrections tree)

| File | Bytes | Lines | Entity | Gate | Entities | Class | Reason |
|---|---|---|---|---|---|---|---|
| `Automatic/classicQuestReputationFixes.lua` | 351 294 | 12 775 | quest | `Questie.IsClassic` | **4 254** | **STATIC** | pure generated `reputationReward` data, no runtime refs; header says "AUTO GENERATED FILE! DO NOT EDIT!" |
| `Automatic/itemStartFixes.lua` | 99 433 | 2 272 | item | always | **452** (all only `itemKeys.startQuest`) | **STATIC** | generated from wowhead; applied with `noOverwrites+noNewEntries` |
| `Automatic/sodBaseQuests.lua` | 577 098 | 10 213 | quest | `Questie.IsSoD` | **927** | **DYNAMIC** | new SoD-only base rows over Era DB |
| `Automatic/sodBaseNPCs.lua` | 948 931 | 23 067 | npc | `Questie.IsSoD` | **2 092** | **DYNAMIC** | |
| `Automatic/sodBaseItems.lua` | **2 124 174** | 54 086 | item | `Questie.IsSoD` | **6 759** | **DYNAMIC** | single largest file in the tree |
| `Automatic/sodBaseObjects.lua` | 99 618 | 2 821 | object | `Questie.IsSoD` | **334** | **DYNAMIC** | |

All four `sodBase*.lua` carry the header *"These are generated, do NOT EDIT the data entries
here. If you want to edit an X, do so in sodXFixes.lua"*.

### 2.3 Blacklists

| File | Bytes | Lines | Entity | Gate | Entities | Class | Reason |
|---|---|---|---|---|---|---|---|
| `QuestieQuestBlacklist.lua` | 527 925 | 8 602 | quest | always | `Load` **6 754** (L13-7108), `AQWarEffortQuests` **140** (L7110-7256, a *plain module table*, not consumed by MinimalInit — read at `QuestieDB.lua:545, 989` and gated by `Questie.db.profile.showAQWarEffortQuests`), `LoadAutoBlacklistWotlk` **283** (L7259-7921), `LoadAutoBlacklistIsTitanReforged` **417** (L7924-8603) | **STAYS-IN-QUESTIE** | visibility policy, not entity data; 4 265 entries are live `Expansions.*` expressions + 46 `Questie.Is*` |
| `QuestieItemBlacklist.lua` | 8 512 | 247 | item | always | **220**, all literal `true` | **STAYS-IN-QUESTIE** (or DYNAMIC set) | "don't show these items as objectives" — display policy |
| `QuestieNPCBlacklist.lua` | 2 252 | 31 | npc | always | **19**, 15 of them conditional | **STAYS-IN-QUESTIE** | expansion/season conditional visibility |
| `HardcoreBlacklist.lua` | 9 984 | 211 | quest | `Questie.IsHardcore` | **202**, all `true` | **STAYS-IN-QUESTIE** | realm-rules policy |
| `BlacklistFilter.lua` | 459 | 15 | — | — | — | **STAYS-IN-QUESTIE** | 1-function helper for the above |
| `BlacklistFilter.test.lua` | 657 | 26 | — | — | — | STAYS-IN-QUESTIE | busted test, not in any `.toc` |
| `QuestieQuestBlacklist.test.lua` | 2 878 | — | — | — | — | STAYS-IN-QUESTIE | busted test |

`QuestieQuestBlacklist:Load()` value breakdown over its 6 754 entries:
`true` **2 384**, `Expansions.*` expression **4 265**, `Questie.Is*` expression **46**,
`Expansions.* or HIDE_ON_MAP` **32**, `false` **17**, bare `HIDE_ON_MAP` **10**.

### 2.4 `ContentPhases/`

| File | Bytes | Lines | Gate (via `.toc`) | Content | Class | Reason |
|---|---|---|---|---|---|---|
| `ContentPhases/ContentPhases.lua` | 672 | 19 | Classic, BCC, WOTLKC, Mists (**not Cata**) | `activePhases = {SoM=5, SoD=7, Anniversary=6, MoP=(Questie.IsChinaRegion and 4 or 5), TBC=2}`; `IsInvasionActive = {[1]=Questie.IsSoD and true or false, [2]=false, [3]=false}` | **STAYS-IN-QUESTIE** | hand-maintained live-server state |
| `ContentPhases/Anniversary.lua` | 21 100 | 786 | Classic only | 7 phases, **747** quest ids (p2=38, p3=91, p4=264, p5=199, p6=126, p7=29) | STAYS-IN-QUESTIE | phase-gated blacklist |
| `ContentPhases/BurningCrusade.lua` | 6 113 | 238 | BCC only | 5 phases, **199** ids (p2=81, p3=54, p4=11, p5=53) | STAYS-IN-QUESTIE | |
| `ContentPhases/MistsOfPandaria.lua` | 39 609 | 793 | Mists only | 5 phases, **763** ids (p2=193, p3=295, p4=47, p5=228) | STAYS-IN-QUESTIE | |
| `ContentPhases/SeasonOfDiscovery.lua` | 33 147 | 799 | Classic only | 8 phases, **725** ids (p2=6, p3=23, p4=0, p5=109, p6=37, p7=133, p8=417) | STAYS-IN-QUESTIE | |
| `ContentPhases/SeasonOfMastery.lua` | 12 805 | 535 | Classic only | 6 phases, **500** ids (p3=50, p4=116, p5=208, p6=126) | STAYS-IN-QUESTIE | |
| `ContentPhases/ContentPhases.test.lua` | 9 409 | — | not in `.toc` | — | STAYS-IN-QUESTIE | |

All five data files expose one identical function shape (`Anniversary.lua:778-786`,
`BurningCrusade.lua:230-238`, `MistsOfPandaria.lua:785-793`, `SeasonOfDiscovery.lua:791-799`,
`SeasonOfMastery.lua:527-535`):

```lua
function ContentPhases.BlacklistXQuestsByPhase(questsToBlacklist, contentPhase)
    for phase = contentPhase + 1, #questsToBlacklistByPhase do
        for questId in pairs(questsToBlacklistByPhase[phase]) do
            questsToBlacklist[questId] = true
        end
    end
    return questsToBlacklist
end
```

Dispatched from `QuestieQuestBlacklist.lua:7090-7105` in this exact if/elseif chain:
`Questie.IsSoD` → `Questie.IsTBC` → `Questie.IsAnniversaryEra or Questie.IsAnniversaryHardcore`
→ `Questie.IsSoM` → `Questie.IsMoP`. (No branch for Era-non-seasonal, Wotlk, Cata.)

### 2.5 `Holidays/`

| File | Bytes | Lines | Event quests inserted | Class | Reason |
|---|---|---|---|---|---|
| `Holidays/QuestieEvent.lua` | 25 682 | 676 | — engine | **STAYS-IN-QUESTIE** | calendar/date/CVar/C_Calendar-driven; already a clean Dynamic Correction per DESIGN.md:685-691 |
| `Holidays/QuestieEvent.test.lua` | 32 474 | — | — | STAYS-IN-QUESTIE | busted test |
| `Holidays/quests/Brewfest.lua` | 3 839 | 52 | **36** | STAYS-IN-QUESTIE | |
| `Holidays/quests/ChildrensWeek.lua` | 5 013 | 74 | **56** | STAYS-IN-QUESTIE | |
| `Holidays/quests/DarkmoonFaire.lua` | 12 088 | 141 | **123** | STAYS-IN-QUESTIE | |
| `Holidays/quests/DayOfTheDead.lua` | 1 414 | 24 | **15** | STAYS-IN-QUESTIE | |
| `Holidays/quests/HallowsEnd.lua` | 18 495 | 291 | **271** | STAYS-IN-QUESTIE | |
| `Holidays/quests/HarvestFestival.lua` | 298 | 8 | **2** | STAYS-IN-QUESTIE | |
| `Holidays/quests/LoveIsInTheAir.lua` | 7 576 | 92 | **68** | STAYS-IN-QUESTIE | |
| `Holidays/quests/LunarFestival.lua` | 8 648 | 125 | **111** | STAYS-IN-QUESTIE | |
| `Holidays/quests/Midsummer.lua` | 17 331 | 265 | **247** | STAYS-IN-QUESTIE | |
| `Holidays/quests/Noblegarden.lua` | 819 | 15 | **6** | STAYS-IN-QUESTIE | |
| `Holidays/quests/PilgrimsBounty.lua` | 1 983 | 31 | **24** | STAYS-IN-QUESTIE | |
| `Holidays/quests/WinterVeil.lua` | 5 060 | 67 | **47** | STAYS-IN-QUESTIE | |

Total **1 006** event-quest rows. Row shape (`QuestieEvent.lua:56-63`):
`{[1]=eventName, [2]=questId, [3]="DD/MM" start, [4]="DD/MM" end, [5]="HH:MM", [6]="HH:MM", [7]=hideQuestEvenDuringEvent}`.
Field 7 doubles as the expansion gate, e.g.
`tinsert(eventQuests, {"Brewfest", 11400, nil,nil,nil,nil, Expansions.Current >= Expansions.Wotlk})`.

### 2.6 Remaining top-level files

| File | Bytes | Lines | Class | Reason |
|---|---|---|---|---|
| `QuestieCorrections.lua` | 22 193 | 450 | **STAYS-IN-QUESTIE** (replaced by the registry) | it *is* the engine being replaced |
| `AutoTableUpdates.lua` | 9 471 | 440 | **STATIC** | **422** `npcFlags` values applied directly to `npcData[id][npcKeys.npcFlags]` (L434-438, guarded by `if QuestieDB.npcData[id]`); `if Questie.IsClassic` gate only (L7) — no other runtime dep; header: *"used for large table updates that are automatically generated … not all of this data is validated as its generated from external sources"* |
| `questTagInfoCorrections.lua` | 183 231 | 2 653 | **STAYS-IN-QUESTIE** | not entity data — it patches the `GetQuestTagInfo` API result (`QuestieDB.lua:567-570`); values are `{tagId, l10n(name)}` and 100 % expansion-conditional |
| `SeasonOfDiscovery.lua` | 29 902 | 659 | **STAYS-IN-QUESTIE** | rune-quest registry + player-setting-driven hiding + `GetMaxPlayerLevel()` phase detection |
| `troubleQuests.md` | 1 707 | 74 | — | scratch notes ("254 - not sure yet"), no code |

---

## 3. `l10n(...)` and `Questie.ICON_TYPE_*` usage

### 3.1 Counts (measured, whole file, `grep -o`)

| File | `l10n(` | `ICON_TYPE_*` | `extraObjectives` lines |
|---|---|---|---|
| `classicQuestFixes.lua` | **100** | **215** | 87 |
| `tbcQuestFixes.lua` | **207** | **409** | 179 |
| `wotlkQuestFixes.lua` | 479 | 762 | 414 |
| `cataQuestFixes.lua` | 552 | 1 453 | 511 |
| `mopQuestFixes.lua` | 198 | 984 | 266 |
| `sodQuestFixes.lua` | 59 | 122 | 41 |
| `questTagInfoCorrections.lua` | 2 643 | 0 | 0 |

(The `classicQuestFixes` 100 / `tbcQuestFixes` 207 figures match DESIGN.md:378-379 exactly.)
Distinct enUS strings across the six quest-fix files + questTagInfo: **991**.

`ICON_TYPE` breakdown:

* `classicQuestFixes.lua` (215): `EVENT` 93, `TALK` 38, `INTERACT` 37, `OBJECT` 35, `SLAY` 9, `NODE_FISH` 3.
* `tbcQuestFixes.lua` (409): `EVENT` 182, `INTERACT` 77, `TALK` 63, `OBJECT` 50, `SLAY` 28, `NODE_FISH` 6, `LOOT` 3.

Import line in every such file: `local l10n = QuestieLoader:ImportModule("l10n")`
(`classicQuestFixes.lua:14`).

### 3.2 Two distinct usage sites

1. **`extraObjectives` (index 29)** — `{spawnlist, iconFile, text, objectiveIndex?, {{refType, id}, …}?}`.
   `l10n()` appears **only** here (position 3), always alongside an `ICON_TYPE` at position 2.
2. **`objectives` (index 10)** — `ICON_TYPE` appears as the 3rd element of a
   creature/object/item objective tuple, or the 4th of a killCredit tuple. No `l10n` here.

### 3.3 Three representative examples — `classicQuestFixes.lua`

```lua
-- L502
[questKeys.extraObjectives] = {{nil, Questie.ICON_TYPE_OBJECT, l10n("Use the cannon"), 0, {{"object", 113531}}}},
-- L1009  (spawn list + fishing node, note the trailing comma / omitted tail fields)
[questKeys.extraObjectives] = {{{[zoneIDs.DARKSHORE]={{35.71,44.68}}}, Questie.ICON_TYPE_NODE_FISH, l10n("Fish for Darkshore Groupers"),}},
-- L1142
[questKeys.extraObjectives] = {{nil, Questie.ICON_TYPE_SLAY, l10n("Slay Gelkis centaur to increase your reputation with the Magram Clan"), 0, {{"monster", 4653},{"monster", 4647},{"monster", 4646},{"monster", 4661},{"monster", 5602},{"monster", 4648},{"monster", 4649},{"monster", 4651},{"monster", 4652}}}},
```

Bare-`ICON_TYPE` (no l10n) examples in the same file:

```lua
-- L85
[questKeys.objectives] = {nil,{{15885,nil,Questie.ICON_TYPE_EVENT}}},
-- L92
[questKeys.objectives] = {nil,nil,{{15885,nil,Questie.ICON_TYPE_EVENT}}}, -- we need event icon here
-- L424
[questKeys.objectives] = {nil,nil,{{18642,nil,Questie.ICON_TYPE_TALK}}},
```

### 3.4 Three representative examples — `tbcQuestFixes.lua`

```lua
-- L747  (spawn coords + event icon, objectiveIndex 0, no reference list)
[questKeys.extraObjectives] = {{{[zoneIDs.THE_BARRENS]={{44.7,28.1}}}, Questie.ICON_TYPE_EVENT, l10n("Defeat Centaur to summon Warlord Krom'zar"), 0}},
-- L2280
[questKeys.extraObjectives] = {{nil, Questie.ICON_TYPE_LOOT, l10n("Use the Sanctified Crystal against a wounded Uncontrolled Voidwalker"), 0, {{"monster", 16975}}}},
-- L2527  (note: no spaces after commas — formatting is not uniform)
[questKeys.extraObjectives] = {{nil,Questie.ICON_TYPE_INTERACT,l10n("Open the cage"),0,{{"object",410019}}}},
```

Bare-`ICON_TYPE` examples:

```lua
-- L1438  (killCredit objective: icon is the 4th element)
[questKeys.objectives] = {nil,nil,nil,nil,{{{15294,15274},15274,nil,Questie.ICON_TYPE_INTERACT}}},
-- L2069
[questKeys.objectives] = {{{15945,nil,Questie.ICON_TYPE_INTERACT},{15941,nil,Questie.ICON_TYPE_INTERACT}}},
-- L2114
[questKeys.objectives] = {{{16208,nil,Questie.ICON_TYPE_TALK},{16206,nil,Questie.ICON_TYPE_TALK},{16209,nil,Questie.ICON_TYPE_TALK}}},
```

**Implication:** the value stored is the *integer* 1–24 (see §6), and the `l10n` call
resolves at load time to a translated string that is then **baked into the compiled DB** —
which is why `dbCompiledLang` forces a recompile on locale change
(`QuestieInit.lua:158, 162`). DESIGN.md:381 already resolves this: store the enUS string,
translate at render time.

---

## 4. Runtime dependencies of correction files (exhaustive)

### 4.1 `UnitFactionGroup("Player")` — 21 files, always the last statement of `LoadFactionFixes`

Exact idiom:

```lua
    if UnitFactionGroup("Player") == "Horde" then
        return questFixesHorde
    else
        return questFixesAlliance
    end
```

| File:line |
|---|
| `classicQuestFixes.lua:7021` |
| `classicNPCFixes.lua:3705` |
| `classicItemFixes.lua:1652` |
| `classicObjectFixes.lua:631` |
| `tbcQuestFixes.lua:8836` |
| `tbcNPCFixes.lua:2049` |
| `tbcItemFixes.lua:623` |
| `tbcObjectFixes.lua:1137` |
| `wotlkQuestFixes.lua:8791` |
| `wotlkNPCFixes.lua:3987` |
| `wotlkItemFixes.lua:823` |
| `wotlkObjectFixes.lua:886` |
| `cataQuestFixes.lua:15896` |
| `cataNPCFixes.lua:9085` |
| `cataItemFixes.lua:1298` |
| `cataObjectFixes.lua:1788` |
| `mopQuestFixes.lua:10866` |
| `mopNPCFixes.lua:7455` |
| `mopObjectFixes.lua:1383` |
| `sodQuestFixes.lua:9729` |
| (`mopItemFixes.lua` has **no** faction function) |

### 4.2 Class / race

* `classicQuestFixes.lua:6438` — `local playerClass = UnitClassBase("player")` inside
  `LoadFactionFixes`. Used to pick per-class `nextQuestInChain` values, e.g.
  `classicQuestFixes.lua` tail: `[questKeys.nextQuestInChain] = ({["DRUID"]=8999, ["HUNTER"]=9000, …})[playerClass]`.
* `tbcQuestFixes.lua:8349` — `local playerClass = UnitClassBase("player")`
* `tbcQuestFixes.lua:8350` — `local playerRace = select(2, UnitRace("player"))`

### 4.3 `Expansions.*`

`Expansions` is `Modules/Expansions.lua`: `Era=1, Tbc=2, Wotlk=3, Cata=4, MoP=5`;
`Expansions.Current = expansionOrderLookup[WOW_PROJECT_ID or 2]`.

* `QuestieCorrections.lua:133, 141, 160, 168, 198` — the gating chain.
* `QuestieNPCBlacklist.lua:11, 12, 15-23, 24, 25, 27, 28, 29` — 15 of 19 entries.
* `QuestieQuestBlacklist.lua` — 4 265 entries; notable lines: `20, 28, 31, 45, 614, 815-824,
  845-856, 1309, 1310, 1348, 1352, 1358, 1361, 5065, 5066`.
* `questTagInfoCorrections.lua:15, 17, 18, 20, 21, 25-55, …` — pervasive.
* `Holidays/QuestieEvent.lua:157, 159, 198`.
* `Holidays/quests/*.lua` — field 7 of most rows (Brewfest 17/22/30/35/38/39/44/45;
  ChildrensWeek 36, 42; DarkmoonFaire 9-39; HallowsEnd 27-102; LoveIsInTheAir 9-36;
  LunarFestival 58-82; Midsummer 19-175; Noblegarden 10, 11; WinterVeil 22, 23, 55-63).

### 4.4 `Questie.Is*` flags (all defined in `Modules/VersionCheck.lua`)

```lua
Questie.IsMoP        = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC              -- L55
Questie.IsCata       = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC          -- L59
Questie.IsWotlk      = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC              -- L63
Questie.IsTBC        = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC    -- L67
Questie.IsClassic    = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC                    -- L71
Questie.IsEra        = Questie.IsClassic and (not C_Seasons.HasActiveSeason())   -- L75
Questie.IsSoM        = Questie.IsClassic and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfMastery)   -- L81
Questie.IsSoD        = Questie.IsClassic and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfDiscovery) -- L85
Questie.IsTitanReforged = Questie.IsWotlk and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == 109)                            -- L89
Questie.IsAnniversaryEra      = Questie.IsClassic and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.Fresh)         -- L93
Questie.IsAnniversaryTBC      = Questie.IsTBC     and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.Fresh)         -- L97
Questie.IsAnniversaryHardcore = Questie.IsClassic and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.FreshHardcore) -- L101
Questie.IsHardcore   = C_GameRules and C_GameRules.IsHardcoreActive()           -- L105
Questie.IsChinaRegion = GetCurrentRegion() == 5                                 -- L109
Questie.IsEURegion    = GetCurrentRegion() == 3                                 -- L113
```

Uses inside Corrections:

| Flag | file:line |
|---|---|
| `Questie.IsClassic` | `AutoTableUpdates.lua:7`; `QuestieCorrections.lua:262`; `Holidays/QuestieEvent.lua:257` |
| `Questie.IsSoD` | `QuestieCorrections.lua:179, 300`; `QuestieNPCBlacklist.lua:14`; `QuestieQuestBlacklist.lua:7090`; `ContentPhases/ContentPhases.lua:16`; `Holidays/QuestieEvent.lua:286`; `Holidays/quests/DarkmoonFaire.lua:9-28`; `Holidays/quests/WinterVeil.lua:16-33` |
| `Questie.IsTBC` | `QuestieQuestBlacklist.lua:7093`; `Holidays/QuestieEvent.lua:258, 288, 393` |
| `Questie.IsSoM` | `QuestieQuestBlacklist.lua:7099` |
| `Questie.IsMoP` | `QuestieQuestBlacklist.lua:7102` |
| `Questie.IsAnniversaryEra` / `IsAnniversaryHardcore` | `QuestieQuestBlacklist.lua:7096`; `Holidays/QuestieEvent.lua:257` |
| `Questie.IsTitanReforged` | `QuestieCorrections.lua:147, 207`; `QuestieQuestBlacklist.lua:1675-1722 (49 entries), 5065, 5066`; `Holidays/QuestieEvent.lua:269, 541` |
| `Questie.IsHardcore` | `QuestieCorrections.lua:218` |
| `Questie.IsChinaRegion` | `ContentPhases/ContentPhases.lua:10`; `QuestieQuestBlacklist.lua:6321` |
| `Questie.IsEURegion` | `Holidays/quests/Brewfest.lua:10, 11, 12, 23` |

### 4.5 `Questie.db.*`

| Path | file:line | Purpose |
|---|---|---|
| `Questie.db.global.isleOfQuelDanasPhase` | `QuestieCorrections.lua:188, 189` | gate + index into `IsleOfQuelDanas.quests` |
| `Questie.db.profile.showSoDRunes` | `SeasonOfDiscovery.lua:645` | hide all rune quests |
| `Questie.db.profile.showRunesOfPhase["phase"..n]` | `SeasonOfDiscovery.lua:651, 654, 655` | per-phase rune visibility |
| `Questie.db.profile.showEventQuests` | `Holidays/QuestieEvent.lua:186, 249, 439` | **only gates `print()`** — no data effect (confirmed; matches DESIGN.md:685-691) |

`QuestiePlayer` is **not** referenced anywhere under `Database/Corrections/`.

### 4.6 Calendar / date / CVar (all in `Holidays/QuestieEvent.lua`)

| Line | API |
|---|---|
| 135-138 | `Questie:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", …)` then `UnregisterEvent` |
| 142-143 | `C_Calendar.OpenCalendar()`, `C_Calendar.SetMonth(0)` |
| 147 | `local year = date("%y")` |
| 194 | `local shouldShowDmfEvents = GetCVarBool("calendarShowDarkmoon")` |
| 195 / 254 | `SetCVar("calendarShowDarkmoon", "1")` / restore |
| 199, 284, 358, 455 | `QuestieCompat.GetCurrentCalendarTime()` |
| 200 | `C_Calendar.GetNumDayEvents(0, currentDate.monthDay)` |
| 203 | `C_Calendar.GetHolidayInfo(0, currentDate.monthDay, i)` — matched against `DMF_CALENDAR_ICON_TEXTURES = {235446, 235447, 235448}` |
| 278 | `if C_Calendar == nil then` — private-server band-aid, returns `DMF_LOCATIONS.NONE` |
| 330, 333 | `C_Calendar.GetMonthInfo()` / `GetMonthInfo(monthOffset)` → `.firstWeekday` |
| 356-357 | `time({year=2023, month=12, day=4, …})` SoD DMF epoch |
| 613 | (`SeasonOfDiscovery.lua`) `GetMaxPlayerLevel()` |

`QuestieCorrections.lua:153` — `GetLocale() == "zhCN"`.

### 4.7 Module import graph of `QuestieCorrections.lua` (L1-78)

`QuestieDB, Expansions, ZoneDB, QuestieLib, RamerDouglasPeucker, QuestieQuestBlacklist,
QuestieNPCBlacklist, QuestieItemBlacklist, HardcoreBlacklist, SeasonOfDiscovery,
BlacklistFilter, QuestieQuestFixes, QuestieClassicQuestReputationFixes, QuestieNPCFixes,
QuestieItemFixes, QuestieObjectFixes, QuestieTBC{Quest,Npc,Item,Object}Fixes,
QuestieWotlk{Quest,Npc,Item,Object}Fixes, Cata{Quest,Npc,Item,Object}Fixes,
Mop{Quest,Npc,Item,Object}Fixes, IsleOfQuelDanas, QuestieItemStartFixes.`

`QuestieLoader:ImportModule` auto-creates an empty stub for a module that was never loaded
(`Modules/Libs/QuestieLoader.lua:28-35`), which is why importing `HardcoreBlacklist` /
`SeasonOfDiscovery` on Cata (where their files are not in the `.toc`) does not error — the
guarded calls simply never run.

### 4.8 TOC load order (which corrections exist per flavor)

`Questie-Classic.toc:80-124`, `Questie-BCC.toc:80-115`, `Questie-WOTLKC.toc:80-123`,
`Questie-Cata.toc:80-129`, `Questie-Mists.toc:80-135`.

Common prefix in all five: `BlacklistFilter → QuestieCorrections → QuestieItemBlacklist →
QuestieNPCBlacklist → QuestieQuestBlacklist → questTagInfoCorrections`.

Per-flavor presence:

| File | Classic | BCC | WOTLKC | Cata | Mists |
|---|---|---|---|---|---|
| `AutoTableUpdates.lua` (**first** correction file when present) | ✔ (L81) | ✔ (L81) | ✔ (L81) | ✘ | ✘ |
| `HardcoreBlacklist.lua` | ✔ (L88) | ✘ | ✘ | ✘ | ✘ |
| `SeasonOfDiscovery.lua` | ✔ (L89) | ✘ | ✘ | ✘ | ✘ |
| `ContentPhases/ContentPhases.lua` | ✔ | ✔ | ✔ | **✘** | ✔ |
| `ContentPhases/Anniversary.lua` | ✔ | ✘ | ✘ | ✘ | ✘ |
| `ContentPhases/SeasonOfDiscovery.lua` | ✔ | ✘ | ✘ | ✘ | ✘ |
| `ContentPhases/SeasonOfMastery.lua` | ✔ | ✘ | ✘ | ✘ | ✘ |
| `ContentPhases/BurningCrusade.lua` | ✘ | ✔ | ✘ | ✘ | ✘ |
| `ContentPhases/MistsOfPandaria.lua` | ✘ | ✘ | ✘ | ✘ | ✔ |
| `Holidays/quests/Brewfest.lua` | **✘** | ✔ | ✔ | ✔ | ✔ |
| `Holidays/quests/DayOfTheDead.lua` | ✘ | ✘ | ✔ | ✔ | ✔ |
| `Holidays/quests/Noblegarden.lua` | ✘ | ✘ | ✔ | ✔ | ✔ |
| `Holidays/quests/PilgrimsBounty.lua` | ✘ | ✘ | ✔ | ✔ | ✔ |
| `Automatic/itemStartFixes.lua` + `classicQuestReputationFixes.lua` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `Automatic/sodBase*.lua` (4) | ✔ only | ✘ | ✘ | ✘ | ✘ |
| `sod*Fixes.lua` (4) | ✔ only | ✘ | ✘ | ✘ | ✘ |
| `classic*Fixes.lua` (4) | ✔ | ✔ | ✔ | ✔ | ✔ |
| `tbc*Fixes.lua` (4) | ✘ | ✔ | ✔ | ✔ | ✔ |
| `wotlk*Fixes.lua` (4) | ✘ | ✘ | ✔ | ✔ | ✔ |
| `cata*Fixes.lua` (4) | ✘ | ✘ | ✘ | ✔ | ✔ |
| `mop*Fixes.lua` (4) | ✘ | ✘ | ✘ | ✘ | ✔ |

The 4 `*.test.lua` files are in no `.toc` (busted only).
Note: `Database\DropTables\data\itemDropCorrections.lua` (22 334 B) is a *separate*
corrections family outside this directory, loaded in every toc; module
`QuestieItemDropCorrections`, keys from `DropDB.correctionKeys`.

---

## 5. The SoD parallel database

### 5.1 `Questie.db.global.sod.*`

Declared once as an empty table default: `Modules/Options/QuestieOptionsDefaults.lua:243`
→ `sod = {}, -- Special place for the SoD database`, inside the `global` block
(lines 237-245).

Keys written by the compiler, `Database/compiler.lua:999-1005`:

```lua
if Questie.IsSoD then
    Questie.db.global.sod[databaseKey.."Bin"]  = stream:Save()
    Questie.db.global.sod[databaseKey.."Ptrs"] = QuestieDBCompiler:EncodePointerMap(stream, pointerMap)
else
    Questie.db.global[databaseKey.."Bin"]  = stream:Save()
    Questie.db.global[databaseKey.."Ptrs"] = QuestieDBCompiler:EncodePointerMap(stream, pointerMap)
end
```

with `databaseKey ∈ {npc, quest, obj, item}` ⇒ 8 blobs:
`npcBin/npcPtrs/questBin/questPtrs/objBin/objPtrs/itemBin/itemPtrs`.

Metadata, `Database/compiler.lua:1101-1104`:
`sod.dbCompiledOnVersion`, `sod.dbCompiledLang`, `sod.dbIsCompiled = true`,
`sod.dbCompiledCount = (… or 0) + 1`.

Read side, `Database/QuestieDB.lua:270-290` — comment *"For now we store both, the SoD
database and the Era/HC database"* — selects `Questie.db.global.sod.*` vs
`Questie.db.global.*` on `Questie.IsSoD`.

Other touch points: `Database/QuestieDB.lua:250` (recompile popup),
`Modules/Options/AdvancedTab/QuestieOptionsAdvanced.lua:42`,
`Modules/QuestieMenu/QuestieMenu.lua:437`, `Modules/QuestieInit.lua:152-154, 178`.

So: **two full compiled binary databases coexist in SavedVariables on a Classic install**,
one keyed under `global.*` and one under `global.sod.*`. `dbCompiledExpansion` is *not*
duplicated — `QuestieInit.lua:162` always checks the shared
`Questie.db.global.dbCompiledExpansion ~= WOW_PROJECT_ID`.

### 5.2 `Database/Corrections/SeasonOfDiscovery.lua` (29 902 B, 659 lines)

Contains exactly three things:

1. `local runeQuestsInSoD = { [questId] = phaseNumber, … }` (L11-607) — **584 entries**,
   values 1..5, e.g. `[1470] = 1, … [90322] = 5, [91000] = 1, [91001] = 1`.
2. `SeasonOfDiscovery.Initialize()` (L612-630) — automatic phase detection from
   `GetMaxPlayerLevel()`: 25→`ContentPhases.activePhases.SoD = 1`, 40→2, 50→3,
   60 (and current `<= 4`) →4; otherwise logs a failure and leaves the value alone. Called
   from `Modules/QuestieInit.lua:418`. Comment explains the delay: *"if GetMaxPlayerLevel()
   is called too early after initial login (not reloads), the game returns 60 even in early
   phases"*.
3. `QuestieDB.IsSoDRuneQuest(questId)` (L634-636) and
   `QuestieDB.IsRuneAndShouldBeHidden(questId)` (L640-659):

```lua
function QuestieDB.IsRuneAndShouldBeHidden(questId)
    if (not QuestieDB.IsSoDRuneQuest(questId)) then return false end
    if (not Questie.db.profile.showSoDRunes) then return true
    elseif questId == 91000 or questId == 91001 then return false end -- Rune Broker quests are always shown
    local showRunesOfPhase = Questie.db.profile.showRunesOfPhase
    local phaseOfRuneQuest = runeQuestsInSoD[questId]
    if showRunesOfPhase["phase" .. phaseOfRuneQuest] ~= nil then
        return not showRunesOfPhase["phase" .. phaseOfRuneQuest]
    end
    return false
end
```

**Important:** this file defines the module `SeasonOfDiscovery` but contains **none** of the
`Load*` functions QuestieCorrections calls. Those live in other files that all
`ImportModule("SeasonOfDiscovery")` and attach onto it:

| Function | Defined at |
|---|---|
| `SeasonOfDiscovery:LoadQuests()` | `sodQuestFixes.lua:18` |
| `SeasonOfDiscovery:LoadFactionQuestFixes()` | `sodQuestFixes.lua:9239` |
| `SeasonOfDiscovery:LoadNPCs()` | `sodNPCFixes.lua:8` |
| `SeasonOfDiscovery:LoadItems()` | `sodItemFixes.lua:6` |
| `SeasonOfDiscovery:LoadObjects()` | `sodObjectFixes.lua:8` |
| `SeasonOfDiscovery:LoadBaseQuests()` | `Automatic/sodBaseQuests.lua:9` |
| `SeasonOfDiscovery:LoadBaseNPCs()` | `Automatic/sodBaseNPCs.lua:11` |
| `SeasonOfDiscovery:LoadBaseItems()` | `Automatic/sodBaseItems.lua:9` |
| `SeasonOfDiscovery:LoadBaseObjects()` | `Automatic/sodBaseObjects.lua:9` |

### 5.3 What `Automatic/sodBase*.lua` actually do

They return **full new entity rows** (not field patches) for SoD-only ids, merged into the
Era raw tables by `_LoadCorrections` (which creates the id if missing). Example
`Automatic/sodBaseQuests.lua:15-24`:

```lua
[76156] = {
    [questKeys.name] = "Stalk With The Earthmother",
    [questKeys.startedBy] = {{205729}},
    [questKeys.finishedBy] = {{205729}},
    [questKeys.requiredLevel] = 4,
    [questKeys.questLevel] = 6,
    [questKeys.requiredRaces] = raceIDs.ALL_HORDE,
    [questKeys.requiredClasses] = classIDs.SHAMAN,
    [questKeys.objectivesText] = {"Sneak into the Venture Company mine…"},
    [questKeys.objectives] = {nil,nil,{{206157}}},
},
```

`sodBaseItems.lua` rows are mostly all-nil stubs (`[itemKeys.npcDrops]=nil, objectDrops=nil,
itemDrops=nil, vendors=nil, startQuest=nil`), i.e. after Lua constructor evaluation they
collapse to `{[itemKeys.name] = "…"}` — 27 509 `= nil,` lines that produce nothing.
Same pattern in `sodBaseObjects.lua` (`zoneID`, `spawns`, `questStarts`, `questEnds`).

Ordering guarantee: `QuestieCorrections.lua:301-308` always calls `LoadBase*` before the
matching `Load*` fix, so hand-written `sod*Fixes.lua` wins.

---

## 6. `Questie.ICON_TYPE_*` constants — exact list

Defined in `Questie.lua:265-288` (module-level, after `Questie.usedIcons = {}` on L263):

```lua
Questie.ICON_TYPE_SLAY = 1
Questie.ICON_TYPE_LOOT = 2
Questie.ICON_TYPE_EVENT = 3
Questie.ICON_TYPE_OBJECT = 4
Questie.ICON_TYPE_TALK = 5
Questie.ICON_TYPE_AVAILABLE = 6
Questie.ICON_TYPE_AVAILABLE_GRAY = 7
Questie.ICON_TYPE_COMPLETE = 8
Questie.ICON_TYPE_GLOW = 9
Questie.ICON_TYPE_REPEATABLE = 10
Questie.ICON_TYPE_REPEATABLE_COMPLETE = 11
Questie.ICON_TYPE_INCOMPLETE = 12
Questie.ICON_TYPE_EVENTQUEST = 13
Questie.ICON_TYPE_EVENTQUEST_COMPLETE = 14
Questie.ICON_TYPE_PVPQUEST = 15
Questie.ICON_TYPE_PVPQUEST_COMPLETE = 16
Questie.ICON_TYPE_INTERACT = 17
Questie.ICON_TYPE_SODRUNE = 18
Questie.ICON_TYPE_MOUNT_UP = 19
Questie.ICON_TYPE_NODE_FISH = 20
Questie.ICON_TYPE_NODE_HERB = 21
Questie.ICON_TYPE_NODE_ORE = 22
Questie.ICON_TYPE_CHEST = 23
Questie.ICON_TYPE_PET_BATTLE = 24
```

They are indices into `Questie.usedIcons[...]`, populated by `Questie.SetIcons()`
(`Questie.lua:291+`) from `Questie.db.profile.ICON_*` or the `Questie.icons[...]` texture
path table (`Questie.lua:~230-261`). Files that reference `ICON_TYPE_*`:
`Questie.lua`, `Database/QuestieDB.lua`, the six `*QuestFixes.lua`,
`Modules/QuestieNameplate.lua`, `Modules/Libs/QuestieLib.lua`,
`Modules/QuestieDBMIntegration.lua`, `Modules/Map/QuestieMapUtils.lua`,
`Modules/Quest/QuestFinisher.lua` (+ its test), `Modules/Quest/QuestieQuestPrivates.lua`.

Only 7 of the 24 ever appear inside correction data:
`SLAY(1), LOOT(2), EVENT(3), OBJECT(4), TALK(5), INTERACT(17), NODE_FISH(20)`.

---

## 7. Gotchas for the implementer

1. **`= nil` in a correction table is dead code.** `pairs()` never sees it. Do not port
   these as "delete" instructions. 35 000+ such lines exist, almost all in the generated
   SoD base files.
2. **`{}` means delete — but only through `QuerySingle`.** `compiler.lua:1136-1141` converts
   an empty-table override to nil; `handle.Query` (L1198-1199) and `handle.QueryValidator`
   (L1242) do not. Behaviour differs by access path today.
3. **`addOverride` can only add/replace, never remove**, and on first insert it stores the
   *caller's table by reference* (`override_table[id] = data`) — subsequent merges mutate the
   correction file's own returned table. DESIGN.md:352-356 already flags this.
4. **Mop `LoadContentPhaseFixes()` returns `{}` in all three files** (`mopQuestFixes.lua:10874`,
   `mopNPCFixes.lua:7463`, `mopObjectFixes.lua:1391`). The MinimalInit calls at L173-175 are
   currently no-ops but are load-bearing extension points.
5. **`mopItemFixes.lua` has no `LoadFactionFixes`**, so `MinimalInit` L169-171 deliberately
   omits item. Do not "fix" this by symmetry.
6. **Wotlk NPC ordering is significant**: `LoadAutomatics()` (L280) runs *before* `Load()`
   (L281) so hand fixes win. Every other expansion has only one `Load`.
7. **`Cata` and `Mists` TOCs do not load `ContentPhases/ContentPhases.lua`.** Blacklist
   entries referencing `ContentPhases.activePhases.TBC` (e.g. `QuestieQuestBlacklist.lua:1309,
   1310, 1348, 1352, 1358, 1361`; `QuestieNPCBlacklist.lua:24, 25, 27, 29`) survive only
   because Lua short-circuits the surrounding `or`/`and`. Any reordering of those expressions
   crashes Cata/Mists with "attempt to index a nil value".
8. **`isleOfQuelDanasPhase` lives in two places.** Default is declared under `profile`
   (`QuestieOptionsDefaults.lua:213`) and the options UI reads/writes
   `Questie.db.profile.isleOfQuelDanasPhase`
   (`Modules/Options/AdvancedTab/QuestieOptionsAdvanced.lua:186, 188`), but
   `QuestieCorrections.lua:188-189`, `Migration.lua:114-118`, `QuestieInit.lua:309` and
   `QuestEventHandler.lua:295` use `Questie.db.global.isleOfQuelDanasPhase`.
   `AvailableQuests.lua:402` uses `profile`. Pre-existing split-brain — do not "unify" it
   silently while porting.
9. **`hiddenQuests` is mutated after `MinimalInit`.** `QuestieEvent:Load()` deletes entries
   (`QuestieEvent.lua:242, 403, 418, 421, 432`) and adds entries (`:428, 435`) at runtime.
   Any frozen/immutable composed view must accommodate a post-init recomposition.
10. **`filterExpansion` mutates its argument and returns it**; the blacklist `Load()` result
    is not copied. `false` disappears, `"HIDE_ON_MAP"` survives.
11. **`_LoadCorrections` will happily create ids that don't exist** (`QuestieDB[table][id] = {}`)
    unless `noNewEntries` is passed. That is how SoD base rows get in — and how a typo'd id
    silently creates a ghost entity.
12. **The `PreCompile` object loop never increments `count`** (`QuestieCorrections.lua:439-449`),
    so it never yields. Harmless today, but do not copy the pattern.
13. **`Initialize`'s faction-inference pass (L313-350) rewrites `requiredRaces` from NPC
    `friendlyToFaction`.** This is a derived-data step, not a correction file, and it depends
    on npc corrections having already been applied. It must be reproduced (or replaced) in the
    generator or a whole class of quests loses its faction.
14. **`l10n()` results are baked into the compiled DB**, which is the sole reason
    `dbCompiledLang` exists (`QuestieInit.lua:154, 158, 162`; `compiler.lua:1102`).
    Storing enUS + translating at render time removes that recompile trigger (DESIGN.md
    phase 9).
15. **`QuestieLoader:ImportModule` silently creates empty stub modules**
    (`Modules/Libs/QuestieLoader.lua:28-35`). A missing correction file therefore produces
    "attempt to call a nil value" at the call site, not at import — errors surface late.
16. **`Automatic/classicQuestReputationFixes.lua` is Era-only by policy**, not by data:
    `QuestieCorrections.lua:262-265` comments *"This data is only correct for Era/SoX, for
    the other expansions we trust the base DB"*. If it is made STATIC it must be baked into
    the Vanilla flavor only.
17. **`sodBaseItems.lua` is 2.12 MB of mostly-nil rows** — the single biggest win available
    from a nil-stripping pass, and evidence that the SoD base tables were machine-emitted
    without post-processing.
