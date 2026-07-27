# Recon 06 — Questie's data validators

Source of truth: `/home/logon/projects/Questie-clones/Questie-toc/Questie/`
All paths below are relative to that directory unless absolute.

Files in scope:

| File | Lines | Role |
| --- | --- | --- |
| `cli/validators.lua` | 1037 | The 15 check functions (the thing that ports) |
| `cli/validate-era.lua` | 109 | driver, Classic Era |
| `cli/validate-sod.lua` | 115 | driver, Season of Discovery |
| `cli/validate-tbc.lua` | 108 | driver, TBC |
| `cli/validate-wotlk.lua` | 113 | driver, WotLK |
| `cli/validate-cata.lua` | 109 | driver, Cataclysm |
| `cli/validate-mop.lua` | 103 | driver, Mists of Pandaria |
| `cli/validate-localization.lua` | 95 | driver, deDE smoke test — runs **no** Validators |
| `cli/validators.test.lua` | 1252 | busted suite, 16 describes / 53 `it`s |
| `cli/loadTOC.lua` | 25 | .toc interpreter |
| `cli/apiMocks.lua` | 148 | WoW API globals |
| `cli/print.lua` | 5 | stderr print |
| `cli/dump.lua` | 367 | DevTools `/dump`; required first, never used by validators |
| `cli/profiler.lua` | — | optional, commented out in validate-wotlk.lua |

---

## 1. `cli/validators.lua` — module structure

### Module preamble (lines 1–7, verbatim)

```lua
local Validators = {}

local lfs = require("lfs")

local projectDir = os.getenv("PWD")
local outputDir = projectDir .. "/cli/output"
lfs.mkdir(outputDir)
```

* Hard dependency on **luafilesystem** (`lfs`) at require time — even for pure unit tests.
* `os.getenv("PWD")` is read **at module load**, i.e. before any test can stub `os`. The
  process must therefore be launched from a shell with `PWD` exported **and cwd == repo root**.
  If `PWD` is nil this is an immediate `attempt to concatenate a nil value` error.
* `lfs.mkdir(outputDir)` runs unconditionally on require, creating `<repo>/cli/output`.
* `cli/output` is gitignored (`.gitignore:35`).

### Private helpers

`tableContainsAll(t1, t2)` — lines 12–23. Builds a set from `t1` (`ipairs`), returns false if any
`t2` element is missing. **Does not compare multiplicity or ordering.** The call sites carry a
`-- TODO: Fix tableContainsAll to correctly compare tables.` comment (lines 436, 553, 667, 784).

`pairsByKeys(t, f)` — lines 28–44. Collects keys, `table.sort(a, f)` (default `<`), returns an
iterator yielding `key, value` in ascending key order. Used only in the four `questStarts` /
`questEnds` reporters and the three `*SpawnAreaIds` reporters, i.e. wherever output order
must be deterministic.

### Output conventions (identical in every check)

* Header, before scanning: `print("\n\27[36m<Searching for ...>\27[0m")` — cyan.
* Failure block: `print("\27[31mFound " .. count .. " ...:\27[0m")` then one red line per entity.
* Success: `print("\27[32mNo ... found ...\27[0m")` — green — and `return nil`.
* Counting is always `local count = 0; for _ in pairs(x) do count = count + 1 end`.
* On failure the function calls **`os.exit(1)`** and *then* `return <table>`. In a real run the
  `return` is unreachable; the tests only see it because they stub `os.exit`.
* `print` inside validators.lua is the **global** `print` (stdout). The drivers rebind a *local*
  `print` to `cli/print.lua` (stderr) for their own progress lines — so validator findings go to
  **stdout** and driver chatter goes to **stderr**.

### The 15 exported checks

Order below is the order of definition in the file.

#### 1. `Validators.checkRequiredSourceItems(quests, questKeys)` — line 49
* `@return table<QuestId, string>`
* Invariant: `quest.requiredSourceItems` must contain neither `quest.sourceItemId` nor any
  `objectives[3][*][1]` (item objective id).
* Needs: quests + questKeys only.
* Message values: `"sourceItemId in requiredSourceItems: " .. sourceItemId` and
  `"itemObjectiveId in requiredSourceItems: " .. itemObjective[1]`.
* Per-quest line: `- Quest <id> (<reason>)`.
* Gotcha: one reason string per quest; the item-objective pass runs second and can **overwrite**
  the sourceItemId reason.

#### 2. `Validators.checkPreQuestExclusiveness(quests, questKeys)` — line 107
* Invariant: a quest must not have both a non-empty `preQuestSingle` and a non-empty
  `preQuestGroup`. Condition is
  `preQuestSingle and next(preQuestSingle) and preQuestGroup and next(preQuestGroup)`.
* Hardcoded exclusion table, lines 94–102 (module-level `preQuestExclusions`):
  `30235, 30236, 30239, 30277, 30280, 30296, 30297` (all `= true`).
* Value stored is `true`, not a reason string; line is `- Quest <id>`.

#### 3. `Validators.checkParentChildQuestRelations(quests, questKeys)` — line 140
* Doc comment (lines 135–136): *"If a quest has a parent quest, then the parent quest must have
  the child quest in its childQuests list. This also must hold vice versa: If a quest has child
  quests, then each child quest must have the parent quest set."*
* Forward pass (`parentQuest and parentQuest > 0`) — note the `> 0` guard, corrections set
  `parentQuest = 0` to disable:
  * parent missing from `quests` → key `questId`, reason
    `"parent quest " .. parentQuestId .. " is missing/hidden in the database"`
  * parent has no `childQuests` → key **`parentQuestId`**, reason
    `"quest has no childQuests. " .. questId .. " is listing it as parent quest"`
  * `questId` not in parent's `childQuests` → key **`parentQuestId`**, reason
    `"quest " .. questId .. " is missing in childQuests list"`
* Reverse pass over `childQuests`:
  * child missing → key `childQuestId`, reason
    `"quest is missing/hidden in the database. parentQuest is " .. questId`
  * child has no `parentQuest` → key `childQuestId`, reason
    `"quest has no parentQuest. " .. questId .. " is listing it as child quest"`
* Gotcha: the result map is keyed by a **mix** of offending quest and parent quest ids; one
  reason per key, later writes overwrite earlier ones.

#### 4. `Validators.checkQuestStarters(quests, questKeys, npcs, npcKeys, objects, items)` — line 204
* Invariant: every id in `startedBy[1]` (npc), `[2]` (object), `[3]` (item) exists in the
  respective entity table, and an NPC starter additionally has a `name`.
* Reasons: `"NPC starter <id> is missing in the database"`, `"NPC starter <id> has no name"`,
  `"Object starter <id> is missing in the database"`, `"Item starter <id> is missing in the database"`.
* One reason per quest (overwrites), line `- Quest <id> (<reason>)`.
* `npcKeys` is used **only** for `npcKeys.name`.

#### 5. `Validators.checkQuestFinishers(quests, questKeys, npcs, objects)` — line 252
* Invariant: every id in `finishedBy[1]` (npc) and `[2]` (object) exists.
* **No `npcKeys` parameter** (asymmetric with #4) and **no name check**.
* Reasons: `"NPC finisher <id> is missing in the database"`,
  `"Object finisher <id> is missing in the database"`.

#### 6. `Validators.checkObjectives(quests, questKeys, npcs, objects, items)` — line 294
* Invariant: ids referenced by objectives exist. Slots checked:
  * `objectives[1][*][1]` → npcs — `"NPC objective <id> is missing in the database"`
  * `objectives[2][*][1]` → objects — `"Object objective <id> is missing in the database"`
  * `objectives[3][*][1]` → items — `"Item objective <id> is missing in the database"`
  * `objectives[5][*][1]` is a **list of npc ids** (killCredit) → each must be in npcs —
    `"NPC <id> for killCredit objective is missing in the database"`
  * slot 4 (reputation) and 6 (spell) are **not** checked.
* Result shape differs from #1–#5: `table<QuestId, string[]>` (accumulating list, not overwrite).
* Report format:
  ```
  \27[31m- Quest <id>:
    - <reason>
    - <reason>
  \27[0m
  ```
  (the reset code is printed on its own line after each quest's reasons).

#### 7. `Validators.checkNpcQuestStarts(npcs, npcKeys, quests, questKeys)` — line 366
* `@return table<NpcId, string>, table<NpcId, QuestId[]>` (actually `table<NpcId, string[]>`).
* Bidirectional invariant between `quest.startedBy[1]` and `npc.questStarts`:
  * pass 1 (quests → npcs): for each `startedBy[1]` npc id, record it in `targetQuestStarts`,
    then require `questId ∈ npc.questStarts`, else
    `"quest " .. questId .. " is missing in questStarts"`.
  * pass 2 (npcs → quests): for each `npc.questStarts` entry,
    * quest not in db → `"questStart " .. questId .. " is not in the database"` (and seeds an
      empty `targetQuestStarts[npcId]`)
    * quest exists but npcId ∉ `quest.startedBy[1]` → `"quest " .. questId .. " is not started by this NPC"`
    * if `tableContainsAll` both ways, `targetQuestStarts[npcId] = nil` (nothing to correct).
* **Side effect — correction file.** On failure it writes `cli/output/npcQuestStartsCorrections.lua`
  *before* exiting:
  ```lua
  local correctionFile = io.open(outputDir .. "/npcQuestStartsCorrections.lua", "w")
  correctionFile:write("return {\n")
  ...
  local correctionString = "[" .. npcId .. "] = { -- " .. npcs[npcId][npcKeys.name] .. "\n            [npcKeys.questStarts] = {" .. table.concat(targetQuestStarts[npcId] or {}, ",") .. "},\n        },"
  correctionFile:write("        " .. correctionString .. "\n")
  ...
  correctionFile:write("}\n")
  correctionFile:close()
  ```
  Real sample (`cli/output/npcQuestStartsCorrections.lua`, left over from the unit tests):
  ```lua
  return {
          [1] = { -- First NPC
              [npcKeys.questStarts] = {2},
          },
          [3] = { -- Third NPC
              [npcKeys.questStarts] = {5,6},
          },
  }
  ```
* Console: `- NPC <id>:` then indented `  - <reason>` lines, iterated with `pairsByKeys` (sorted).
* **BUG / gotcha (line 380):** `local npcQuestStarters = npcs[npcStarterId][npcKeys.questStarts]`
  has **no nil guard**. If a quest's `startedBy[1]` names an NPC absent from `npcData`, this
  throws `attempt to index a nil value` instead of reporting. (`checkNpcQuestEnds` line 494–495
  *does* guard with `if npcEnder then`.) Same asymmetry in `checkObjectQuestStarts` (line 611,
  unguarded) vs `checkObjectQuestEnds` (line 725, guarded). Worse, this check runs **first** in
  every driver — before `checkQuestStarters`, which is the check that would have reported the
  missing NPC properly — so a missing questgiver surfaces as a raw Lua stack trace, not a
  validation message.

#### 8. `Validators.checkNpcQuestEnds(npcs, npcKeys, quests, questKeys)` — line 480
* Mirror of #7 for `quest.finishedBy[1]` ↔ `npc.questEnds`.
* Reasons: `"quest <id> is missing in questEnds"`, `"questEnd <id> is not in the database"`,
  `"quest <id> is not finished by this NPC"`.
* Writes `cli/output/npcQuestEndsCorrections.lua`, field label `[npcKeys.questEnds]`.
* Guards `if npcEnder then` — quests whose finisher NPC is absent are silently skipped
  (covered by the test *"should skip finishedBy entries of quests"*, line 744).
* Success message says `"No NPCs found with invalid questEnds"`.

#### 9. `Validators.checkObjectQuestStarts(objects, objectKeys, quests, questKeys)` — line 597
* Mirror of #7 for `quest.startedBy[2]` ↔ `object.questStarts`.
* Reason for the reverse mismatch is `"quest <id> is not started by this object"`.
* Writes `cli/output/objectQuestStartsCorrections.lua`, field `[objectKeys.questStarts]`,
  comment `-- <objects[objectId][objectKeys.name]>`.
* Console prefix is lowercase `- object <id>:`.

#### 10. `Validators.checkObjectQuestEnds(objects, objectKeys, quests, questKeys)` — line 711
* Mirror of #8 for `quest.finishedBy[2]` ↔ `object.questEnds`.
* Reason `"quest <id> is not finished by this object"`.
* Writes `cli/output/objectQuestEndsCorrections.lua`, field `[objectKeys.questEnds]`.
* **Copy-paste leftovers:** the failure header says `"Found N objects with invalid questEnds:"`
  but the success line says `"No NPCs found with invalid questEnds"` (line 818), and the
  `---@return` annotation says `table<NpcId, string>` (line 710).

#### 11. `Validators.checkRequiredRaces(quests, questKeys, raceKeys)` — line 827
* Invariant: every quest has a `requiredRaces` and it does not exceed the sum of **all** values in
  `raceKeys`:
  ```lua
  local highestPossibleRaceCombination = 0
  for _, raceId in pairs(raceKeys) do
      highestPossibleRaceCombination = highestPossibleRaceCombination + raceId
  end
  ```
* Reasons: `"no requiredRaces entry"`, `"requiredRaces is too high"`.
* Gotcha: this sums composite constants (`ALL_ALLIANCE`, `ALL_HORDE`) together with the
  individual race bits, so the ceiling is far above the true bitmask maximum. It is a
  garbage-detector, not a strict mask check. Computed ceilings with the real
  `QuestieDB.raceKeys` (`Database/QuestieDB.lua:122`):
  * individual bits total = 60 819 455 (1,2,4,8,16,32,64,128,256,512,1024,2097152,8388608,16777216,33554432)
  * Classic/Era/SoD: `+77 +178 +0` → **60 819 710**
  * TBC / WotLK: `+1101 +690` → **60 821 246**
  * Cata: `+2098253 +946` → **62 918 654**
  * MoP: `+18875469 +33555378` → **113 250 302**
* Note: `NONE = 0` participates harmlessly.

#### 12. `Validators.checkNpcSpawnAreaIds(npcs, npcKeys, getUiMapIdByAreaId)` — line 867
* `@param getUiMapIdByAreaId fun(areaId: AreaId): number|nil`
* `@return table<NpcId, AreaId[]>|nil`
* Invariant: every key of `npc.spawns` (a `[areaId] = {coordPairs}` map) resolves through
  `getUiMapIdByAreaId`.
* Unknown ids are collected per NPC, `table.sort`ed ascending.
* Report line: `- NPC <id> (<name or "unknown">): areaIds <a, b, c>` (via `table.concat(areaIds, ", ")`),
  iterated with `pairsByKeys`.
* Name lookup is defensive: `npcs[npcId] and npcs[npcId][npcKeys.name] or "unknown"`, wrapped in
  `tostring`.

#### 13. `Validators.checkObjectSpawnAreaIds(objects, objectKeys, getUiMapIdByAreaId)` — line 909
* Identical to #12 over `object.spawns`; line prefix `- Object <id> (<name>): areaIds ...`.

#### 14. `Validators.checkQuestExtraObjectiveSpawnAreaIds(quests, questKeys, getUiMapIdByAreaId)` — line 951
* Iterates `quest.extraObjectives` with `ipairs`; `extraObjective[1]` is the spawnlist
  (`[areaId] = {coords}`); nil spawnlists are skipped.
* Report line: `- Quest <id>: areaIds <a, b>`.
* Unknown ids from **all** extraObjectives of a quest are merged into one sorted list.

#### 15. `Validators.checkQuestTriggerEndSpawnAreaIds(quests, questKeys, getUiMapIdByAreaId)` — line 997
* `quest.triggerEnd` is `{text, {[areaId] = {coords}}}`; the spawnlist is `triggerEnd[2]`,
  skipped when nil.
* Report line: `- Quest <id>: areaIds <a, b>`.

### What the checks need beyond the entity tables

| Need | Supplied by | Notes |
| --- | --- | --- |
| `questKeys` / `npcKeys` / `objectKeys` | `QuestieDB.questKeys` etc. (see §4) | field-name → array-index maps |
| `raceKeys` | `QuestieDB.raceKeys` (`Database/QuestieDB.lua:122`) | expansion-dependent values |
| `getUiMapIdByAreaId(areaId)` | `ZoneDB:GetUiMapIdByAreaId` (`Database/Zones/zoneDB.lua:85`) | the only zone dependency |
| filesystem | `lfs` (mkdir) + `io.open` | writes 4 correction files |
| `PWD` env var | shell | `cli/output` path root |

Nothing else: no `l10n`, no compiler, no `QuestieDB` query API. The check functions are pure
except for `print`, `io.open` and `os.exit`.

---

## 2. The drivers `cli/validate-*.lua`

### 2.1 `cli/validate-era.lua` — full text (the canonical driver)

```lua
require("cli.dump")
local Validators = require("cli.validators")

WOW_PROJECT_ID = 2

dofile("cli/apiMocks.lua")
local print = require("cli.print")
local loadTOC = require("cli.loadTOC")

GetBuildInfo = function()
    return "1.14.3", "44403", "Jun 27 2022", 11403
end
UnitLevel = function()
    return 60
end
GetMaxPlayerLevel = function()
    return 60
end

local function _Debug(_, ...)
    --print(...)
end

local function _ErrorOrWarning(_, text, ...)
    print(text)
end

local function _CheckClassicDatabase()
    print("\n\27[36mCompiling Classic database...\27[0m")
    loadTOC("Questie-Classic.toc")

    assert(Questie.IsEra, "Questie is not started for Era/HC/Anniversary")

    Questie.Debug = _Debug
    Questie.Error = _ErrorOrWarning
    Questie.Warning = _ErrorOrWarning

    Questie.db = {
        char = {
            showEventQuests = false
        },
        global = {},
        profile = {}
    }
    QuestieConfig = {}

    ---@type QuestieDB
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    ---@type QuestieCorrections
    local QuestieCorrections = QuestieLoader:ImportModule("QuestieCorrections")
    ---@type l10n
    local l10n = QuestieLoader:ImportModule("l10n")
    ---@type ZoneDB
    local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

    print("\124cFF4DDBFF [1/7] " .. l10n("Loading database") .. l10n("..."))

    QuestieDB.npcData = loadstring(QuestieDB.npcData)()
    QuestieDB.objectData = loadstring(QuestieDB.objectData)()
    QuestieDB.questData = loadstring(QuestieDB.questData)()
    QuestieDB.itemData = loadstring(QuestieDB.itemData)()

    print("\124cFF4DDBFF [2/7] " .. l10n("Applying database corrections") .. l10n("..."))

    Questie:SetIcons()
    ZoneDB:Initialize()

    QuestieCorrections:Initialize({
        ["npcData"] = QuestieDB.npcData,
        ["objectData"] = QuestieDB.objectData,
        ["itemData"] = QuestieDB.itemData,
        ["questData"] = QuestieDB.questData
    })

    local QuestieDBCompiler = QuestieLoader:ImportModule("DBCompiler")

    Questie.db.global.debugEnabled = true
    QuestieDBCompiler:Compile(function() end)

    QuestieDB:Initialize()


    print("\n\27[32mClassic database compiled successfully\27[0m")

    -- We accept blacklisted quests as questStarts and questEnds for now
    Validators.checkNpcQuestStarts(QuestieDB.npcData, QuestieDB.npcKeys, QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkNpcQuestEnds(QuestieDB.npcData, QuestieDB.npcKeys, QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkObjectQuestStarts(QuestieDB.objectData, QuestieDB.objectKeys, QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkObjectQuestEnds(QuestieDB.objectData, QuestieDB.objectKeys, QuestieDB.questData, QuestieDB.questKeys)

    -- Remove hidden quests from the database as we don't want to validate them
    for questId, _ in pairs(QuestieCorrections.hiddenQuests) do
        QuestieDB.questData[questId] = nil
    end

    Validators.checkRequiredRaces(QuestieDB.questData, QuestieDB.questKeys, QuestieDB.raceKeys)
    Validators.checkRequiredSourceItems(QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkPreQuestExclusiveness(QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkParentChildQuestRelations(QuestieDB.questData, QuestieDB.questKeys)
    Validators.checkQuestStarters(QuestieDB.questData, QuestieDB.questKeys, QuestieDB.npcData, QuestieDB.npcKeys, QuestieDB.objectData, QuestieDB.itemData)
    Validators.checkQuestFinishers(QuestieDB.questData, QuestieDB.questKeys, QuestieDB.npcData, QuestieDB.objectData)
    Validators.checkObjectives(QuestieDB.questData, QuestieDB.questKeys, QuestieDB.npcData, QuestieDB.objectData, QuestieDB.itemData)
    Validators.checkNpcSpawnAreaIds(QuestieDB.npcData, QuestieDB.npcKeys, function(areaId) return ZoneDB:GetUiMapIdByAreaId(areaId) end)
    Validators.checkObjectSpawnAreaIds(QuestieDB.objectData, QuestieDB.objectKeys, function(areaId) return ZoneDB:GetUiMapIdByAreaId(areaId) end)
    Validators.checkQuestExtraObjectiveSpawnAreaIds(QuestieDB.questData, QuestieDB.questKeys, function(areaId) return ZoneDB:GetUiMapIdByAreaId(areaId) end)
    Validators.checkQuestTriggerEndSpawnAreaIds(QuestieDB.questData, QuestieDB.questKeys, function(areaId) return ZoneDB:GetUiMapIdByAreaId(areaId) end)
end

_CheckClassicDatabase()
```

### 2.2 The seven-phase driver shape (same in all six DB drivers)

1. `require("cli.dump")` — side-effect-only; builds DevTools symbol caches from `getfenv(0)`.
2. `local Validators = require("cli.validators")` — **runs `lfs.mkdir(cli/output)` here**.
3. `WOW_PROJECT_ID = <n>` — must precede `apiMocks` and the TOC load.
4. `dofile("cli/apiMocks.lua")` — installs the WoW API globals.
5. `local print = require("cli.print")` — driver-local stderr printer.
6. `local loadTOC = require("cli.loadTOC")`.
7. Per-flavor client stubs (`GetBuildInfo`, `UnitLevel`, `GetMaxPlayerLevel`, and for SoD
   `C_Seasons`, for localization `GetLocale`).
8. Inside the `_Check*Database()` function:
   `loadTOC(<toc>)` → `assert(Questie.Is<Flavor>, msg)` → override
   `Questie.Debug/Error/Warning` → build `Questie.db` + `QuestieConfig` →
   import the 4 modules → `loadstring` the 4 packed data blobs →
   `Questie:SetIcons()` → `ZoneDB:Initialize()` → `QuestieCorrections:Initialize(validationTables)`
   → import `DBCompiler` → (`Questie.db.global.debugEnabled = true`) → `Compile(function() end)`
   → `QuestieDB:Initialize()` → success banner → validator calls.
9. Bottom-of-file call `_Check*Database()`.

### 2.3 Per-driver differences

| | era | sod | tbc | wotlk | cata | mop | localization |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `WOW_PROJECT_ID` | 2 | 2 | 5 | 11 | 14 | 19 | 2 |
| TOC loaded | `Questie-Classic.toc` | `Questie-Classic.toc` | `Questie-BCC.toc` | `Questie-WOTLKC.toc` | `Questie-Cata.toc` | `Questie-Mists.toc` | `Questie-Classic.toc` + 4 deDE lookups |
| `GetBuildInfo` | `"1.14.3","44403","Jun 27 2022",11403` | `"1.15.0","52409","Dev 1 2023",11500` | `"2.5.1","38644","May 11 2021",20501` | `"3.4.0","44644","Jun 12 2022",30400` | `"4.4.0","53863","Mar 28 2024",40400` | `"5.5.0","60700","May 6 2025",50500` | same as era |
| `UnitLevel`/`GetMaxPlayerLevel` | 60 | 25 | 70 | 80 | 85 | 90 | 60 |
| extra globals | — | `C_Seasons = {HasActiveSeason=true, GetActiveSeason=Enum.SeasonID.SeasonOfDiscovery}` | — | — | — | — | `GetLocale = "deDE"` |
| assertion | `Questie.IsEra` | `Questie.IsSoD` | `Questie.IsTBC` | `Questie.IsWotlk` | `Questie.IsCata` | `Questie.IsMoP` | `Questie.IsEra` |
| `Questie.db.global` | `{}` | `{ sod = {} }` | `{}` | `{}` | `{}` | `{}` | `{}` |
| sets `debugEnabled` | yes | yes | **no** | yes | yes | yes | yes |
| imports `ZoneDB` as local | yes | yes | yes | yes | yes | yes | no (inline `QuestieLoader:ImportModule("ZoneDB"):Initialize()`) |
| calls `l10n.InitializeUILocale()` / `l10n:Initialize()` | no | no | no | no | no | no | **yes** |
| runs Npc/Object questStarts+questEnds checks | yes | yes | yes | yes | yes | **NO** | no |
| runs `checkRequiredRaces` | yes | yes | yes | yes | **NO** | yes | no |
| success banner trailing `\n` | none | none | `\27[0m\n` | `\27[0m\n` | none | none | n/a |

**Validator call order** (identical in era / sod / tbc / wotlk; cata drops #5, mop drops #1–#4):

1. `checkNpcQuestStarts(npcData, npcKeys, questData, questKeys)`
2. `checkNpcQuestEnds(npcData, npcKeys, questData, questKeys)`
3. `checkObjectQuestStarts(objectData, objectKeys, questData, questKeys)`
4. `checkObjectQuestEnds(objectData, objectKeys, questData, questKeys)`
   — comment above them: `-- We accept blacklisted quests as questStarts and questEnds for now`
   — **these four run on the FULL quest table, before hidden quests are stripped.**
5. *strip hidden quests*: `for questId in pairs(QuestieCorrections.hiddenQuests) do QuestieDB.questData[questId] = nil end`
6. `checkRequiredRaces(questData, questKeys, raceKeys)` *(not in cata)*
7. `checkRequiredSourceItems(questData, questKeys)`
8. `checkPreQuestExclusiveness(questData, questKeys)`
9. `checkParentChildQuestRelations(questData, questKeys)`
10. `checkQuestStarters(questData, questKeys, npcData, npcKeys, objectData, itemData)`
11. `checkQuestFinishers(questData, questKeys, npcData, objectData)`
12. `checkObjectives(questData, questKeys, npcData, objectData, itemData)`
13. `checkNpcSpawnAreaIds(npcData, npcKeys, λareaId → ZoneDB:GetUiMapIdByAreaId(areaId))`
14. `checkObjectSpawnAreaIds(objectData, objectKeys, λ…)`
15. `checkQuestExtraObjectiveSpawnAreaIds(questData, questKeys, λ…)`
16. `checkQuestTriggerEndSpawnAreaIds(questData, questKeys, λ…)`

`ZoneDB:GetUiMapIdByAreaId` is always wrapped in a closure because it is a **colon method**
(needs `self`) while the validators expect a plain 1-arg function.

### 2.4 Pass / fail and exit codes

* There is **no aggregation**. Each check exits the process on its own first failure
  (`os.exit(1)` inside the check). Consequently:
  * exit code is `1` on any failure, `0` if the script falls off the end.
  * **only the first failing check ever reports** — everything after it is skipped, including
    the correction-file writes of later checks. Fixing one class of error can therefore reveal
    a completely different set of errors on the next CI run.
* `assert(Questie.Is<Flavor>, ...)` failure, or any error raised during `loadTOC`, exits with
  Lua's error exit code **1** as well (`lua: ...` on stderr).
* `validate-localization.lua` fails only via its four `assert`s.

### 2.5 `cli/validate-localization.lua` specifics

Loads the TOC and then four extra files by `dofile`:
```lua
loadTOC("Questie-Classic.toc")
dofile("Localization/lookups/Classic/lookupItems/deDE.lua")
dofile("Localization/lookups/Classic/lookupNpcs/deDE.lua")
dofile("Localization/lookups/Classic/lookupObjects/deDE.lua")
dofile("Localization/lookups/Classic/lookupQuests/deDE.lua")
```
(the lookups are normally pulled in through `.xml` files, which `loadTOC` skips).
It calls `l10n.InitializeUILocale()` and `l10n:Initialize()` after corrections, then asserts:
```lua
assert(QuestieDB.GetQuest(2).name == "Klaue von Scharfkralle")
assert(QuestieDB:GetNPC(3).name == "Fleischfresser")
assert(QuestieDB:GetObject(31).name == "Alte Löwenstatue")
assert(QuestieDB:GetItem(159).name == "Erfrischendes Quellwasser")
```
No `Validators.*` call at all — it is a compiled-DB + localization smoke test, and it is the
only driver that exercises the compiled query path.

---

## 3. Bootstrap: `loadTOC.lua` + `apiMocks.lua` + the `.toc`

### 3.1 `cli/loadTOC.lua` — full text

```lua
local print = print

-- WoW addon namespace
local addonName = "Questie"
local addonTable = {}

local function loadTOC(file)
    local rfile = io.open(file, "r")
    for line in rfile:lines() do
        if string.len(line) > 1 and string.byte(line, 1) ~= 35 and (not string.find(line, ".xml")) then
            line = line:gsub("\\", "/")
            line = line:gsub("%s+", "")
            local pcallResult, errorMessage
            local chunck = loadfile(line)
            if chunck then
                pcallResult, errorMessage = pcall(chunck, addonName, addonTable)
            end
            if (not pcallResult) then
                error("Error loading " .. line .. ": " .. (errorMessage or "No errorMessage"))
            end
        end
    end
end

return loadTOC
```

Line-filter semantics (exactly):
* `string.len(line) > 1` — drops empty lines and 1-char lines.
* `string.byte(line, 1) ~= 35` — drops everything starting with `#`, which is **all** `##`
  metadata directives *and* all comments/section headers.
* `not string.find(line, ".xml")` — drops XML includes (`embeds.xml`,
  `Localization\Translations\Translations.xml`, the lookup `.xml`s, the LibUIDropDownMenu xml,
  the WorldMapButton template). Note `.` is an unescaped Lua pattern wildcard, so any line
  containing `<any-char>xml` is skipped; harmless in practice.
* `line:gsub("\\","/")` then `line:gsub("%s+","")` — Windows→POSIX separators and *all*
  whitespace stripped (so paths must not contain spaces).
* Each file is executed as `chunk(addonName, addonTable)` → `local addonName, addonTable = ...`,
  matching WoW's addon vararg convention. `addonName` must be `"Questie"` or
  `Modules/VersionCheck.lua` bails out (`VersionCheck.lua:4`).
* `loadfile` returning nil (missing file / syntax error) leaves `pcallResult` nil → `error(...)`
  with `"No errorMessage"`.
* All paths are **relative to cwd**, therefore every driver must be launched from the repo root.

### 3.2 `cli/apiMocks.lua` — every global it installs

Constants:
`WOW_PROJECT_CLASSIC = 2`, `WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5`,
`WOW_PROJECT_WRATH_CLASSIC = 11`, `WOW_PROJECT_CATACLYSM_CLASSIC = 14`,
`WOW_PROJECT_MISTS_CLASSIC = 19`, `WOW_PROJECT_MAINLINE = 1`,
`QUEST_MONSTERS_KILLED`, `QUEST_ITEMS_NEEDED`, `QUEST_OBJECTS_FOUND`,
`ERR_QUEST_ACCEPTED_S`, `ERR_QUEST_COMPLETE_S` (each set to its own name as a string).

Lua-side shims:
`tremove = table.remove`, `tinsert = table.insert`,
`coroutine.yield = <no-op>` (**global monkey-patch of the coroutine library** — this is what lets
`QuestieDBCompiler:Compile` run synchronously), `mod = function(a,b) return a % b end`,
`bit = require("bit32")` (**luarocks `bit32` is required**), `hooksecurefunc = <no-op>`.

API functions: `GetAddOnInfo`, `GetAddOnMetadata` (returns `"6.6.0"`), `GetRealmName`,
`GetTime`, `InCombatLockdown`, `IsAddOnLoaded`, `UnitFactionGroup` (returns `arg[1] or "Horde"`
— `arg` is the Lua 5.1 CLI argv table, so normally `"Horde"`), `UnitClass` (`"Druid","DRUID",11`),
`UnitClassBase`, `UnitRace` (`"Tauren","TAUREN",6`), `GetLocale` (`"enUS"`),
`GetCurrentRegion` (`3` → `Questie.IsEURegion = true`), `GetQuestGreenRange` (`10`),
`GetNumQuestWatches` (`0`), `GetTrackedAchievements` (`0`), `UnitName` (`"QuestieNPC"`).

Tables / frames: `LibStub` (table with `NewLibrary`, `GetLibrary`, plus a `__call` metamethod
returning `{NewAddon = <returns {}>, New = <returns {}>}` — this is how `Questie` itself is
created in `VersionCheck.lua:41`), `StaticPopupDialogs = {}`,
`QuestLogListScrollFrame = {ScrollBar = {}}`, `CreateFrame` (returns a stub with
`Show/SetOwner/SetScript/RegisterEvent`), `C_QuestLog = {}`,
`C_Timer` (`After(_, f)` calls `f()` immediately; `NewTicker(_, f, times)` loops — with no
`times` it installs a fake ticker on `QuestieLoader:ImportModule("DBCompiler").ticker` and spins
until `Cancel()`), `Enum = { SeasonID = { SeasonOfMastery = 1, SeasonOfDiscovery = 2, Hardcore = 3 } }`,
`C_Seasons = { HasActiveSeason = function() return false end }`,
`ItemRefTooltip` (7 no-op methods), `C_CurrencyInfo = {}`, `C_AddOns = {}`, `C_Item = {}`,
`C_Map = {}`.

**Not mocked** (relied on being nil): `C_GameRules` → `Questie.IsHardcore = nil`;
`Enum.SeasonID.Fresh` / `FreshHardcore` → the Anniversary flags are `false`;
`DEFAULT_CHAT_FRAME` (only touched on error paths); `getglobal` (only inside `dump.lua`'s lazy
cache builders).

### 3.3 Globals the drivers themselves depend on

Written by the driver **before** the TOC load: `WOW_PROJECT_ID`.
Written **after** the TOC load: `Questie.Debug`, `Questie.Error`, `Questie.Warning`,
`Questie.db` (`.char.showEventQuests`, `.global`, `.profile`), `QuestieConfig`,
`Questie.db.global.debugEnabled`, `QuestieDB.npcData/objectData/questData/itemData`
(replaced by the `loadstring`ed tables).

Read after the TOC load: `Questie` (created by `Modules/VersionCheck.lua`),
`Questie.IsEra/IsSoD/IsTBC/IsWotlk/IsCata/IsMoP` (`Modules/VersionCheck.lua:55-85`),
`Questie:SetIcons` (`Questie.lua:291`), `QuestieLoader` (`Modules/Libs/QuestieLoader.lua:3`,
a bare global with `CreateModule` / `ImportModule` returning the same lazily-created table).

Expansion flags are derived from `WOW_PROJECT_ID` in `Modules/VersionCheck.lua`:
`Questie.IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC`,
`Questie.IsEra = Questie.IsClassic and (not C_Seasons.HasActiveSeason())`,
`Questie.IsSoD = Questie.IsClassic and C_Seasons.HasActiveSeason() and (C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfDiscovery)`, etc.
`Modules/Expansions.lua` maps `WOW_PROJECT_ID` → ordinal via
`{[2]=1,[5]=2,[11]=3,[14]=4,[19]=5}` and exposes `Expansions.Current/Era/Tbc/Wotlk/Cata/MoP`.

### 3.4 Ordering constraints (all load-bearing)

1. `require("cli.validators")` must happen while `os.getenv("PWD")` is valid (it is read at
   require time).
2. `WOW_PROJECT_ID` must be assigned before `dofile("cli/apiMocks.lua")`? — not strictly, but it
   *must* be before `loadTOC`, because `Modules/Expansions.lua` and `Modules/VersionCheck.lua`
   read it at load.
3. SoD's `C_Seasons` override must come **after** `dofile("cli/apiMocks.lua")` (apiMocks defines
   the default `C_Seasons`), which it does.
4. `Questie.db` must be assigned before `ZoneDB:Initialize()` (which reads
   `Questie.db.profile.debugEnabled` at `zoneDB.lua:67`) and before
   `QuestieCorrections:Initialize` (reads `Questie.db.global.isleOfQuelDanasPhase`).
   Because `debugEnabled` is set on `.global` *after* `ZoneDB:Initialize()`,
   `_ZoneDB:RunTests()` is **never** executed in CLI runs — good, it needs `C_Map` for real.
5. The four `loadstring(QuestieDB.xData)()` calls must precede `QuestieCorrections:Initialize`
   (corrections mutate the decoded tables).

---

## 4. External helpers used by the validation pipeline (outside `cli/`)

| Symbol | Module name | File | Used for |
| --- | --- | --- | --- |
| `ZoneDB:GetUiMapIdByAreaId(areaId)` | `ZoneDB` | `Database/Zones/zoneDB.lua:85` | the only helper the check functions themselves take |
| `ZoneDB.Initialize()` | `ZoneDB` | `Database/Zones/zoneDB.lua:38` | builds `areaIdToUiMapId` from the packed strings + overrides |
| `ZoneDB.private.areaIdToUiMapId` / `…Override` | data | `Database/Zones/data/areaIdToUiMapId.lua` (line 110 / line 6); MoP uses `Database/Zones/data/MoP/areaIdToUiMapId.lua` (line 144 / line 6) | the areaId → uiMapId table |
| `ZoneDB.private.uiMapIdToAreaId` / `…Override` | data | `Database/Zones/data/uiMapIdToAreaId.lua`; MoP `Database/Zones/data/MoP/uiMapIdToAreaId.lua` | inverse table (not used by validators, but `Initialize` loads it) |
| `ZoneDB.private.dungeons` | data | `Database/Zones/data/dungeons.lua` | required by `Initialize` |
| `ZoneDB.private.subZoneToParentZone` / `…Override` | data | `Database/Zones/data/subZoneToParentZone.lua` | required by `Initialize` |
| `ZoneDB.zoneIDs` | data | `Database/Zones/data/zoneIds.lua` | referenced by `QuestieCorrections` `ZONE_SCALES` |
| — | data | `Database/Zones/data/instanceIdToAreaId.lua` | in every TOC's Zones block |
| `QuestieLoader:CreateModule/ImportModule` | `QuestieLoader` (global) | `Modules/Libs/QuestieLoader.lua:16` / `:28` | module registry |
| `QuestieDB.questKeys` | `QuestieDB` | `Database/Classic/classicQuestDB.lua:6` (per-flavor: `Database/TBC/tbcQuestDB.lua:6`, `Wotlk/wotlkQuestDB.lua:6`, `Cata/cataQuestDB.lua:6`, `MoP/mopQuestDB.lua:6`) | field→index map |
| `QuestieDB.npcKeys` | `QuestieDB` | `Database/Classic/classicNpcDB.lua:6` (+ TBC/Wotlk/Cata/MoP variants) | field→index map |
| `QuestieDB.objectKeys` | `QuestieDB` | `Database/Classic/classicObjectDB.lua:6` (+ variants) | field→index map |
| `QuestieDB.itemKeys` | `QuestieDB` | `Database/Classic/classicItemDB.lua:6` (+ variants) | not used by validators |
| `QuestieDB.raceKeys` | `QuestieDB` | `Database/QuestieDB.lua:122` | `checkRequiredRaces` ceiling |
| `QuestieDB.Initialize` | `QuestieDB` | `Database/QuestieDB.lua` | needed only so the compiled query API works (localization driver) |
| `QuestieCorrections:Initialize(validationTables)` | `QuestieCorrections` | `Database/Corrections/QuestieCorrections.lua:258` | applies all corrections |
| `QuestieCorrections.hiddenQuests` | `QuestieCorrections` | populated at `QuestieCorrections.lua:185` from `QuestieQuestBlacklist:Load()` (+ QuelDanas / Wotlk auto / Hardcore additions) | the hidden-quest strip step |
| `QuestieDBCompiler:Compile` | `DBCompiler` | `Database/compiler.lua:1078` (module created `Database/compiler.lua:2`) | must run before `QuestieDB:Initialize` |
| `l10n(...)`, `l10n.InitializeUILocale`, `l10n:Initialize` | `l10n` | `Localization/l10n.lua:13` | progress strings; full init only in the localization driver |
| `Questie:SetIcons()` | global `Questie` | `Questie.lua:291` | must run before corrections (icons referenced by fixes) |
| `QuestieLib.equals` | `QuestieLib` | `Modules/Libs/QuestieLib.lua` | used by the redundant-correction warning |

### 4.1 The *other* validator hiding in `QuestieCorrections`

`QuestieCorrections:Initialize(validationTables)` is the CI-only "irrelevant correction"
detector (`Database/Corrections/QuestieCorrections.lua:239-246`):

```lua
if validationTables and QuestieDB[databaseTableName][id] then
    if value and QuestieLib.equals(QuestieDB[databaseTableName][id][key], value) and validationTables[databaseTableName][id] and
        QuestieLib.equals(validationTables[databaseTableName][id][key], value) then
        Questie:Warning("Correction of " ..
                        databaseTableName .. " " .. tostring(id) .. "." .. reversedKeys[key] .. " matches base DB! Value:" .. tostring(value))
    end
end
```
* The `validationTables` argument is exactly the 4-table literal the drivers pass.
* It only **warns** (routed to stderr by the driver's `_ErrorOrWarning`); it never fails CI.
* Because the drivers pass the *same* table references as `QuestieDB.*Data`, the two
  `QuestieLib.equals` comparisons are the same test twice; it works only because the check runs
  before the assignment on the following lines.
* Needs `QuestieDB.questKeysReversed` / `npcKeysReversed` / `itemKeysReversed` /
  `objectKeysReversed` for the message text.

---

## 5. CI

`.github/workflows/ci.yml`. The relevant job, verbatim (lines 65–102):

```yaml
  db-validation:
    runs-on: ubuntu-latest
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name != github.event.pull_request.base.repo.full_name
    env:
      TZ: Europe/Berlin
    strategy:
      matrix:
        expansion: [era, sod, tbc, wotlk, mop, localization]
      fail-fast: false

    steps:
      - name: Checkout project
        uses: actions/checkout@v7.0.0

      - name: Install Lua
        uses: leafo/gh-actions-lua@v13.0.0
        with:
          luaVersion: "5.1"

      - name: Install luarocks packages
        uses: leafo/gh-actions-luarocks@v6.1.0
        with:
          luaRocksVersion: "3.13.0"

      - name: Install dependencies
        run: |
          luarocks install bit32 5.3.5.1-1
          luarocks install luafilesystem 1.8.0-1

      - name: Validate ${{ matrix.expansion }} database
        run: lua cli/validate-${{ matrix.expansion }}.lua

      - name: Upload correction files
        uses: actions/upload-artifact@v7.0.1
        with:
          name: correction-files-${{ matrix.expansion }}
          path: cli/output/
        if: success() || failure()
```

Notes:
* Matrix is `[era, sod, tbc, wotlk, mop, localization]` — **`cata` is NOT in CI** even though
  `cli/validate-cata.lua` exists.
* `fail-fast: false`, so all six run regardless.
* `TZ: Europe/Berlin` (the holiday/event corrections are date-sensitive).
* No `busted` in this job; the validators are plain `lua` scripts.
* `cli/output/` is uploaded as artifact `correction-files-<expansion>` on success *and* failure.
* Triggers: `push` on `'**'`, `pull_request` (opened/synchronize/reopened), and `workflow_call`.
* The `notify` job (`needs: [luacheck, unit-tests, db-validation]`, `if: failure()`) posts to
  Discord via `nebularg/actions-discord-webhook@v1.0.0` with `secrets.DISCORD_WEBHOOK`.
* Two sibling jobs: `luacheck` (`nebularg/actions-luacheck@v1.1.2`, files
  `Database Localization Modules Public Questie.lua`, args `-q`) and `unit-tests`.

Local / docker invocation:
* `README.md:82` — "`lua cli/validate-<expansion>.lua`".
* `AGENTS.md:33-37` lists era, tbc, wotlk, mop, sod. `AGENTS.md` also states:
  *"**Note:** Any change to `cli/validators.lua` must be accompanied by a matching test in
  `cli/validators.test.lua`."*
* `.dockerfiles/setup.sh` (run by `.dockerfiles/docker-compose.yml`, image
  `nickblah/lua:5.1-luarocks`, repo mounted at `/code`):
  ```bash
  cd code
  lua ./cli/validate-era.lua
  lua ./cli/validate-sod.lua
  lua ./cli/validate-tbc.lua
  lua ./cli/validate-wotlk.lua
  ```

---

## 6. `cli/validators.test.lua`

**Yes — it is a busted suite.** Structure:

* `local Validators = require("cli.validators")` (line 1), `local exitMock` (line 2).
* Plain-string key tables at lines 4–35: `questKeys`, `npcKeys`, `objectKeys`, `raceKeys`.
  They map each field name **to its own name as a string** (e.g. `startedBy = "startedBy"`), so
  the tests can write readable fixtures. `raceKeys` in the tests is only
  `{ALL_ALLIANCE = 18875469, ALL_HORDE = 33555378, PANDAREN_ALLIANCE = 16777216, PANDAREN_HORDE = 33554432}`
  → ceiling `102 762 495`.
* Outer `describe("Validators", ...)` (line 38) with:
  ```lua
  before_each(function()
      exitMock = spy.new(function() end)
      _G.os = {
          exit = exitMock
      }
      _G.print = function() end -- disable print
  end)
  ```
  i.e. the **whole `os` table is replaced** with `{exit = <spy>}` and `print` is silenced.
* 16 inner `describe` blocks (one per exported check) and **53** `it` cases:

| describe | line | its |
| --- | --- | --- |
| `checkRequiredSourceItems` | 47 | 2 |
| `checkPreQuestExclusiveness` | 96 | 4 (incl. explicit cases for quests 30277 and 30280) |
| `checkParentChildQuestRelations` | 163 | 5 (incl. *"should ignore parent quests which were corrected to be 0"*) |
| `checkQuestStarters` | 275 | 5 |
| `checkQuestFinishers` | 371 | 3 |
| `checkObjectives` | 429 | 5 |
| `checkNpcQuestStarts` | 541 | 3 |
| `checkNpcQuestEnds` | 653 | 4 (incl. *"should skip finishedBy entries of quests"*) |
| `checkObjectQuestStarts` | 782 | 3 |
| `checkObjectQuestEnds` | 894 | 3 |
| `checkRequiredRaces` | 1005 | 3 |
| `checkNpcSpawnAreaIds` | 1058 | 3 |
| `checkObjectSpawnAreaIds` | 1103 | 3 |
| `checkQuestExtraObjectiveSpawnAreaIds` | 1148 | 4 |
| `checkQuestTriggerEndSpawnAreaIds` | 1212 | 3 |

* The four `*AreaIds` describes each define a `before_each` supplying
  `getUiMapIdByAreaId = function(areaId) local known = { [1519] = 84, [12] = 37 } return known[areaId] end`.
* Assertions are `assert.are_same(<expected>, result)` plus
  `assert.spy(exitMock).was.called_with(1)` / `.was.not_called()`.

**Invocation**: it is picked up by the repo-wide busted run — there is **no** `.busted` config
file; the pattern comes from the command line.
* CI job `unit-tests` (`.github/workflows/ci.yml:36-63`): Lua 5.1 + luarocks 3.13.0, installs
  `bit32 5.3.5.1-1`, `busted 2.2.0-1`, `luafilesystem 1.8.0-1`, `TZ: Europe/Berlin`, then
  `run: busted -p ".test.lua" .`
* `README.md:75` and `AGENTS.md:14` — `busted -p ".test.lua" .` from the repo root.
* Single file: `busted cli/validators.test.lua`; filter: `busted -p ".test.lua" --filter "<desc>" .`

---

## 7. Gotchas / traps for the port

1. **First failure aborts everything.** `os.exit(1)` lives inside each check, not in the driver.
   No aggregation, no summary, and later checks (and their correction files) never run.
   A QuestieTDB port that collects all failures will surface *more* problems than Questie's CI
   currently shows.
2. **The `return` after `os.exit(1)` is dead code in production.** It exists only so the busted
   tests (which stub `os.exit`) can assert on the result tables. Preserve the return values if
   you want to reuse the test suite.
3. **`os.getenv("PWD")` at module load**, plus `lfs.mkdir` as an import side effect. Requires a
   POSIX shell launch and cwd == repo root. Windows `cmd` does not export `PWD`.
4. **Running the unit tests writes real files** into `cli/output/` — the four checked-out
   `cli/output/*Corrections.lua` files contain `-- First NPC` / `-- Third Object` comments from
   the test fixtures, not real data. `io` is never mocked, only `os`.
5. **Unguarded index in `checkNpcQuestStarts` (validators.lua:380) and
   `checkObjectQuestStarts` (validators.lua:611)**: `npcs[npcStarterId][npcKeys.questStarts]`.
   A quest whose `startedBy` names a nonexistent NPC/object crashes with a Lua error rather than
   a validation message. The `*QuestEnds` twins guard correctly (lines 494, 725).
6. **`tableContainsAll` is not set equality** — it ignores duplicates and multiplicity. Two
   `tableContainsAll` calls are used to fake bidirectional containment. Carrying the TODO forward
   is fine; "fixing" it may change which NPCs get pruned from the correction output.
7. **Hidden-quest ordering is significant**: `checkNpcQuestStarts/Ends` and
   `checkObjectQuestStarts/Ends` deliberately run **before** hidden quests are stripped
   (`-- We accept blacklisted quests as questStarts and questEnds for now`). Moving the strip
   earlier will produce a flood of "questStart X is not in the database".
8. **Coverage is not uniform**: cata skips `checkRequiredRaces`; mop skips all four
   questStarts/questEnds relation checks; cata is not in the CI matrix at all; localization runs
   zero validators.
9. **`checkRequiredRaces`'s ceiling is a sum over `pairs(raceKeys)`**, including the composite
   `ALL_ALLIANCE`/`ALL_HORDE` constants. It is deliberately loose. If QuestieTDB supplies a
   different `raceKeys` shape (e.g. only the individual bits) the ceiling drops and previously
   passing quests will fail.
10. **`raceKeys` is expansion-dependent** and is itself computed from `Questie.IsClassic` /
    `IsTBC` / … at `Database/QuestieDB.lua:122`. Get the flavor right before reading it.
11. **`checkObjectives` returns `table<QuestId, string[]>`** while its `---@return` annotation
    says `table<QuestId, string>`; #1–#5 and #11 return `table<Id, string>`; #2 returns
    `table<Id, true>`; #12–#15 return `table<Id, number[]>`. Four different result shapes.
12. **The reason string for a quest is overwritten, not accumulated,** in #1, #3, #4, #5 and #11.
    A quest with three bad starters reports only the last one.
13. **Copy-paste text bugs to keep or fix consciously**: `checkObjectQuestEnds` prints
    "No **NPCs** found with invalid questEnds" (validators.lua:818); its `---@return` says
    `table<NpcId, string>` (line 710); `checkNpcSpawnAreaIds`'s `@param npcs table<NpcId, Npc>`
    uses `Npc` instead of `NPC` (line 863).
14. **stdout vs stderr split**: validator findings → stdout (global `print`), driver progress and
    `Questie:Warning` → stderr (`cli/print.lua`). CI logs interleave them; a port that unifies
    them changes the artifact/triage story.
15. **`coroutine.yield` is globally no-op'd** by `apiMocks.lua:20` (with its own
    `TODO: maybe find a less hacky fix`), and `C_Timer.NewTicker` busy-loops against a fake
    ticker planted on the `DBCompiler` module. Anything that needs real coroutines will break.
16. **`ZoneDB:GetUiMapIdByAreaId` logs via `Questie:Debug(Questie.DEBUG_CRITICAL, ...)`** when a
    lookup misses (`zoneDB.lua:88`). The drivers replace `Questie.Debug` with a no-op **after**
    `loadTOC` but **before** `ZoneDB:Initialize()`, so the misses the validators intentionally
    provoke stay silent. If `Questie.Debug` is not stubbed, expect one debug line per unknown
    areaId per entity.
17. **`ZoneDB` needs both the base table and the override table** merged
    (`zoneDB.lua:40-46`); MoP uses a different pair of files
    (`Database/Zones/data/MoP/areaIdToUiMapId.lua`). A port that only carries the generated table
    will produce false "areaId not handled" failures for the manual overrides
    (`[0]=0`, `[2257]=0` Deeprun Tram, `[2917]=0`, `[2918]=0`, `[10073]=1414`, `[10074]=1415`, …).
18. **`Questie.db.global.debugEnabled = true` is set *after* `ZoneDB:Initialize()`** and
    `ZoneDB` reads `Questie.db.**profile**.debugEnabled` — so `_ZoneDB:RunTests()` never runs in
    CLI mode. Do not "fix" this: `RunTests` needs a real `C_Map`.
19. **`validate-tbc.lua` never sets `debugEnabled`** while all other drivers do. Whether that is
    intentional is unclear; it changes compiler verbosity.
20. **`loadTOC` strips all whitespace from every path** and skips every `.xml` include, so the
    localization lookups and `embeds.xml` libraries are simply absent unless `dofile`d manually
    (see `validate-localization.lua`).
21. **`cli/dump.lua` is required first and never used.** Its top-level loop over `getfenv(0)`
    snapshots the global function/userdata symbols; requiring it after `apiMocks` would change
    that snapshot. Harmless, but do not reorder blindly.
