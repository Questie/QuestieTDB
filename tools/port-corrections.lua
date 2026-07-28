#!/usr/bin/env lua
-- tools/port-corrections.lua
--
-- One-shot port of Questie's corrections into QuestieTDB.
--
-- Two jobs, both mechanical on purpose:
--
--   1. **Extract the constants** correction files reference — key enums, race and class
--      bitmasks, zone IDs, profession keys, icon types — by executing Questie's own sources
--      under the mocked environment and dumping what they defined. Same discipline as the
--      schema: derived, not transcribed, so it cannot quietly drift.
--
--   2. **Copy the correction files verbatim.** They are 10 MB of hand-curated data, and
--      rewriting their preamble by hand would be 10 MB of opportunities to introduce a
--      transcription error. Instead `src/corrections/compat.lua` supplies the module surface
--      they expect, so the copies stay byte-identical to Questie's and re-syncing later is a
--      file copy.
--
-- Usage: lua tools/port-corrections.lua [path-to-questie]

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")
local serialize = dofile("generator/serialize.lua")

local QUESTIE = arg and arg[1] or "../Questie"

--------------------------------------------------------------------------------------------
-- Constant extraction
--------------------------------------------------------------------------------------------

--- Files to execute, and what to harvest from the modules they touch.
local EXTRACTIONS = {
  { file = "Database/Constants.lua", module = "QuestieDB", names = { "sortKeys" } },
  { file = "Database/questDB.lua", module = "QuestieDB", names = { "questKeys", "questFlags", "factionIDs" } },
  { file = "Database/npcDB.lua", module = "QuestieDB", names = { "npcKeys", "npcFlags" } },
  { file = "Database/itemDB.lua", module = "QuestieDB", names = { "itemKeys", "itemClasses" } },
  { file = "Database/objectDB.lua", module = "QuestieDB", names = { "objectKeys" } },
  { file = "Modules/QuestieProfessions.lua", module = "QuestieProfessions",
    names = { "professionKeys", "specializationKeys", "rankNames" } },
  { file = "Modules/Phasing.lua", module = "Phasing", names = { "phases" } },
}

--- `Database/QuestieDB.lua` is 94 KB of runtime behaviour around three constant tables, so it
--- is sliced rather than executed. The slice is bounded by the exact assignment lines, and the
--- extractor fails loudly if any of them moves.
local SLICES = {
  { file = "Database/QuestieDB.lua", name = "raceKeys", startsWith = "QuestieDB.raceKeys = {" },
  { file = "Database/QuestieDB.lua", name = "classKeys", startsWith = "QuestieDB.classKeys = {" },
  { file = "Database/QuestieDB.lua", name = "specialFlags", startsWith = "QuestieDB.specialFlags = {" },
  { file = "Database/QuestieDB.lua", name = "waypointPresets", startsWith = "QuestieDB.waypointPresets = {" },
  -- `itemDropCorrections.lua` is support data that reads these sentinels from the logic module
  -- staying in Questie, so they have to travel with the data.
  { file = "Database/DropTables/dropDB.lua", name = "dropCorrectionKeys", startsWith = "DropDB.correctionKeys = {" },
  { file = "Questie.lua", name = "iconTypes", pattern = "^Questie%.(ICON_TYPE_[%w_]+)%s*=%s*(%d+)" },
}

local function sliceTable(source, startsWith)
  local startPos = source:find(startsWith, 1, true)
  if not startPos then
    error("port: cannot find `" .. startsWith .. "` — the source moved, update tools/port-corrections.lua", 0)
  end
  local bracePos = source:find("{", startPos, true)
  local depth, pos = 0, bracePos
  repeat
    local char = source:sub(pos, pos)
    if char == "{" then depth = depth + 1 elseif char == "}" then depth = depth - 1 end
    pos = pos + 1
  until depth == 0 or pos > #source
  if depth ~= 0 then error("port: unbalanced braces after `" .. startsWith .. "`", 0) end
  return source:sub(bracePos, pos - 1)
end

local function extractConstants()
  local extracted = {}

  for _, spec in ipairs(EXTRACTIONS) do
    loader.installEnvironment({ isClassic = true })
    local Expansions = QuestieLoader:ImportModule("Expansions")
    Expansions.Classic, Expansions.Era, Expansions.Tbc = 1, 1, 2
    Expansions.Wotlk, Expansions.Cata, Expansions.MoP, Expansions.Current = 3, 4, 5, 1
    local path = QUESTIE .. "/" .. spec.file
    local restore = loader.installPermissiveGlobals()
    local ok, err = pcall(loader.executeFile, path)
    restore()
    if not ok then error(err, 0) end
    local module = QuestieLoader:ImportModule(spec.module)
    for _, name in ipairs(spec.names) do
      if type(module[name]) ~= "table" then
        error("port: " .. spec.file .. " did not define " .. spec.module .. "." .. name, 0)
      end
      extracted[name] = module[name]
    end
  end

  -- Zone IDs live in their own data file and need only the ZoneDB module.
  loader.installEnvironment({ isClassic = true })
  local restoreZone = loader.installPermissiveGlobals()
  local zoneOk, zoneErr = pcall(loader.executeFile, QUESTIE .. "/Database/Zones/data/zoneIds.lua")
  restoreZone()
  if not zoneOk then error(zoneErr, 0) end
  local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
  if type(ZoneDB.zoneIDs) ~= "table" then
    error("port: Database/Zones/data/zoneIds.lua did not define ZoneDB.zoneIDs", 0)
  end
  extracted.zoneIDs = ZoneDB.zoneIDs

  for _, spec in ipairs(SLICES) do
    local source = lib.readAll(QUESTIE .. "/" .. spec.file)
    if spec.pattern then
      local collected = {}
      for line in source:gmatch("[^\n]+") do
        local key, value = line:match(spec.pattern)
        if key then collected[key] = tonumber(value) end
      end
      if next(collected) == nil then
        error("port: no matches for " .. spec.name .. " in " .. spec.file, 0)
      end
      extracted[spec.name] = collected
    else
      local chunk = assert(loadstring("return " .. sliceTable(source, spec.startsWith)),
        "port: cannot parse the slice for " .. spec.name)
      -- Some slices reference other extracted tables — `waypointPresets` is keyed by
      -- `ZoneDB.zoneIDs.*`. Give the chunk an environment holding what has already been
      -- extracted rather than reaching for globals that no longer exist.
      setfenv(chunk, setmetatable({ ZoneDB = { zoneIDs = extracted.zoneIDs } }, { __index = _G }))
      extracted[spec.name] = chunk()
    end
  end

  return extracted
end

local function renderConstants(extracted)
  local out = {}
  out[#out + 1] = "-- src/corrections/enum/constants.lua"
  out[#out + 1] = "--"
  out[#out + 1] = "-- GENERATED by `lua tools/port-corrections.lua`. Do not edit by hand."
  out[#out + 1] = "--"
  out[#out + 1] = "-- The constants correction files reference, extracted from Questie's own sources rather"
  out[#out + 1] = "-- than transcribed — the same discipline as the schema, for the same reason: a"
  out[#out + 1] = "-- hand-maintained copy of someone else's table drifts."
  out[#out + 1] = ""
  out[#out + 1] = "local _, LibQuestieDB = ..."
  out[#out + 1] = ""
  out[#out + 1] = "local constants = {}"
  out[#out + 1] = ""

  local names = {}
  for name in pairs(extracted) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    out[#out + 1] = "constants." .. name .. " = " .. serialize.value(extracted[name])
    out[#out + 1] = ""
  end

  out[#out + 1] = "if LibQuestieDB then"
  out[#out + 1] = "  LibQuestieDB.Enum = constants"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return constants"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

--------------------------------------------------------------------------------------------
-- Correction file copying
--------------------------------------------------------------------------------------------

--- Read the module name a correction file registers itself under, rather than recording it by
--- hand. Getting one wrong is silent — the file loads, nothing registers, and the corrections
--- simply do not appear.
local function moduleNameOf(path)
  local source = lib.readAll(path)
  local name = source:match('QuestieLoader:CreateModule%(%s*"([^"]+)"')
             or source:match("QuestieLoader:CreateModule%(%s*'([^']+)'")
             or source:match('QuestieLoader:ImportModule%(%s*"([^"]+)"')
  if not name then
    error("port: cannot find the module name in " .. path, 0)
  end
  return name
end

--- Which Questie correction files move here, and how each is classified.
---
--- `static` names the functions whose output is data truth — foldable during Generation.
--- `dynamic` names the ones that branch on runtime state (faction, class, race, season,
--- calendar, realm flag) and therefore go through the Correction Overlay.
---
--- Blacklists, ContentPhases and Holidays are deliberately absent: hiding an entity is
--- consumer policy, not a database fact. See DESIGN.md, the boundary rule.
local FILES = {
  -- Era
  { src = "classicQuestFixes.lua", dst = "Era/classicQuestFixes.lua", datatype = "Quest", expansions = { Classic = true },
    module = "QuestieQuestFixes", static = { "LoadMissingQuests", "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "classicNPCFixes.lua", dst = "Era/classicNPCFixes.lua", datatype = "Npc", expansions = { Classic = true },
    module = "QuestieNPCFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" }, parameterized = { "LoadDarkmoonFixes" } },
  { src = "classicItemFixes.lua", dst = "Era/classicItemFixes.lua", datatype = "Item", expansions = { Classic = true },
    module = "QuestieItemFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "classicObjectFixes.lua", dst = "Era/classicObjectFixes.lua", datatype = "Object", expansions = { Classic = true },
    module = "QuestieObjectFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "Automatic/classicQuestReputationFixes.lua", dst = "Era/classicQuestReputationFixes.lua",
    datatype = "Quest", expansions = { Classic = true }, module = "QuestieQuestReputationFixes",
    static = { "Load" }, generated = true },

  -- TBC
  { src = "tbcQuestFixes.lua", dst = "Tbc/tbcQuestFixes.lua", datatype = "Quest", minExpansion = 2,
    module = "QuestieTBCQuestFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "tbcNPCFixes.lua", dst = "Tbc/tbcNPCFixes.lua", datatype = "Npc", minExpansion = 2,
    module = "QuestieTBCNpcFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" }, parameterized = { "LoadDarkmoonFixes" } },
  { src = "tbcItemFixes.lua", dst = "Tbc/tbcItemFixes.lua", datatype = "Item", minExpansion = 2,
    module = "QuestieTBCItemFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "tbcObjectFixes.lua", dst = "Tbc/tbcObjectFixes.lua", datatype = "Object", minExpansion = 2,
    module = "QuestieTBCObjectFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- Wotlk
  { src = "wotlkQuestFixes.lua", dst = "Wotlk/wotlkQuestFixes.lua", datatype = "Quest", minExpansion = 3,
    module = "QuestieWotlkQuestFixes", static = { "Load" }, dynamic = { "LoadFactionFixes", "LoadTitanReforgedFixes" } },
  { src = "wotlkNPCFixes.lua", dst = "Wotlk/wotlkNPCFixes.lua", datatype = "Npc", minExpansion = 3,
    module = "QuestieWotlkNpcFixes", static = { "Load", "LoadAutomatics" },
    dynamic = { "LoadFactionFixes", "LoadTitanReforgedFixes" } },
  { src = "wotlkItemFixes.lua", dst = "Wotlk/wotlkItemFixes.lua", datatype = "Item", minExpansion = 3,
    module = "QuestieWotlkItemFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes", "LoadTitanReforgedFixes" } },
  { src = "wotlkObjectFixes.lua", dst = "Wotlk/wotlkObjectFixes.lua", datatype = "Object", minExpansion = 3,
    module = "QuestieWotlkObjectFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- Cata
  { src = "cataQuestFixes.lua", dst = "Cata/cataQuestFixes.lua", datatype = "Quest", minExpansion = 4,
    module = "QuestieCataQuestFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataNPCFixes.lua", dst = "Cata/cataNPCFixes.lua", datatype = "Npc", minExpansion = 4,
    module = "QuestieCataNpcFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataItemFixes.lua", dst = "Cata/cataItemFixes.lua", datatype = "Item", minExpansion = 4,
    module = "QuestieCataItemFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataObjectFixes.lua", dst = "Cata/cataObjectFixes.lua", datatype = "Object", minExpansion = 4,
    module = "QuestieCataObjectFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- MoP
  { src = "mopQuestFixes.lua", dst = "MoP/mopQuestFixes.lua", datatype = "Quest", minExpansion = 5,
    module = "QuestieMoPQuestFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes", "LoadContentPhaseFixes" } },
  { src = "mopNPCFixes.lua", dst = "MoP/mopNPCFixes.lua", datatype = "Npc", minExpansion = 5,
    module = "QuestieMoPNpcFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes", "LoadContentPhaseFixes" } },
  { src = "mopItemFixes.lua", dst = "MoP/mopItemFixes.lua", datatype = "Item", minExpansion = 5,
    module = "QuestieMoPItemFixes", static = { "Load" } },
  { src = "mopObjectFixes.lua", dst = "MoP/mopObjectFixes.lua", datatype = "Object", minExpansion = 5,
    module = "QuestieMoPObjectFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes", "LoadContentPhaseFixes" } },

  -- Season of Discovery: a Dynamic Correction set over the Era database, not a separate
  -- database. This is what lets Questie's parallel compiled SoD database be deleted.
  { src = "sodQuestFixes.lua", dst = "Sod/sodQuestFixes.lua", datatype = "Quest", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadQuests", "LoadFactionQuestFixes" } },
  { src = "sodNPCFixes.lua", dst = "Sod/sodNPCFixes.lua", datatype = "Npc", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadNPCs" } },
  { src = "sodItemFixes.lua", dst = "Sod/sodItemFixes.lua", datatype = "Item", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadItems" } },
  { src = "sodObjectFixes.lua", dst = "Sod/sodObjectFixes.lua", datatype = "Object", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadObjects" } },
  { src = "Automatic/sodBaseQuests.lua", dst = "Sod/sodBaseQuests.lua", datatype = "Quest", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadBaseQuests" }, generated = true },
  { src = "Automatic/sodBaseNPCs.lua", dst = "Sod/sodBaseNPCs.lua", datatype = "Npc", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadBaseNPCs" }, generated = true },
  { src = "Automatic/sodBaseItems.lua", dst = "Sod/sodBaseItems.lua", datatype = "Item", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadBaseItems" }, generated = true },
  { src = "Automatic/sodBaseObjects.lua", dst = "Sod/sodBaseObjects.lua", datatype = "Object", expansions = { Classic = true },
    module = "SeasonOfDiscovery", dynamic = { "LoadBaseObjects" }, generated = true },

  -- Applies to every flavor.
  { src = "Automatic/itemStartFixes.lua", dst = "Shared/itemStartFixes.lua", datatype = "Item",
    module = "QuestieItemStartFixes", static = { "LoadAutomaticQuestStarts" }, generated = true,
    options = { noOverwrites = true, noNewEntries = true } },
}

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local function copyCorrections()
  local copied, missing = 0, {}
  for _, spec in ipairs(FILES) do
    local src = QUESTIE .. "/Database/Corrections/" .. spec.src
    if lib.fileExists(src) then
      local dst = "src/corrections/" .. spec.dst
      lib.mkdirp(dst:match("^(.*)/[^/]+$"))
      lib.copyFile(src, dst)
      local derived = moduleNameOf(dst)
      if spec.module and spec.module ~= derived then
        print(("  note: %s registers as %s, not %s"):format(spec.dst, derived, spec.module))
      end
      spec.module = derived
      copied = copied + 1
    else
      missing[#missing + 1] = spec.src
    end
  end
  return copied, missing
end

local function renderManifest()
  local out = {}
  out[#out + 1] = "-- src/corrections/manifest.lua"
  out[#out + 1] = "--"
  out[#out + 1] = "-- GENERATED by `lua tools/port-corrections.lua`. Do not edit by hand."
  out[#out + 1] = "--"
  out[#out + 1] = "-- Which correction file provides which functions, and whether each is Static or"
  out[#out + 1] = "-- Dynamic. The classification is declared by the author, never inferred — folder names"
  out[#out + 1] = "-- are not a reliable signal, as `Sod/static/sodItemQuestStartFixes.lua` registering"
  out[#out + 1] = "-- dynamic in the prototype demonstrates."
  out[#out + 1] = ""
  out[#out + 1] = "local _, LibQuestieDB = ..."
  out[#out + 1] = ""
  out[#out + 1] = "local manifest = {"
  for _, spec in ipairs(FILES) do
    if lib.fileExists(QUESTIE .. "/Database/Corrections/" .. spec.src) then
      local parts = {
        "file = " .. serialize.quote(spec.dst),
        "module = " .. serialize.quote(spec.module),
        "datatype = " .. serialize.quote(spec.datatype),
      }
      if spec.static then parts[#parts + 1] = "static = " .. serialize.value(spec.static) end
      if spec.dynamic then parts[#parts + 1] = "dynamic = " .. serialize.value(spec.dynamic) end
      if spec.expansions then parts[#parts + 1] = "expansions = " .. serialize.value(spec.expansions) end
      if spec.minExpansion then parts[#parts + 1] = "minExpansionOrder = " .. spec.minExpansion end
      if spec.parameterized then parts[#parts + 1] = "parameterized = " .. serialize.value(spec.parameterized) end
      if spec.options then parts[#parts + 1] = "options = " .. serialize.value(spec.options) end
      if spec.generated then parts[#parts + 1] = "generated = true" end
      out[#out + 1] = "  { " .. table.concat(parts, ", ") .. " },"
    end
  end
  out[#out + 1] = "}"
  out[#out + 1] = ""
  out[#out + 1] = "if LibQuestieDB then"
  out[#out + 1] = "  LibQuestieDB.CorrectionManifest = manifest"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return manifest"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

if not lib.fileExists(QUESTIE .. "/Database/Corrections/classicQuestFixes.lua") then
  error("port: no Questie checkout at " .. QUESTIE, 0)
end

lib.mkdirp("src/corrections/enum")
local extracted = extractConstants()
lib.writeAll("src/corrections/enum/constants.lua", renderConstants(extracted))
local names = {}
for name in pairs(extracted) do names[#names + 1] = name end
table.sort(names)
print(("Extracted %d constant tables: %s"):format(#names, table.concat(names, ", ")))

local copied, missing = copyCorrections()
lib.writeAll("src/corrections/manifest.lua", renderManifest())
print(("Copied %d correction files, wrote src/corrections/manifest.lua"):format(copied))
if #missing > 0 then
  print("Missing in the Questie checkout: " .. table.concat(missing, ", "))
end
