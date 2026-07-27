-- src/corrections/compat.lua
--
-- The module surface Questie's correction files expect.
--
-- The correction files under `src/corrections/<Expansion>/` are **byte-identical copies** of
-- Questie's. That is deliberate: they are ~10 MB of hand-curated data, and rewriting their
-- preambles would be 10 MB of opportunities to introduce a transcription error, plus a
-- permanent merge conflict with upstream. Re-syncing is a file copy, run by
-- `tools/port-corrections.lua`.
--
-- The price is this file: a scoped stand-in for `QuestieLoader` and the handful of Questie
-- modules those files import. It is installed only while correction files are being loaded and
-- removed immediately afterwards, so nothing here leaks into the consumer's environment.

local _, LibQuestieDB = ...

local compat = {}

local constants = LibQuestieDB.Enum

--------------------------------------------------------------------------------------------
-- Module stand-ins
--------------------------------------------------------------------------------------------

--- `QuestieCorrections.itemObjectiveFirst[503] = true` and friends are module-level side
--- effects in the correction files. They are consumer hints about objective ordering, not
--- entity data, so they are collected and published rather than merged into the database.
compat.objectiveFirst = {
  killCreditObjectiveFirst = {},
  objectObjectiveFirst = {},
  itemObjectiveFirst = {},
  eventObjectiveFirst = {},
  spellObjectiveFirst = {},
}

--- Direct writes such as `QuestieDB.questData[5640] = {}` — how `LoadMissingQuests` and the
--- `InsertMissing*Ids` helpers make the database emit a row at all. Captured per datatype so
--- the apply path can fold them in alongside the function's return value.
compat.captured = { Quest = {}, Npc = {}, Item = {}, Object = {} }

local DATA_FIELD_TO_TYPE = {
  questData = "Quest", npcData = "Npc", itemData = "Item", objectData = "Object",
}

local function buildQuestieDB()
  local QuestieDB = {
    questKeys = constants.questKeys,
    npcKeys = constants.npcKeys,
    itemKeys = constants.itemKeys,
    objectKeys = constants.objectKeys,
    raceKeys = constants.raceKeys,
    classKeys = constants.classKeys,
    sortKeys = constants.sortKeys,
    specialFlags = constants.specialFlags,
    factionIDs = constants.factionIDs,
    questFlags = constants.questFlags,
    npcFlags = constants.npcFlags,
    itemClasses = constants.itemClasses,
    waypointPresets = constants.waypointPresets,
  }

  for name, datatype in pairs(DATA_FIELD_TO_TYPE) do
    QuestieDB[name] = compat.captured[datatype]
  end

  -- The reversed maps exist only to render a CI warning message in Questie's merge helper;
  -- they are provided so a file that touches them does not fault.
  local function reverse(keys)
    local reversed = {}
    for key, index in pairs(keys) do reversed[index] = key end
    return reversed
  end
  QuestieDB.questKeysReversed = reverse(constants.questKeys)
  QuestieDB.npcKeysReversed = reverse(constants.npcKeys)
  QuestieDB.itemKeysReversed = reverse(constants.itemKeys)
  QuestieDB.objectKeysReversed = reverse(constants.objectKeys)

  return QuestieDB
end

local function buildModules()
  local modules = {}

  modules.QuestieDB = buildQuestieDB()
  modules.ZoneDB = { zoneIDs = constants.zoneIDs }
  modules.QuestieProfessions = {
    professionKeys = constants.professionKeys,
    specializationKeys = constants.specializationKeys,
    rankNames = constants.rankNames,
  }
  modules.QuestieCorrections = compat.objectiveFirst
  modules.Phasing = { phases = constants.phases }

  -- `l10n(...)` appears ~100 times in classicQuestFixes and ~207 times in tbcQuestFixes,
  -- always inside `extraObjectives`. **Store the enUS string, translate at render time** —
  -- Questie's l10n is keyed by the English string, so the output is identical and the database
  -- stays locale-free. The prototype's correction files stubbed it exactly this way.
  modules.l10n = setmetatable({}, { __call = function(_, text) return text end })

  modules.Expansions = {
    Era = 1, Classic = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1,
  }

  return modules
end

--------------------------------------------------------------------------------------------
-- Scoped installation
--------------------------------------------------------------------------------------------

local saved

--- Install the shim. Returns a function that removes it again.
---
--- Scoped rather than permanent because `QuestieLoader` and `Questie` belong to the consumer;
--- QuestieTDB borrows them for the duration of loading its own correction files and gives them
--- straight back.
function compat.Install(flavor)
  local expansionOrder = LibQuestieDB.Corrections.expansionOrder
  local order = (flavor and expansionOrder[flavor.expansion]) or 1

  saved = { QuestieLoader = rawget(_G, "QuestieLoader") }

  local modules = buildModules()
  modules.Expansions.Current = order
  compat.modules = modules

  _G.QuestieLoader = {
    ImportModule = function(_, name)
      modules[name] = modules[name] or {}
      return modules[name]
    end,
    CreateModule = function(_, name)
      modules[name] = modules[name] or {}
      return modules[name]
    end,
  }

  -- `Questie.ICON_TYPE_*` is referenced directly by correction files, alongside `Questie.Is*`
  -- flags — and unlike the module imports, those are read from the **global at apply time**,
  -- not captured at load time. So this one is *augmented in place and left installed* rather
  -- than removed with the rest of the shim: tearing it down would leave every Dynamic
  -- Correction reading a nil global the moment it ran.
  --
  -- In a client the consumer owns this table. QuestieTDB loads first, so it may not exist yet;
  -- the fields written here are only ever the ones that are missing, and the consumer's own
  -- definitions win as soon as it loads. Its `ApplyRegisteredCorrections` call then recomposes
  -- against the real values.
  local questie = rawget(_G, "Questie")
  if type(questie) ~= "table" then questie = {} end
  for name, value in pairs(constants.iconTypes) do
    if questie[name] == nil then questie[name] = value end
  end
  if questie.IsClassic == nil then questie.IsClassic = (order == 1) end
  if questie.IsTBC == nil then questie.IsTBC = (order == 2) end
  if questie.IsWotlk == nil then questie.IsWotlk = (order == 3) end
  if questie.IsCata == nil then questie.IsCata = (order == 4) end
  if questie.IsMoP == nil then questie.IsMoP = (order == 5) end
  if questie.IsSoD == nil then questie.IsSoD = false end
  if questie.IsSoM == nil then questie.IsSoM = false end
  if questie.IsHardcore == nil then questie.IsHardcore = false end
  if questie.IsAnniversary == nil then questie.IsAnniversary = false end
  if questie.IsTitanRuneReforged == nil then questie.IsTitanRuneReforged = false end
  if questie.IsChinaRegion == nil then questie.IsChinaRegion = false end
  questie.db = questie.db or { profile = {}, global = {}, char = {} }
  _G.Questie = questie

  return compat.Remove
end

function compat.Remove()
  if not saved then return end
  _G.QuestieLoader = saved.QuestieLoader
  saved = nil
end

--------------------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------------------

--- Clear the direct-write buffers before invoking a correction function.
function compat.BeginCapture()
  for datatype in pairs(compat.captured) do
    local buffer = compat.captured[datatype]
    for id in pairs(buffer) do buffer[id] = nil end
  end
end

--- What a correction function wrote directly, for one datatype.
function compat.EndCapture(datatype)
  return compat.captured[datatype]
end

LibQuestieDB.CorrectionCompat = compat

return compat
