-- src/corrections/compat.lua
--
-- The module surface Questie's correction files expect.
--
-- The correction files under `src/corrections/<Expansion>/` preserve Questie's bytes exactly
-- outside the provider/consumer ownership exclusions explicitly declared by
-- `tools/port-corrections.lua`.
-- That fidelity avoids transcription errors across ~10 MB of hand-curated data and keeps
-- upstream re-syncs mechanical: copy each file, then apply only the declared exclusions.
--
-- The price is this file: scoped stand-ins for `QuestieLoader`, the handful of Questie
-- modules those files import, and the icon constants their providers read later. The loader is
-- installed only while correction files load. The `Questie` stand-in exists in the global
-- namespace only while a registered provider runs, and both globals are restored afterwards.

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

--- The enum's flat tables hold Classic values; expansion-varying constants (race masks,
--- npc flags, ALL_CLASSES — see the generated header) also appear per expansion under
--- `constants.byExpansion`. Serving the flavor's own set here is what keeps Era correction
--- files, which apply on every expansion, from baking Era-valued masks into TBC+ flavors.
local function pick(name, expansionName)
  local per = constants.byExpansion and constants.byExpansion[expansionName]
  local value = per and per[name]
  if value ~= nil then return value end
  return constants[name]
end

local function buildQuestieDB(expansionName)
  local QuestieDB = {
    questKeys = pick("questKeys", expansionName),
    npcKeys = pick("npcKeys", expansionName),
    itemKeys = pick("itemKeys", expansionName),
    objectKeys = pick("objectKeys", expansionName),
    raceKeys = pick("raceKeys", expansionName),
    classKeys = pick("classKeys", expansionName),
    sortKeys = pick("sortKeys", expansionName),
    specialFlags = pick("specialFlags", expansionName),
    factionIDs = pick("factionIDs", expansionName),
    questFlags = pick("questFlags", expansionName),
    npcFlags = pick("npcFlags", expansionName),
    itemClasses = pick("itemClasses", expansionName),
    waypointPresets = pick("waypointPresets", expansionName),
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
  QuestieDB.questKeysReversed = reverse(QuestieDB.questKeys)
  QuestieDB.npcKeysReversed = reverse(QuestieDB.npcKeys)
  QuestieDB.itemKeysReversed = reverse(QuestieDB.itemKeys)
  QuestieDB.objectKeysReversed = reverse(QuestieDB.objectKeys)

  return QuestieDB
end

local function buildModules(expansionName)
  local modules = {}

  modules.QuestieDB = buildQuestieDB(expansionName)
  modules.ZoneDB = { zoneIDs = pick("zoneIDs", expansionName) }
  modules.QuestieProfessions = {
    professionKeys = pick("professionKeys", expansionName),
    specializationKeys = pick("specializationKeys", expansionName),
    rankNames = pick("rankNames", expansionName),
  }
  modules.QuestieCorrections = compat.objectiveFirst
  modules.Phasing = { phases = pick("phases", expansionName) }

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

-- Copied providers resolve these constants through the global at invocation time. Keep the
-- stand-in private between calls so Questie's duplicate-installation check sees an unclaimed
-- global when it loads after QuestieTDB.
local correctionQuestie = {}
for name, value in pairs(constants.iconTypes) do correctionQuestie[name] = value end

--- Installs the loader shim while the copied correction files define their modules.
---@param flavor table? Active database flavor.
---@return fun(): nil remove Restores the previous `QuestieLoader`.
function compat.Install(flavor)
  local expansionOrder = LibQuestieDB.Corrections.expansionOrder
  local order = (flavor and expansionOrder[flavor.expansion]) or 1

  saved = { QuestieLoader = rawget(_G, "QuestieLoader") }

  local modules = buildModules((flavor and flavor.expansion) or "Classic")
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

  return compat.Remove
end

--- Restores the loader global saved by `Install`.
---@return nil
function compat.Remove()
  if not saved then return end
  _G.QuestieLoader = saved.QuestieLoader
  saved = nil
end

--- Invokes a copied correction provider with its private `Questie` constants available.
--- Restoration happens before an error is rethrown, so a bad provider cannot block Questie.
---@param func fun(...): table? Copied correction provider.
---@param ... any Provider receiver and arguments.
---@return table? corrections Provider result.
function compat.Invoke(func, ...)
  local previousQuestie = rawget(_G, "Questie")
  rawset(_G, "Questie", correctionQuestie)

  local ok, returned = pcall(func, ...)
  rawset(_G, "Questie", previousQuestie)

  if not ok then error(returned, 0) end
  return returned
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
