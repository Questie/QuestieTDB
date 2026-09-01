# Questie: object-hover tooltips without a database scan

Implementation guide for the Questie side of ADR 0008 (`docs/adr/0008-name-index.md`). It
replaces the "Object-hover tooltip name index" task: the plan there — build a full name index
from composed Object ids after init and rebuild it on every locale change and Correction
apply — is withdrawn. This is what to do instead.

Lives at the QuestieTDB root for now; it moves to Questie with the work.

## The shape

A hovered world object gives Questie a name and nothing else. Two different questions hide
behind that name, and they get two different answers:

| Question | Source | Cost |
| --- | --- | --- |
| Which objects with this name have quest tooltip data? | `QuestieTooltips.objectIdsByName`, filled when Questie registers an `o_` tooltip | O(1) per registration, nothing at boot |
| Which objects in the database have this name? — the "Object ID" line behind `enableTooltipsObjectID`, off by default | `LibQuestieDB.Object.IdsByName(name)` | One full pass — 23 ms on Vanilla, measured live — paid at init or on toggle, never on hover |

Why the split: `QuestieTooltips.GetTooltip("o_" .. id)` reads `lookupByKey`, the same table
the register functions fill, so a registration set keyed by name cannot disagree with what a
hover will find. The old full scan only ever produced a superset that the hover loop
filtered back down by calling `GetTooltip` per id. The database-wide answer is needed only for
the ID line, which is a contributor setting in all but name.

## Step 1 — index `o_` registrations by name (`Modules/Tooltips/Tooltip.lua`)

Next to `lookupByKey`:

```lua
---Object name -> { [objectId] = true } for every object Questie has registered an "o_"
---tooltip for. A hovered world object is identified by name only, so this is how the hover
---finds the ids that have quest data. Append-only on purpose: an id whose quests were all
---removed simply has no tooltip data any more, which GetTooltip answers with nil, so removal
---needs no bookkeeping and RemoveQuest stays untouched.
---@type table<string, table<ObjectId, true>>
QuestieTooltips.objectIdsByName = {}

---@param key string
local function _IndexObjectKeyByName(key)
    if key:sub(1, 2) ~= "o_" then
        return
    end
    local objectId = tonumber(key:sub(3))
    local name = objectId and LibQuestieDB.Object.name(objectId)
    if not name then
        return
    end
    local ids = QuestieTooltips.objectIdsByName[name]
    if not ids then
        ids = {}
        QuestieTooltips.objectIdsByName[name] = ids
    end
    ids[objectId] = true
end
```

Call it first thing in both register functions:

```lua
function QuestieTooltips:RegisterObjectiveTooltip(questId, key, objective)
    _IndexObjectKeyByName(key)
    -- ... unchanged

function QuestieTooltips:RegisterQuestStartTooltip(questId, name, starterId, key, type)
    _IndexObjectKeyByName(key)
    -- ... unchanged
```

Notes:

- `LibQuestieDB.Object.name(id)` — or whatever the seam exposes for a single-field object
  read at the time — is one cached read, in the entity locale current at registration. Questie
  reloads the UI on an effective locale change today (`QuestieOptionsAdvanced.lua`, the
  `ReloadUI()` after `SetUILocale`); keep that, and registrations are always in the locale the
  client displays. If a runtime locale switch without reload is ever introduced, clearing
  `objectIdsByName` from `LibQuestieDB.l10n.onLocaleChanged` is the one-liner. Do not build
  it now.
- Resolving from the key keeps both register signatures unchanged. `RegisterQuestStartTooltip`
  already receives `name`, the objective path does not; one path is simpler than two.
- The "fake id" objects (extra spawn locations under a real object's name) register under the
  same name and bucket together, which is what the line dedup in the hover already expects.
- It is a set, not a list: abandon/re-accept cycles must not duplicate ids.
- Accepted residual: a Dynamic Correction applied *after* a registration that renames that
  object leaves its quest lines under the old name until the tooltip is registered again (next
  quest accept or reload). No Correction renames an object at runtime today; ADR 0008 D1
  records this. The database index in Step 2 is unaffected — it is rebuilt on every apply.
- Only `o_` keys matter. `io_` is a map-icon key; the tooltip for an item-from-object starter
  is registered under `o_` (`AvailableQuests.lua`).

## Step 2 — the hover (`Modules/Tooltips/TooltipHandler.lua`)

```lua
---@param name string
---@param playerZone AreaId
function _QuestieTooltips.AddObjectDataToTooltip(name, playerZone)
    if (not Questie.db.profile.enableTooltips) or (not name) then
        return
    end

    if Questie.db.profile.enableTooltipsObjectID then
        -- Every object in the database with this name, not only the quest-active ones:
        -- contributors use this line to find ids for Corrections. The index behind it is
        -- warmed at init and on toggle, so this is a lookup, not a scan.
        local ids = LibQuestieDB.Object.IdsByName(name)
        local count = ids and #ids or 0
        if count == 1 then
            GameTooltip:AddDoubleLine(l10n("Object ID"), "|cFFFFFFFF" .. ids[1] .. "|r")
        elseif count > 10 and (not Questie.db.profile.debugEnabled) then
            GameTooltip:AddDoubleLine(l10n("Object ID"), "|cFFFFFFFF" .. ids[1] .. " (10+)|r")
        elseif count > 1 then
            GameTooltip:AddDoubleLine(l10n("Object ID"), "|cFFFFFFFF" .. ids[1] .. " (" .. count .. ")|r")
        end
    end

    -- Quest lines come from the objects Questie registered tooltips for. An id whose quests
    -- were removed is still in the set and costs one GetTooltip call that answers nil.
    local addedObjects = 0
    local alreadyAddedObjectiveLines = {}
    for gameObjectId in pairs(QuestieTooltips.objectIdsByName[name] or {}) do
        if addedObjects >= 10 then
            break -- only show 10 objects' worth of lines
        end
        local tooltipData = QuestieTooltips.GetTooltip("o_" .. gameObjectId, playerZone)
        if tooltipData then
            for _, line in pairs(tooltipData) do
                if (not alreadyAddedObjectiveLines[line]) then
                    alreadyAddedObjectiveLines[line] = true
                    GameTooltip:AddLine(line)
                end
            end
            addedObjects = addedObjects + 1
        end
    end
    GameTooltip:Show()
    QuestieTooltips.lastGametooltipType = "object";
end
```

What changed and what did not:

- The ID line keeps its one / `(n)` / `(10+)` presentation and the debug-mode exception. Its
  count now comes from the database index. **Never** count the registration set for it — that
  set is append-only, so its size means nothing.
- The quest-line loop keeps the line dedup and the 10-object cap. The `count > 10 and` guard
  on the break is gone because `addedObjects >= 10` alone gives the same result.
- Nothing is read from `l10n` any more except the "Object ID" label.

## Step 3 — warm the database index where a stall is invisible

`IdsByName` builds its index on first use and drops it on every Correction apply, locale
change, or `InvalidateCache`. Left alone, that is a hitch on the first hover after each of
those — 23 ms on Vanilla measured in a live client, roughly three times that on Mists — in
debug mode only. Hide it:

**At init** — `Modules/QuestieInit.lua`, Stage 2, in place of `l10n:PostBoot()`. It must run
*after* Questie's own `LibQuestieDB.ApplyRegisteredCorrections("Questie")` (Stage 1, where
`QuestieCorrections:MinimalInit()` sits today), because the apply drops the index:

```lua
    if Questie.db.profile.enableTooltipsObjectID then
        -- Contributors keep this on permanently; pay for the name index here rather than on
        -- the first hover. Synchronous — unlike the old PostBoot scan it cannot yield — and
        -- 23 ms on Vanilla (more on larger flavors), fine inside init behind a debug setting.
        LibQuestieDB.Object.BuildNameIndex()
    end
```

**On toggle** — `Modules/Options/AdvancedTab/QuestieOptionsAdvanced.lua`, the
`enableTooltipsObjectID` option:

```lua
                set = function(_, value)
                    Questie.db.profile.enableTooltipsObjectID = value
                    if value then
                        LibQuestieDB.Object.BuildNameIndex()
                    end
                end
```

Turning it off does nothing; the index stays until the next invalidation — about 2.2 MB on
Vanilla, most of it the warmed name cache the database keeps for the session anyway.

Residual, accepted: with the setting on, the first hover after a later Correction apply (a
third-party addon, a Darkmoon location change) or a runtime locale change rebuilds
synchronously once. If that ever matters, re-warm from `LibQuestieDB.l10n.onLocaleChanged` and
after Questie's own `Apply()` calls — not before.

## Step 4 — delete the legacy index

- `Localization/l10n.lua`: `l10n.objectNameLookup`, its `---@field` annotation, and
  `l10n:PostBoot()` entirely.
- `Modules/QuestieInit.lua`: the `l10n:PostBoot()` call and its debug line in Stage 2.
- Afterwards, with the tests below updated, `grep -rn objectNameLookup` must hit nothing at
  all, and nothing in production reads raw Object tables for this.

`l10n:Initialize()`'s entity writes are a separate checklist item in
`docs/questie-handover.md` and are not part of this change.

## Tests

`Modules/Tooltips/TooltipHandler.test.lua` — the existing five cases keep their assertions
with one exception; the seeding changes:

- Quest-line cases seed `QuestieTooltips.objectIdsByName[name] = { [1] = true, [2] = true }`
  instead of `l10n.objectNameLookup[name] = { 1, 2 }`.
- ID-line cases stub the database with what each case expects — `_G.LibQuestieDB = { Object =
  { IdsByName = function() return { 1 } end } }` for the single-ID case, `{ 1, 2 }` for the
  `(2)` case, eleven ids for the `(10+)` case — or whatever the test setup exposes.
- The `(10+)` case seeds eleven ids in the set for its `GetTooltip.was.called(10)` assertion
  and **drops** `was.not_called_with("o_11", ...)`: the set is iterated with `pairs`, so which
  ten are visited is not defined. It would only pass by hash-layout luck.
- Reset `Questie.db.profile.enableTooltipsObjectID = false` in `before_each`; the file never
  resets it today, and with the split a stale `true` sends a quest-line case into the
  `LibQuestieDB` stub.
- Drop the `l10n` import from the test file if nothing else uses it.

`Modules/Tooltips/Tooltip.test.lua` — two focused cases for Step 1, with a
`LibQuestieDB.Object.name` stub added to its `before_each` (it stubs `QuestieDB` only today):

- `RegisterObjectiveTooltip` with `"o_5"` adds `5` under the object's name; registering the
  same key for a second quest does not duplicate it.
- An `i_` or `m_` key adds nothing.

No test for removal — there is none.

## Acceptance

The original task's checks, restated against this design:

- Object-hover tooltips still show deduplicated quest/objective lines — Step 2, unchanged loop.
- The optional Object ID line preserves the one, many, and `10+` presentation — Step 2.
- Rebuilding replaces old-locale names and does not append duplicate Object IDs — the database
  index is rebuilt from scratch on every invalidation (QuestieTDB's `name-index` suite); the
  registration set is a set, and is locale-stable within a session because a locale change
  reloads.
- Correction-added Objects become discoverable and withdrawn Objects disappear — proven for
  `IdsByName` in the `name-index` suite; for quest lines, an added object is discoverable the
  moment a quest registers a tooltip for it.
- No production code reads raw Object tables or `l10n.objectNameLookup` — Step 4.
