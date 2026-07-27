# Recon 01 — Questie entity schema (exhaustive)

Source of truth: `/home/logon/projects/Questie-clones/Questie-toc/Questie/`
All paths below are absolute unless prefixed `Database/` (relative to the Questie addon root
`/home/logon/projects/Questie-clones/Questie-toc/Questie/`).

Read-only recon. Nothing was modified.

---

## 0. Files read

| File | Purpose |
|---|---|
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/questDB.lua` | canonical quest schema (267 lines) |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/npcDB.lua` | canonical npc schema (86 lines) |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/itemDB.lua` | canonical item schema (125 lines) |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/objectDB.lua` | canonical object schema (43 lines) |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/compiler.lua` | binary compiler, defines all reader/writer/skipper types |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/QuestieDB.lua` | creates the `QuestieDB` module (line 2) |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/Libs/QuestieLoader.lua` | `QuestieLoader:CreateModule` / `ImportModule` |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/Expansions.lua` | `Expansions.Current/Era/Tbc/Wotlk/Cata/MoP` |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/QuestieInit.lua` | `LoadDatabase()` — loadstring of the `[[...]]` blobs |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/Corrections/QuestieCorrections.lua` | applies corrections onto the loaded tables |
| `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/Constants.lua` | `QuestieDB.sortKeys` (zoneOrSort negative values) |

---

## 1. FIELD COUNTS AT A GLANCE (canonical Questie)

| Entity | `*Keys` fields | `*CompilerTypes` entries | `*CompilerOrder` entries | Max index actually present in shipped data |
|---|---|---|---|---|
| quest  | **36** | 36 | 36 | **26** |
| npc    | **15** | 15 | 15 | **15** |
| item   | **16** | 16 | 16 | **14** |
| object | **7**  | 7  | 7  | **6**  |

Every `*CompilerOrder` is a complete permutation of its `*Keys` — verified programmatically:
no key missing, no extras, no duplicates, for all four entity types.

---

## 2. QUEST — `Database/questDB.lua`

### 2.1 Header / load-time requirements (lines 1–2)

```lua
---@class QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
```

Nothing else. Only mock needed: global `QuestieLoader` with `:ImportModule(name)`.

### 2.2 `QuestieDB.questKeys` — lines 6–54 — **36 fields** (verbatim)

```lua
---@class DatabaseQuestKeys
QuestieDB.questKeys = {
    ['name'] = 1, -- string
    ['startedBy'] = 2, -- table
        --['creatureStart'] = 1, -- table {creature(int),...}
        --['objectStart'] = 2, -- table {object(int),...}
        --['itemStart'] = 3, -- table {item(int),...}
    ['finishedBy'] = 3, -- table
        --['creatureEnd'] = 1, -- table {creature(int),...}
        --['objectEnd'] = 2, -- table {object(int),...}
    ['requiredLevel'] = 4, -- int
    ['questLevel'] = 5, -- int
    ['requiredRaces'] = 6, -- bitmask
    ['requiredClasses'] = 7, -- bitmask
    ['objectivesText'] = 8, -- table: {string,...}, Description of the quest. Auto-complete if nil.
    ['triggerEnd'] = 9, -- table: {text, {[zoneID] = {coordPair,...},...}}
    ['objectives'] = 10, -- table
        --['creatureObjective'] = 1, -- table {{creature(int), text(string), iconFile},...}, If text is nil the default "<Name> slain x/y" is used
        --['objectObjective'] = 2, -- table {{object(int), text(string), iconFile},...}
        --['itemObjective'] = 3, -- table {{item(int), text(string), iconFile},...}
        --['reputationObjective'] = 4, -- table: {faction(int), value(int)}
        --['killCreditObjective'] = 5, -- table: {{{creature(int), ...}, baseCreatureID, baseCreatureText, iconFile}, ...}
        --['spellObjective'] = 6, -- table: {{spell(int), text(string), item(int)},...}
    ['sourceItemId'] = 11, -- int, item provided by quest starter
    ['preQuestGroup'] = 12, -- table: {quest(int)}
    ['preQuestSingle'] = 13, -- table: {quest(int)}
    ['childQuests'] = 14, -- table: {quest(int)}
    ['inGroupWith'] = 15, -- table: {quest(int)}
    ['exclusiveTo'] = 16, -- table: {quest(int)}
    ['zoneOrSort'] = 17, -- int, >0: AreaTable.dbc ID; <0: QuestSort.dbc ID
    ['requiredSkill'] = 18, -- table: {skill(int), value(int)}
    ['requiredMinRep'] = 19, -- table: {faction(int), value(int)}
    ['requiredMaxRep'] = 20, -- table: {faction(int), value(int)}
    ['requiredSourceItems'] = 21, -- table: {item(int), ...} Items that are not an objective but still needed for the quest.
    ['nextQuestInChain'] = 22, -- int: if this quest is active/finished, the current quest is not available anymore
    ['questFlags'] = 23, -- bitmask: see https://github.com/cmangos/issues/wiki/Quest_template#questflags
    ['specialFlags'] = 24, -- bitmask: 1 = Repeatable, 2 = Needs event, 4 = Monthly reset (req. 1). See https://github.com/cmangos/issues/wiki/Quest_template#specialflags
    ['parentQuest'] = 25, -- int, the ID of the parent quest that needs to be active for the current one to be available. See also 'childQuests' (field 14)
    ['reputationReward'] = 26, -- table: {{faction(int), value(int)},...}, a list of reputation rewarded upon quest completion
    ['breadcrumbForQuestId'] = 27, -- int: quest ID for the quest this optional breadcrumb quest leads to
    ['breadcrumbs'] = 28, -- table: {questID(int), ...} quest IDs of the breadcrumbs that lead to this quest
    ['extraObjectives'] = 29, -- table: {{spawnlist, iconFile, text, objectiveIndex (optional), {{dbReferenceType, id}, ...} (optional)},...}, a list of hidden special objectives for a quest. Similar to requiredSourceItems
    ['requiredSpell'] = 30, -- int: quest is only available if character has this spellID
    ['requiredSpecialization'] = 31, -- int: quest is only available if character meets the spec requirements. Use QuestieProfessions.specializationKeys for having a spec, or QuestieProfessions.professionKeys to indicate having the profession with no spec. See QuestieProfessions.lua for more info.
    ['requiredMaxLevel'] = 32, -- int: the maximum level at which the quest is still available
    ['availableUntilCompleted'] = 33, -- int: the current quest is available until this quest is turned in
    ['availableStartingWith'] = 34, -- int: the ID of the quest that needs to be in quest log OR turned in for the current one to be available.
    ['requiredRanks'] = 35, -- table: {{skill(int), value(int)}}. Table of professions and ranks to be checked with OR logic
    ['disabledByQuest'] = 36, -- int: quest that, if in player's quest log, makes current quest unavailable for the duration
}
```

Also built at lines 56–59: `QuestieDB.questKeysReversed[id] = key`.
Also built at lines 263–266: `QuestieDB._questAdapterQueryOrder[id] = key` (identical content to `questKeysReversed`).

### 2.3 `QuestieDB.questCompilerTypes` — lines 61–98 (verbatim)

```lua
QuestieDB.questCompilerTypes = {
    ['name'] = "u8string",
    ['startedBy'] = "questgivers",
    ['finishedBy'] = "questgivers",
    ['requiredLevel'] = "u8",
    ['questLevel'] = "s16",
    ['requiredRaces'] = "u32",
    ['requiredClasses'] = "u16",
    ['objectivesText'] = "u8u16stringarray",
    ['triggerEnd'] = "trigger",
    ['objectives'] = "objectives",
    ['sourceItemId'] = "u24",
    ['preQuestGroup'] = "u8s24array",
    ['preQuestSingle'] = "u8u24array",
    ['childQuests'] = "u8u24array",
    ['inGroupWith'] = "u8u24array",
    ['exclusiveTo'] = "u8u24array",
    ['zoneOrSort'] = "s16",
    ['requiredSkill'] = "u12pair",
    ['requiredMinRep'] = "s24pair",
    ['requiredMaxRep'] = "s24pair",
    ['requiredSourceItems'] = "u8u24array",
    ['nextQuestInChain'] = "u24",
    ['questFlags'] = "u24",
    ['specialFlags'] = "u16",
    ['parentQuest'] = "u24",
    ['reputationReward'] = "u8s24pairs",
    ['breadcrumbForQuestId'] = "u24",
    ['breadcrumbs'] = "u8u24array",
    ['extraObjectives'] = "extraobjectives",
    ['requiredSpell'] = "s24",
    ['requiredSpecialization'] = "u24",
    ['requiredMaxLevel'] = "u8",
    ['availableUntilCompleted'] = "u24",
    ['availableStartingWith'] = "u24",
    ['requiredRanks'] = "u8s24pairs",
    ['disabledByQuest'] = "u24",
}
```

Note the asymmetry: `preQuestGroup` = `u8s24array` (SIGNED 24) while `preQuestSingle`,
`childQuests`, `inGroupWith`, `exclusiveTo`, `requiredSourceItems`, `breadcrumbs` are all
`u8u24array` (unsigned). Negative values in `preQuestGroup` are meaningful in Questie.
`requiredSpell` is `s24` (signed) while every other single-int field is `u24`/`u8`/`u16`/`u32`.

### 2.4 `QuestieDB.questCompilerOrder` — lines 100–109 (verbatim, 36 entries)

```lua
QuestieDB.questCompilerOrder = { -- order easily skipable data first for efficiency
    --static size
    'requiredLevel', 'questLevel', 'requiredRaces', 'requiredClasses', 'sourceItemId', 'zoneOrSort', 'requiredSkill',
    'requiredMinRep', 'requiredMaxRep', 'nextQuestInChain', 'questFlags', 'specialFlags', 'parentQuest', 'requiredSpell',
    'requiredSpecialization', 'requiredMaxLevel', 'breadcrumbForQuestId', 'availableUntilCompleted', 'availableStartingWith', 'disabledByQuest',

    -- variable size
    'name', 'preQuestGroup', 'preQuestSingle', 'childQuests', 'inGroupWith', 'exclusiveTo', 'requiredSourceItems',
    'objectivesText', 'triggerEnd', 'startedBy', 'finishedBy', 'breadcrumbs', 'objectives', 'reputationReward', 'extraObjectives', 'requiredRanks'
}
```

Flat list form (index = position in the compiled binary record):
```
1 requiredLevel        2 questLevel           3 requiredRaces          4 requiredClasses
5 sourceItemId         6 zoneOrSort           7 requiredSkill          8 requiredMinRep
9 requiredMaxRep      10 nextQuestInChain    11 questFlags            12 specialFlags
13 parentQuest        14 requiredSpell       15 requiredSpecialization 16 requiredMaxLevel
17 breadcrumbForQuestId 18 availableUntilCompleted 19 availableStartingWith 20 disabledByQuest
21 name               22 preQuestGroup       23 preQuestSingle        24 childQuests
25 inGroupWith        26 exclusiveTo         27 requiredSourceItems   28 objectivesText
29 triggerEnd         30 startedBy           31 finishedBy            32 breadcrumbs
33 objectives         34 reputationReward    35 extraObjectives       36 requiredRanks
```

### 2.5 Other tables in `questDB.lua`

* `QuestieDB.questFlags` — lines 111–127 (NONE=0, STAY_ALIVE=1, PARTY_ACCEPT=2, EXPLORATION=4,
  SHARABLE=8, UNUSED1=16, EPIC=32, RAID=64, UNUSED2=128, UNKNOWN=256, HIDDEN_REWARDS=512,
  AUTO_REWARDED=1024, DAILY=4096, WEEKLY=32768, MONTHLY=65536)
* `QuestieDB.factionIDs` — lines 129–260 (132 named faction constants, BOOTY_BAY=21 … DARKSPEAR_REBELLION=1440)

---

## 3. NPC — `Database/npcDB.lua`

### 3.1 Header / load-time requirements (lines 1–4)

```lua
---@class QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
---@type Expansions
local Expansions = QuestieLoader:ImportModule("Expansions");
```

**This is the only one of the four schema files with extra dependencies.** See §7.

### 3.2 `QuestieDB.npcKeys` — lines 7–24 — **15 fields** (verbatim)

```lua
---@class DatabaseNpcKeys
QuestieDB.npcKeys = {
    ['name'] = 1, -- string
    ['minLevelHealth'] = 2, -- int
    ['maxLevelHealth'] = 3, -- int
    ['minLevel'] = 4, -- int
    ['maxLevel'] = 5, -- int
    ['rank'] = 6, -- int, see https://github.com/cmangos/issues/wiki/creature_template#rank
    ['spawns'] = 7, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['waypoints'] = 8, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['zoneID'] = 9, -- guess as to where this NPC is most common
    ['questStarts'] = 10, -- table {questID(int),...}
    ['questEnds'] = 11, -- table {questID(int),...}
    ['factionID'] = 12, -- int, see https://github.com/cmangos/issues/wiki/FactionTemplate.dbc
    ['friendlyToFaction'] = 13, -- string, Contains "A" and/or "H" depending on NPC being friendly towards those factions. nil if hostile to both.
    ['subName'] = 14, -- string, The title or function of the NPC, e.g. "Weapon Vendor"
    ['npcFlags'] = 15, -- int, Bitmask containing various flags about the NPCs function (Vendor, Trainer, Flight Master, etc.).
                       -- For flag values see https://github.com/cmangos/mangos-classic/blob/172c005b0a69e342e908f4589b24a6f18246c95e/src/game/Entities/Unit.h#L536
}
```

`QuestieDB.npcKeysReversed` built lines 26–29; `QuestieDB._npcAdapterQueryOrder` lines 82–85.

### 3.3 `QuestieDB.npcCompilerTypes` — lines 32–48 (verbatim)

```lua
QuestieDB.npcCompilerTypes = {
    ['name'] = "u8string",
    ['minLevelHealth'] = "u32",
    ['maxLevelHealth'] = "u32",
    ['minLevel'] = "u8",
    ['maxLevel'] = "u8",
    ['rank'] = "u8",
    ['spawns'] = "spawnlist",
    ['waypoints'] = "waypointlist",
    ['zoneID'] = "u16",
    ['questStarts'] = "u8u24array",
    ['questEnds'] = "u8u24array",
    ['factionID'] = "u16",
    ['friendlyToFaction'] = "faction",
    ['subName'] = "u8string",
    ['npcFlags'] = "u32",
}
```

### 3.4 `QuestieDB.npcCompilerOrder` — lines 50–56 (verbatim, 15 entries)

```lua
QuestieDB.npcCompilerOrder = { -- order easily skipable data first for efficiency
    --static size
    'minLevelHealth', 'maxLevelHealth', 'minLevel', 'maxLevel', 'rank', 'zoneID', 'factionID', 'friendlyToFaction', 'npcFlags',

    -- variable size
    'name', 'spawns', 'waypoints', 'questStarts', 'questEnds', 'subName'
}
```

### 3.5 `QuestieDB.npcFlags` — lines 58–79 (expansion-dependent!)

```lua
---@enum NpcFlags
QuestieDB.npcFlags = {
    NONE = 0,
    GOSSIP = 1,
    QUEST_GIVER = 2,
    VENDOR = Questie.IsClassic and 4 or 128,
    FLIGHT_MASTER = Questie.IsClassic and 8 or 8192,
    TRAINER = 16,
    SPIRIT_HEALER = Questie.IsClassic and 32 or 16384,
    SPIRIT_GUIDE = Questie.IsClassic and 64 or 32768,
    INNKEEPER = Questie.IsClassic and 128 or 65536,
    BANKER = Questie.IsClassic and 256 or 131072,
    PETITIONER = Questie.IsClassic and 512 or 262144,
    TABARD_DESIGNER = Questie.IsClassic and 1024 or 524288,
    BATTLEMASTER = Questie.IsClassic and 2048 or 1048576,
    AUCTIONEER = Questie.IsClassic and 4096 or 2097152,
    STABLEMASTER = Questie.IsClassic and 8192 or 4194304,
    REPAIR = Questie.IsClassic and 16384 or 4096,
    BARBER = (Expansions.Current >= Expansions.Wotlk) and 33554432 or nil,
    ARCANE_REFORGER = Expansions.Current >= Expansions.Cata and 134217728 or nil,
    TRANSMOGRIFIER = Expansions.Current >= Expansions.Cata and 268435456 or nil
}
```

---

## 4. ITEM — `Database/itemDB.lua`

### 4.1 Header / load-time requirements (lines 1–2)

```lua
---@class QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
```

### 4.2 `QuestieDB.itemKeys` — lines 5–22 — **16 fields** (verbatim)

```lua
---@class DatabaseItemKeys
QuestieDB.itemKeys = {
    ['name'] = 1, -- string
    ['npcDrops'] = 2, -- table or nil, NPC IDs
    ['objectDrops'] = 3, -- table or nil, object IDs
    ['itemDrops'] = 4, -- table or nil, item IDs
    ['startQuest'] = 5, -- int or nil, ID of the quest started by this item
    ['questRewards'] = 6, -- table or nil, quest IDs
    ['flags'] = 7, -- int or nil, see: https://github.com/cmangos/issues/wiki/Item_template#flags
    ['foodType'] = 8, -- int or nil, see https://github.com/cmangos/issues/wiki/Item_template#foodtype
    ['itemLevel'] = 9, -- int, the level of this item
    ['requiredLevel'] = 10, -- int, the level required to equip/use this item
    ['ammoType'] = 11, -- int,
    ['class'] = 12, -- int,
    ['subClass'] = 13, -- int,
    ['vendors'] = 14, -- table or nil, NPC IDs
    ['relatedQuests'] = 15, -- table or nil, IDs of quests that are related to this item
    ['teachesSpell'] = 16, -- int, spellID taught by this item upon use
}
```

`itemKeysReversed` lines 24–27; `_itemAdapterQueryOrder` lines 121–124.
`QuestieDB.itemClasses = { QUEST = 12 }` at lines 89–91.
Lines 29–87 are a large comment block documenting item class/subClass combinations.

### 4.3 `QuestieDB.itemCompilerTypes` — lines 93–110 (verbatim; note DOUBLE-quoted keys here)

```lua
QuestieDB.itemCompilerTypes = {
    ["foodType"] = "u8",
    ["itemLevel"] = "u16",
    ["flags"] = "u32",
    ["startQuest"] = "u24",
    ["requiredLevel"] = "u8",
    ["ammoType"] = "u8",
    ["class"] = "u8",
    ["subClass"] = "u8",
    ["npcDrops"] = "u16u24array",
    ["objectDrops"] = "u8u24array",
    ["itemDrops"] = "u8u24array",
    ["vendors"] = "u16u24array",
    ["relatedQuests"] = "u8u24array",
    ["questRewards"] = "u8u24array",
    ["name"] = "u8string",
    ["teachesSpell"] = "u24",
}
```

`npcDrops` and `vendors` use **u16**-prefixed array length (up to 65535 entries); all other
arrays use u8 length (max 255).

### 4.4 `QuestieDB.itemCompilerOrder` — lines 112–118 (verbatim, 16 entries)

```lua
QuestieDB.itemCompilerOrder = { -- order easily skipable data first for efficiency
    --static size
    "flags", "startQuest", "itemLevel", "requiredLevel", "foodType", "ammoType", "class", "subClass", "teachesSpell",

    -- variable size
    "name", "relatedQuests", "questRewards", "npcDrops", "objectDrops", "vendors", "itemDrops"
}
```

---

## 5. OBJECT — `Database/objectDB.lua`

### 5.1 Header / load-time requirements (lines 1–2)

```lua
---@class QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
```

### 5.2 `QuestieDB.objectKeys` — lines 5–13 — **7 fields** (verbatim)

```lua
---@class DatabaseObjectKeys
QuestieDB.objectKeys = {
    ['name'] = 1, -- string
    ['questStarts'] = 2, -- table {questID(int),...}
    ['questEnds'] = 3, -- table {questID(int),...}
    ['spawns'] = 4, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['zoneID'] = 5, -- guess as to where this object is most common
    ['factionID'] = 6, -- faction restriction mask (same as spawndb factionid)
    ['waypoints'] = 7, -- waypoints for objects on ships/zeppelins/etc
}
```

`objectKeysReversed` lines 15–18; `_objectAdapterQueryOrder` lines 39–42.

### 5.3 `QuestieDB.objectCompilerTypes` — lines 20–28 (verbatim)

```lua
QuestieDB.objectCompilerTypes = {
    ['name'] = "u8string",
    ['spawns'] = "spawnlist",
    ['zoneID'] = "u16",
    ['questStarts'] = "u8u24array",
    ['questEnds'] = "u8u24array",
    ['factionID'] = "u16",
    ['waypoints'] = "waypointlist",
}
```

### 5.4 `QuestieDB.objectCompilerOrder` — lines 30–36 (verbatim, 7 entries)

```lua
QuestieDB.objectCompilerOrder = { -- order easily skipable data first for efficiency
    --static size
    'zoneID', 'factionID',

    -- variable size
    'name', 'spawns', 'questStarts', 'questEnds', 'waypoints'
}
```

---

## 6. DISTINCT COMPILER TYPE STRINGS (21 total across all four entities)

Machine-derived from the four `*CompilerTypes` tables. Format: `type (usage count): entity.field, …`

| # | Type | Uses | Fields |
|---|---|---|---|
| 1 | `u8` | 10 | quest.requiredLevel, quest.requiredMaxLevel, npc.minLevel, npc.maxLevel, npc.rank, item.foodType, item.requiredLevel, item.ammoType, item.class, item.subClass |
| 2 | `s16` | 2 | quest.questLevel, quest.zoneOrSort |
| 3 | `u16` | 7 | quest.requiredClasses, quest.specialFlags, npc.zoneID, npc.factionID, item.itemLevel, object.zoneID, object.factionID |
| 4 | `u24` | 11 | quest.sourceItemId, quest.nextQuestInChain, quest.questFlags, quest.parentQuest, quest.breadcrumbForQuestId, quest.requiredSpecialization, quest.availableUntilCompleted, quest.availableStartingWith, quest.disabledByQuest, item.startQuest, item.teachesSpell |
| 5 | `s24` | 1 | quest.requiredSpell |
| 6 | `u32` | 5 | quest.requiredRaces, npc.minLevelHealth, npc.maxLevelHealth, npc.npcFlags, item.flags |
| 7 | `u8string` | 5 | quest.name, npc.name, npc.subName, item.name, object.name |
| 8 | `faction` | 1 | npc.friendlyToFaction |
| 9 | `u12pair` | 1 | quest.requiredSkill |
| 10 | `s24pair` | 2 | quest.requiredMinRep, quest.requiredMaxRep |
| 11 | `u8s24pairs` | 2 | quest.reputationReward, quest.requiredRanks |
| 12 | `u8u24array` | 14 | quest.preQuestSingle, quest.childQuests, quest.inGroupWith, quest.exclusiveTo, quest.requiredSourceItems, quest.breadcrumbs, npc.questStarts, npc.questEnds, item.objectDrops, item.itemDrops, item.relatedQuests, item.questRewards, object.questStarts, object.questEnds |
| 13 | `u8s24array` | 1 | quest.preQuestGroup |
| 14 | `u16u24array` | 2 | item.npcDrops, item.vendors |
| 15 | `u8u16stringarray` | 1 | quest.objectivesText |
| 16 | `spawnlist` | 2 | npc.spawns, object.spawns |
| 17 | `waypointlist` | 2 | npc.waypoints, object.waypoints |
| 18 | `trigger` | 1 | quest.triggerEnd |
| 19 | `questgivers` | 2 | quest.startedBy, quest.finishedBy |
| 20 | `objectives` | 1 | quest.objectives |
| 21 | `extraobjectives` | 1 | quest.extraObjectives |

### 6.1 Types the compiler supports but which NO entity field uses

From `Database/compiler.lua:63-100` (`QuestieDBCompiler.supportedTypes`):
* number: `s8`
* string: `u16string`
* table: `u24pair`, `u8u16array`, `u16u16array`, `u8s16pairs`, `objective`, `spellobjective`, `reflist`

`objective`, `spellobjective`, `reflist`, `u24pair` and `spawnlist` are used *internally* as
sub-readers by the composite types (`objectives` → 3× `objective` + `u24pair` +
killcredit + `spellobjective`; `trigger` → tinystring + `spawnlist`; `questgivers` → 3×
`u8u24array`; `extraobjectives` → `spawnlist` + `reflist`).

### 6.2 Static vs dynamic classification (`compiler.lua:844-877`)

```lua
QuestieDBCompiler.dynamics = {   -- variable byte length
    "u8string","u16string","u8u16array","u8s16pairs","u16u16array","u8s24pairs",
    "u8u24array","u8s24array","u16u24array","u8u16stringarray","spawnlist","trigger",
    "objective","objectives","questgivers","waypointlist","extraobjectives","reflist"
}
QuestieDBCompiler.statics = {    -- fixed byte length
    ["u8"]=1, ["s8"]=1, ["u16"]=2, ["s16"]=2, ["u24"]=3, ["s24"]=3, ["u32"]=4,
    ["faction"]=1, ["u12pair"]=3, ["u24pair"]=6, ["s24pair"]=6,
}
```

`refTypes` (`compiler.lua:102-113`): `{"monster","item","object"}` → reversed
`{monster=1, item=2, object=3}` (used inside `extraobjectives`/`reflist`).

Compile entry points (`compiler.lua:879-893`):
```lua
CompileNPCs()    -> CompileTableCoroutine(npcData,    npcCompilerTypes,    npcCompilerOrder,    npcKeys,    "npc",   "NPC")
CompileObjects() -> CompileTableCoroutine(objectData, objectCompilerTypes, objectCompilerOrder, objectKeys, "obj",   "Object")
CompileQuests()  -> CompileTableCoroutine(questData,  questCompilerTypes,  questCompilerOrder,  questKeys,  "quest", "Quest", 28)
CompileItems()   -> CompileTableCoroutine(itemData,   itemCompilerTypes,   itemCompilerOrder,   itemKeys,   "item",  "Item", 128)
```

---

## 7. MOCKS REQUIRED TO LOAD THE FOUR SCHEMA FILES

| File | Requirement | Exact line |
|---|---|---|
| `questDB.lua` | `QuestieLoader:ImportModule("QuestieDB")` | `local QuestieDB = QuestieLoader:ImportModule("QuestieDB");` (line 2) |
| `itemDB.lua` | same | line 2 |
| `objectDB.lua` | same | line 2 |
| `npcDB.lua` | `QuestieLoader:ImportModule("QuestieDB")` | line 2 |
| `npcDB.lua` | `QuestieLoader:ImportModule("Expansions")` | `local Expansions = QuestieLoader:ImportModule("Expansions");` (line 4) |
| `npcDB.lua` | global `Questie.IsClassic` (boolean) | used 13× on lines 63–75, e.g. `VENDOR = Questie.IsClassic and 4 or 128,` (line 63) |
| `npcDB.lua` | `Expansions.Current`, `Expansions.Wotlk`, `Expansions.Cata` (numbers) | lines 76–78, e.g. `BARBER = (Expansions.Current >= Expansions.Wotlk) and 33554432 or nil,` |

Minimal mock (sufficient to load all four schema files headlessly under Lua 5.1):

```lua
QuestieLoader = {
  _modules = {},
  CreateModule = function(self, name)
    self._modules[name] = self._modules[name] or { private = {} }
    return self._modules[name]
  end,
}
QuestieLoader.ImportModule = QuestieLoader.CreateModule   -- identical in the real impl
Questie = { IsClassic = false }                            -- or true for Era
-- Expansions numeric ordering, from Modules/Expansions.lua
local E = QuestieLoader:CreateModule("Expansions")
E.Era, E.Tbc, E.Wotlk, E.Cata, E.MoP = 1, 2, 3, 4, 5
E.Current = 5                                              -- 1..5 = Era/TBC/Wotlk/Cata/MoP
```

Real `QuestieLoader` (`Modules/Libs/QuestieLoader.lua:16-35`): `CreateModule` and `ImportModule`
are byte-for-byte the same function body — both lazily create `{ private = {} }`. There is no
error on importing an unknown module.

Real `Expansions` (`Modules/Expansions.lua:6-20`):
```lua
local expansionOrderLookup = { [2]=1, [5]=2, [11]=3, [14]=4, [19]=5 }
Expansions.Current = expansionOrderLookup[WOW_PROJECT_ID or 2]
Expansions.Era     = expansionOrderLookup[WOW_PROJECT_CLASSIC or 2]                  -- 1
Expansions.Tbc     = expansionOrderLookup[WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5]  -- 2
Expansions.Wotlk   = expansionOrderLookup[WOW_PROJECT_WRATH_CLASSIC or 11]           -- 3
Expansions.Cata    = expansionOrderLookup[WOW_PROJECT_CATACLYSM_CLASSIC or 14]       -- 4
Expansions.MoP     = expansionOrderLookup[WOW_PROJECT_MISTS_CLASSIC or 19]           -- 5
```
`Questie.IsClassic` is set in `Modules/VersionCheck.lua:71`:
`Questie.IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC`

---

## 8. EXPANSION DIRECTORIES AND DATA FILES

All five expansion directories exist under `Database/` and **each contains all four**
`*DB.lua` data files. No expansion is missing any entity type.

| Dir | Quest | Npc | Item | Object |
|---|---|---|---|---|
| `Database/Classic/` | `classicQuestDB.lua` | `classicNpcDB.lua` | `classicItemDB.lua` | `classicObjectDB.lua` |
| `Database/TBC/` | `tbcQuestDB.lua` | `tbcNpcDB.lua` | `tbcItemDB.lua` | `tbcObjectDB.lua` |
| `Database/Wotlk/` | `wotlkQuestDB.lua` | `wotlkNpcDB.lua` | `wotlkItemDB.lua` | `wotlkObjectDB.lua` |
| `Database/Cata/` | `cataQuestDB.lua` | `cataNpcDB.lua` | `cataItemDB.lua` | `cataObjectDB.lua` |
| `Database/MoP/` | `mopQuestDB.lua` | `mopNpcDB.lua` | `mopItemDB.lua` | `mopObjectDB.lua` |

File-name prefix per directory: `Classic→classic`, `TBC→tbc`, `Wotlk→wotlk`, `Cata→cata`, `MoP→mop`.

### 8.1 Sizes, entry counts, ID ranges (measured by executing the blobs with lua5.1)

| File | bytes | lines | entries | min id | max id | ids strictly ascending |
|---|---:|---:|---:|---:|---:|---|
| Classic/classicQuestDB.lua | 1 038 790 | 4 301 | 4 244 | 2 | 9 665 | yes |
| Classic/classicNpcDB.lua | 2 033 320 | 10 145 | 10 119 | 1 | 18 199 | yes |
| Classic/classicItemDB.lua | 2 181 706 | 14 914 | 14 889 | 25 | 25 818 | **NO** (237 descents) |
| Classic/classicObjectDB.lua | 1 011 337 | 6 662 | 6 645 | 31 | 300 142 | yes |
| TBC/tbcQuestDB.lua | 1 638 930 | 6 576 | 6 519 | 1 | 12 515 | yes |
| TBC/tbcNpcDB.lua | 3 535 931 | 18 525 | 18 499 | 1 | 29 095 | yes |
| TBC/tbcItemDB.lua | 3 286 744 | 25 035 | 25 010 | 25 | 39 656 | **NO** (721 descents) |
| TBC/tbcObjectDB.lua | 1 682 228 | 9 090 | 9 073 | 31 | 300 158 | yes |
| Wotlk/wotlkQuestDB.lua | 2 323 337 | 9 143 | 9 086 | 1 | 26 034 | yes |
| Wotlk/wotlkNpcDB.lua | 5 186 026 | 29 627 | 29 601 | 1 | 43 282 | yes |
| Wotlk/wotlkItemDB.lua | 4 369 457 | 36 777 | 36 752 | 25 | 56 806 | **NO** (1815 descents) |
| Wotlk/wotlkObjectDB.lua | 2 038 392 | 12 976 | 12 959 | 31 | 300 244 | yes |
| Cata/cataQuestDB.lua | 3 573 309 | 15 065 | 15 008 | 1 | 30 562 | yes |
| Cata/cataNpcDB.lua | 8 257 462 | 46 337 | 46 311 | 1 | 59 072 | yes |
| Cata/cataItemDB.lua | 8 473 795 | 62 111 | 62 086 | 17 | 83 086 | yes |
| Cata/cataObjectDB.lua | 2 517 209 | 17 424 | 17 407 | 1 | 301 121 | yes |
| MoP/mopQuestDB.lua | 4 094 645 | 17 606 | 17 549 | 1 | 34 062 | yes |
| MoP/mopNpcDB.lua | 10 613 320 | 60 096 | 60 068 | 1 | 77 178 | yes |
| MoP/mopItemDB.lua | 10 153 977 | 80 051 | 80 026 | 17 | 112 353 | yes |
| MoP/mopObjectDB.lua | 2 737 013 | 20 097 | 20 081 | 1 | 401 003 | yes |

No duplicate IDs in any file.

### 8.2 Max field index actually present in the data (trailing nils are trimmed by the generator)

| File | maxIndex | distribution (fieldCount : rowCount) |
|---|---:|---|
| Classic/classicQuestDB.lua | 26 | 17:205 18:14 19:11 21:11 22:188 23:1097 24:410 25:41 26:2267 |
| TBC/tbcQuestDB.lua | 26 | 17:379 18:14 19:13 21:11 22:200 23:1969 24:572 25:44 26:3317 |
| Wotlk/wotlkQuestDB.lua | 26 | 10:1 11:1 17:523 18:16 21:21 22:196 23:2299 24:667 25:60 26:5302 |
| Cata/cataQuestDB.lua | 26 | 17:434 18:7 21:4 22:15 23:5174 24:470 25:52 26:8852 |
| MoP/mopQuestDB.lua | 26 | 17:940 18:11 21:4 22:272 23:5604 24:779 25:52 26:9887 |
| \*NpcDB.lua (all 5) | 15 | 15:ALL rows (every npc row has exactly 15 fields) |
| \*ItemDB.lua (all 5) | 14 | classic 13:13138 14:1751; tbc 13:20227 14:4783; wotlk 13:29138 14:7614; cata 13:51360 14:10726; mop 13:67116 14:12910 |
| \*ObjectDB.lua (all 5) | 6 | classic 5:6568 6:77; tbc 5:8957 6:116; wotlk 5:12752 6:207; cata 5:17057 6:350; mop 5:19671 6:410 |

Consequences:
* **quest fields 27–36 are NEVER present in any shipped data file.** They exist only via
  `Database/Corrections/*`. Correction-usage counts (`grep -rn "questKeys.<field>" Database/Corrections`):
  breadcrumbForQuestId 420, breadcrumbs 308, extraObjectives 1498, requiredSpell 526,
  requiredSpecialization 44, requiredMaxLevel 238, availableUntilCompleted 21,
  availableStartingWith 1, requiredRanks 4, disabledByQuest 13. (reputationReward, field 26, 5259.)
* **item field 15 `relatedQuests` is never in raw data** (188 correction sites) and
  **item field 16 `teachesSpell` is never populated anywhere** — 0 hits across the whole
  Questie tree except its own declaration in `Database/itemDB.lua` (lines 21/109/114) and
  `ExternalScripts(DONOTINCLUDEINRELEASE)/merger/item/generate_corrections.lua:20`.
  It is a forward-declared, entirely unused field today.
* **object field 7 `waypoints` is never in raw data** — only 3 correction sites
  (`grep -rn "objectKeys.waypoints" Database/Corrections` → 3).

---

## 9. EXACT SHAPE OF EACH DATA FILE

Every one of the 20 data files has exactly this structure (line numbers are exact):

```
line 1 : -- AUTO GENERATED FILE! DO NOT EDIT!
line 2 : (blank)
line 3 : ---@type QuestieDB
line 4 : local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
line 5 : (blank)
line 6 : QuestieDB.<entity>Keys = {
...    :     ['field'] = N, -- comment          <-- FULL COPY of the keys table
line K : }
line K+1: (blank)
line K+2: QuestieDB.<entity>Data = [[return {
line K+3: [<id>] = {<field1>,<field2>,...},     <-- one entry per line
...
last  : }]]
```

The file does **nothing else** at load time — no function calls, no registration, no
conditionals. The two statements are: (1) the `*Keys` table assignment, (2) the `*Data`
long-string assignment.

### 9.1 Exact `*Data` assignment line per file

| File | line | exact text |
|---|---:|---|
| Classic/classicQuestDB.lua | 56 | `QuestieDB.questData = [[return {` |
| Classic/classicNpcDB.lua | 25 | `QuestieDB.npcData = [[return {` |
| Classic/classicItemDB.lua | 24 | `QuestieDB.itemData = [[return {` |
| Classic/classicObjectDB.lua | 16 | `QuestieDB.objectData = [[return {` |
| TBC/tbcQuestDB.lua | 56 | `QuestieDB.questData = [[return {` |
| TBC/tbcNpcDB.lua | 25 | `QuestieDB.npcData = [[return {` |
| TBC/tbcItemDB.lua | 24 | `QuestieDB.itemData = [[return {` |
| TBC/tbcObjectDB.lua | 16 | `QuestieDB.objectData = [[return {` |
| Wotlk/wotlkQuestDB.lua | 56 | `QuestieDB.questData = [[return {` |
| Wotlk/wotlkNpcDB.lua | 25 | `QuestieDB.npcData = [[return {` |
| Wotlk/wotlkItemDB.lua | 24 | `QuestieDB.itemData = [[return {` |
| Wotlk/wotlkObjectDB.lua | 16 | `QuestieDB.objectData = [[return {` |
| Cata/cataQuestDB.lua | 56 | `QuestieDB.questData = [[return {` |
| Cata/cataNpcDB.lua | 25 | `QuestieDB.npcData = [[return {` |
| Cata/cataItemDB.lua | 24 | `QuestieDB.itemData = [[return {` |
| Cata/cataObjectDB.lua | 16 | `QuestieDB.objectData = [[return {` |
| MoP/mopQuestDB.lua | 56 | `QuestieDB.questData = [[return {` |
| MoP/mopNpcDB.lua | 25 | **`QuestieDB.npcData = [[ return {`** ← extra space after `[[` |
| MoP/mopObjectDB.lua | **15** | `QuestieDB.objectData = [[return {` ← 15 not 16 (objectKeys has only 6 entries here) |
| MoP/mopItemDB.lua | 24 | `QuestieDB.itemData = [[return {` |

Every file ends with the literal two lines `}]]` + trailing `\n`. Each file contains
**exactly one** `[[` and **exactly one** `]]` — no long-bracket collisions inside the data.

### 9.2 Row format

`[<integer id>] = {<comma-separated Lua values>},`

* IDs are plain unquoted integers in square brackets.
* Strings use **either** single or double quotes, inconsistently, sometimes within the same
  file (e.g. `MoP/mopNpcDB.lua:26` is `'Waypoint (Only GM can see it)'` while the last row is
  `"Iron Skyreaver"`). Apostrophes inside single-quoted names are backslash-escaped:
  `'Recruit\'s Shirt'`.
* Missing values are the literal `nil`.
* Trailing `nil`s are trimmed (that is why row lengths vary — see §8.2).
* Spawns/waypoints are `{[zoneID]={{x,y},...},...}`; coordinates are floats.
* **One entry per line** in 19 of 20 files. Exception: `MoP/mopNpcDB.lua` has two stray
  **blank lines at 59162 and 59471**. Every other line after the header in every file matches
  `^\[[0-9]+\] = \{`. A line-oriented parser must tolerate blank lines.

### 9.3 How Questie consumes the blob

`Modules/QuestieInit.lua:361-382`:
```lua
function QuestieInit:LoadDatabase(key)
    if QuestieDB[key] then
        coYield()
        local func, err = loadstring(QuestieDB[key]) -- load the table from string (returns a function)
        if (not func) then
            Questie:Error("Failed to load database: ", key, err)
            return
        end
        QuestieDB[key] = func
        coYield()
        QuestieDB[key] = QuestieDB[key]() -- execute the function (returns the table)
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "Database is missing, this is likely do to era vs tbc: ", key)
    end
end

function QuestieInit:LoadBaseDB()
    QuestieInit:LoadDatabase("npcData")
    QuestieInit:LoadDatabase("objectData")
    QuestieInit:LoadDatabase("questData")
    QuestieInit:LoadDatabase("itemData")
end
```
i.e. `QuestieDB.<entity>Data` is a **string** at file-load time and is replaced in place by the
**table** during init. `Database/Corrections/QuestieCorrections.lua` then mutates that table
(`_LoadCorrections`, lines 232–255), creating missing IDs as `{}` and assigning
`QuestieDB[tbl][id][keyIndex] = value`.

### 9.4 TOC load order (matters!)

From `Questie-Classic.toc` / `Questie-Mists.toc` (identical relative ordering in all five TOCs):

```
36: Modules\VersionCheck.lua           <- sets Questie.IsClassic
39: Modules\Libs\QuestieLoader.lua
40: Modules\Expansions.lua
...
67: Database\<Exp>\<exp>ItemDB.lua     <- DATA files first (they also define *Keys)
68: Database\<Exp>\<exp>NpcDB.lua
69: Database\<Exp>\<exp>ObjectDB.lua
70: Database\<Exp>\<exp>QuestDB.lua
71: Database\QuestieDB.lua
72: Database\questDB.lua               <- CANONICAL schema files load AFTER and overwrite
73: Database\objectDB.lua
74: Database\npcDB.lua
75: Database\itemDB.lua
76: Database\Constants.lua
...
146: Database\compiler.lua
```

**The `*Keys` tables inside the data files are dead code at runtime** — `Database/<entity>DB.lua`
runs later and reassigns `QuestieDB.<entity>Keys` wholesale. That is how the item/object
divergences below are currently harmless.

---

## 10. PER-EXPANSION `*Keys` DIVERGENCE (diffed for ALL 5 expansions × 4 entities)

Method: parsed `QuestieDB.<entity>Keys = { ... }` out of each of the 20 data files and compared
name→index maps against `Database/<entity>DB.lua`.

| Expansion / entity | verdict |
|---|---|
| Classic/quest, npc, object | **identical** to canonical |
| Classic/item | **DIVERGES — missing `['teachesSpell'] = 16`** (15 keys vs 16) |
| TBC/quest, npc, object | identical |
| TBC/item | **DIVERGES — missing `teachesSpell`** (15 vs 16) |
| Wotlk/quest, npc, object | identical |
| Wotlk/item | **DIVERGES — missing `teachesSpell`** (15 vs 16) |
| Cata/quest, npc, object | identical |
| Cata/item | **DIVERGES — missing `teachesSpell`** (15 vs 16) |
| MoP/quest, npc | identical |
| MoP/item | **DIVERGES — missing `teachesSpell`** (15 vs 16) |
| MoP/object | **DIVERGES — missing `['waypoints'] = 7`** (6 vs 7) |

No index was ever *reassigned* — divergences are only truncations at the tail. No extra keys
anywhere. Classic and MoP (the two explicitly requested) are covered above for all four types:
Classic quest/npc/object agree, Classic item is missing `teachesSpell`; MoP quest/npc agree,
MoP item is missing `teachesSpell`, MoP object is missing `waypoints`.

**Conclusion for QuestieTDB: trust `Database/<entity>DB.lua` only. Ignore the copies embedded
in the data files.**

---

## 11. PROTOTYPE FIELD-COUNT COMPARISON

### 11.1 Summary counts

| Entity | Questie (canonical) | Getters/GetterDB/Meta/\*Meta.lua | Getters/{\*DB}/Get.lua | toc-database/{\*DB}/Get.lua |
|---|---:|---:|---:|---:|
| quest | **36** | 33 | 32 (+1 injected `xpReward`) | 29 |
| npc | **15** | 15 ✅ | 7 slots (9 sub-fields packed into slot 2 "combined") | 11 |
| item | **16** | 16 ✅ | 10 slots (7 sub-fields packed into slot 7 "combined") | 16 (names match) |
| object | **7** | 7 ✅ | 7 ✅ | 6 |

### 11.2 `Getters/GetterDB/Meta/QuestMeta.lua` (stale) — indices 1–32 match Questie exactly, then:

```lua
  ['orderedObjectives'] = 33,   -- table: {objectiveTypeKey, objectiveInstanceIndex, orderIndex} pairs
```
* Questie index 33 is `availableUntilCompleted` — **direct index collision**.
* Missing entirely: `availableUntilCompleted`(33), `availableStartingWith`(34),
  `requiredRanks`(35), `disabledByQuest`(36).
* Extra: `orderedObjectives` (does not exist in Questie).
* Also defines `QuestMeta.objectiveKeys = { CREATURE=1, OBJECT=2, ITEM=3, REPUTATION=4, KILLCREDIT=5, SPELL=6 }`
  (`Getters/GetterDB/Meta/QuestMeta.lua:63-70`) — this DOES match Questie's `objectives` sub-index layout.

### 11.3 `Getters/GetterDB/Meta/NpcMeta.lua` — `npcKeys` (lines 18–35) is byte-identical in
name→index to Questie's `npcKeys`. 15/15. ✅
Extras: `NpcMeta.npcTypes` (lua type strings), `NpcMeta.dumpFuncs`, and a `combineValues` map
packing indices `{2,3,4,5,6,9,12,13,15}` into a single `;`-joined string at slot 2.

### 11.4 `Getters/GetterDB/Meta/ItemMeta.lua` — `itemKeys` (lines 16–33) is identical to
Questie's 16 keys **including** `['teachesSpell'] = 16`. ✅
`combineValues` packs indices `{7,8,9,10,11,12,13}` into slot 7.

### 11.5 `Getters/GetterDB/Meta/ObjectMeta.lua` — `objectKeys` (lines 16–24) identical to
Questie's 7 keys. ✅ `combineValues = {}` (empty → `ObjectMeta.combine = nil`).

### 11.6 `toc-database/{NpcDB}/Get.lua:58-70` — 11 fields, **heavily renumbered**

```lua
local schema = {
  {"name",        "string"}, -- 1
  {"minLevel",    "number"}, -- 2
  {"maxLevel",    "number"}, -- 3
  {"rank",        "number"}, -- 4
  {"spawns",      "table"},  -- 5
  {"waypoints",   "table"},  -- 6
  {"questStarts", "table"},  -- 7
  {"questEnds",   "table"},  -- 8
  {"react",       "table"},  -- 9
  {"subName",     "string"}, -- 10
  {"npcFlags",    "number"}, -- 11
}
```
Missing: `minLevelHealth`, `maxLevelHealth`, `zoneID`, `factionID`, `friendlyToFaction`.
Extra/renamed: `react` (table) replaces `friendlyToFaction` (string).

### 11.7 `toc-database/{ItemDB}/Get.lua` (schema at lines 57–74) — 16 fields, names and
order match Questie's `itemKeys` 1:1 including `teachesSpell` = 16. ✅

### 11.8 `toc-database/{ObjectDB}/Get.lua` (schema at lines 57–64) — 6 fields

```lua
{"name",1} {"questStarts",2} {"questEnds",3} {"spawns",4} {"react",5} {"waypoints",6}
```
Missing `zoneID` and `factionID`; `react` occupies index 5; `waypoints` moved 7→6.

### 11.9 `toc-database/{QuestDB}/Get.lua` (schema at lines 62–92) — 29 fields, **shifted from index 9 on**

Missing `triggerEnd` entirely, which shifts everything after it down by one
(`objectives` = 9 instead of 10, … `extraObjectives` = 28 instead of 29). Adds
`requiredEvents` = 29. Missing `requiredSpell`, `requiredSpecialization`, `requiredMaxLevel`,
`availableUntilCompleted`, `availableStartingWith`, `requiredRanks`, `disabledByQuest`.
Uses a shared read-only `EMPTY` table as the default for `startedBy`/`finishedBy`/`objectives`.

### 11.10 `Getters/{QuestDB}/Get.lua:61-97` — 32 fields, indices 1–32 match Questie exactly,
then appends `{"xpReward","number",0}` at index 33 (Questie index 33 = `availableUntilCompleted`
— another collision). Carries per-field defaults: `requiredLevel`=0, `questLevel`=1,
`requiredRaces`=0, `requiredClasses`=0, `sourceItemId`=0, `zoneOrSort`=0, `specialFlags`=0,
`parentQuest`=0, `breadcrumbForQuestId`=0, `requiredSpell`=0, `requiredSpecialization`=0,
`requiredMaxLevel`=0, `startedBy`/`finishedBy`/`objectives` = shared read-only `EMPTY`.

### 11.11 `Getters/{NpcDB}/Get.lua:73-109` and `Getters/{ItemDB}/Get.lua:77-115`
Use the "combined" packing scheme (a single `;`-delimited string slot holding several
scalar fields), so their TOC field indices are NOT Questie indices:

npc (`COMBINED = 2`): slots `1 name, 2 combined, 3 spawns, 4 waypoints, 5 questStarts, 6 questEnds, 7 subName`;
combined sub-order `minLevelHealth(1,def 1), maxLevelHealth(2,def 1), minLevel(3,def 1), maxLevel(4,def 1), rank(5,def 0), zoneID(6), factionID(7), friendlyToFaction(8), npcFlags(9,def 0)`.

item (`COMBINED = 7`): slots `1 name, 2 npcDrops, 3 objectDrops, 4 itemDrops, 5 startQuest(def 0), 6 questRewards, 7 combined, 8 vendors, 9 relatedQuests, 10 teachesSpell(def 0)`;
combined sub-order `flags(1), foodType(2), itemLevel(3), requiredLevel(4), ammoType(5,def 0), class(6), subClass(7)`.

`Getters/{ObjectDB}/Get.lua:55-63` uses the plain 7-field Questie layout. ✅

---

## 12. GOTCHAS FOR THE IMPLEMENTATION

1. **Never read `*Keys` from the data files.** All five `<exp>ItemDB.lua` omit `teachesSpell`;
   `MoP/mopObjectDB.lua` omits `waypoints`. TOC load order makes the canonical file win, so
   the stale copies are invisible at runtime but WILL mislead a generator that greps data files.
2. **`teachesSpell` (item 16) has zero data anywhere.** Emitting it is safe but pointless today.
3. **Object `waypoints` (7) and item `relatedQuests` (15) have no raw data** — corrections only
   (3 and 188 sites respectively).
4. **Quest fields 27–36 have no raw data** — corrections only. If QuestieTDB is generated from
   raw `*Data` alone, ~10 quest fields will be silently empty.
5. **`MoP/mopNpcDB.lua` has two blank lines** (59162, 59471) inside the data blob. Line-based
   parsers must skip them; `loadstring` does not care.
6. **`MoP/mopNpcDB.lua` opens with `[[ return {`** (space after `[[`) unlike the other 19 files.
   Do not pattern-match on the exact literal `[[return {`.
7. **`MoP/mopObjectDB.lua`'s data starts on line 15, not 16**, because its embedded keys table
   is one entry shorter. Do not hard-code header line offsets.
8. **String quoting is mixed** (single and double) within the same file. Escaped `\'` occurs.
   The only reliable parse is `loadstring` on the extracted blob (there is exactly one `[[`
   and one `]]` per file, so `content:match("%[%[(.-)%]%]")` is safe).
9. **Trailing `nil`s are trimmed** so rows have varying arity (e.g. quests: 10..26 fields).
   Any positional writer must treat "absent" as nil, not as "field does not exist".
10. **`preQuestGroup` is `u8s24array` (signed)** while its siblings are `u8u24array`; likewise
    `requiredSpell` is `s24`, `questLevel`/`zoneOrSort` are `s16`, `requiredMinRep`/`requiredMaxRep`
    are `s24pair`. Signedness is load-bearing (negative `zoneOrSort` = QuestSort ID, see
    `Database/Constants.lua` `QuestieDB.sortKeys`, values −1 … −1000).
11. **`npcDrops`/`vendors` use `u16u24array`** (>255 entries possible). Item 117 "Tough Jerky"
    in Classic has 157 npcDrops and 51 vendors — arrays do get large.
12. **`Database/npcDB.lua` cannot be loaded without a `Questie` global and an `Expansions`
    module**; the other three only need `QuestieLoader`.
13. `Classic`, `TBC` and `Wotlk` item DBs are **not sorted by ID** (237 / 721 / 1815 descents).
    No duplicates though. Do not assume ascending order when streaming.
14. `QuestieDB.<entity>Data` is a **string until `QuestieInit:LoadDatabase` runs**. Corrections
    files (e.g. `Database/Corrections/classicQuestFixes.lua:24` `QuestieDB.questData[5640] = {}`)
    assume the table form — they execute later, at `QuestieCorrections:Initialize()`.
15. `QuestieLoader:ImportModule` never fails — it silently creates an empty module. A typo'd
    module name yields an empty table rather than an error.
