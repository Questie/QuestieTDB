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

-- Inapplicable files still define providers, but their hint writes must not enter the
-- published tables. Keep both collections stable for modules that capture local references.
local discardedObjectiveFirst = {}
for field in pairs(compat.objectiveFirst) do discardedObjectiveFirst[field] = {} end

---@param hints table<string, table<number, boolean>>
---@return nil
local function clearHints(hints)
  for _, ids in pairs(hints) do
    for id in pairs(ids) do ids[id] = nil end
  end
end

---Select the hint destination before the next correction file imports its modules.
---This does not suppress provider definitions or alter any entity-data stand-in.
---@param enabled boolean
---@return nil
function compat.SelectObjectiveFirstScope(enabled)
  compat.modules.QuestieCorrections = enabled and compat.objectiveFirst or discardedObjectiveFirst
end

--- Direct writes such as `QuestieDB.questData[5640] = {}` — how `LoadMissingQuests` and the
--- `InsertMissing*Ids` helpers make the database emit a row at all. Captured per datatype so
--- the apply path can fold them in alongside the function's return value.
compat.captured = { Quest = {}, Npc = {}, Item = {}, Object = {} }

local DATA_FIELD_TO_TYPE = {
  questData = "Quest", npcData = "Npc", itemData = "Item", objectData = "Object",
}

---Selects a shared invariant or an explicitly expansion-scoped constant table.
---Expansion-varying tables have no flat Classic copy: a missing expansion or name is a
---contract error rather than permission to bake an Era value into another flavor.
---@param name string Constant table name.
---@param expansionName string Explicit supported expansion name.
---@return table value
local function pick(name, expansionName)
  local shared = constants[name]
  if shared ~= nil then return shared end

  local byExpansion = constants.byExpansion
  local expansionConstants = byExpansion and byExpansion[expansionName]
  if type(expansionConstants) ~= "table" then
    error("correction compat: constants are missing expansion data for " .. expansionName, 0)
  end

  local value = expansionConstants[name]
  if value == nil then
    error(("correction compat: unknown constant `%s` for expansion `%s`")
      :format(name, expansionName), 0)
  end
  return value
end

---Builds the QuestieDB stand-in with constants selected for one explicit expansion.
---@param expansionName string Supported expansion name.
---@return table QuestieDB
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

---Builds all copied-provider module stand-ins for one explicit expansion.
---@param expansionName string Supported expansion name.
---@return table modules
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

---Installs the loader shim while the copied correction files define their modules.
---@param flavor table Active supported database flavor.
---@return fun(): nil remove Restores the previous `QuestieLoader`.
function compat.Install(flavor)
  if type(flavor) ~= "table" then
    error("correction compat: Install requires an explicit flavor table", 2)
  end

  local expansionName = flavor.expansion
  local configuredFlavor = LibQuestieDB.config.flavorByName[flavor.name]
  local expansionOrder = LibQuestieDB.Corrections.expansionOrder
  local order = expansionOrder[expansionName]
  if not configuredFlavor or configuredFlavor.expansion ~= expansionName or not order then
    error(("correction compat: unsupported flavor `%s` / expansion `%s`")
      :format(tostring(flavor.name), tostring(expansionName)), 2)
  end
  if type(constants.byExpansion) ~= "table" or
     type(constants.byExpansion[expansionName]) ~= "table" then
    error("correction compat: constants are missing expansion data for " .. expansionName, 2)
  end

  -- Build before changing globals so malformed generated constants fail without side effects.
  local modules = buildModules(expansionName)
  modules.Expansions.Current = order

  -- A reinstall starts a new load without replacing the published table identities.
  clearHints(compat.objectiveFirst)
  clearHints(discardedObjectiveFirst)
  saved = { QuestieLoader = rawget(_G, "QuestieLoader") }
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
  clearHints(discardedObjectiveFirst)
  compat.modules.QuestieCorrections = compat.objectiveFirst
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
