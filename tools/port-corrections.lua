#!/usr/bin/env lua
-- tools/port-corrections.lua
--
-- Mechanical port of Questie's corrections into QuestieTDB.
--
-- Two jobs, both mechanical on purpose:
--
--   1. **Extract the constants** correction files reference — key enums, race and class
--      bitmasks, zone IDs, profession keys, icon types — by executing Questie's own sources
--      under the mocked environment and dumping what they defined. Same discipline as the
--      schema: derived, not transcribed, so it cannot quietly drift.
--
--   2. **Copy the correction files with declared ownership exclusions.** They are 10 MB of
--      hand-curated data, so `src/corrections/compat.lua` supplies the module surface they
--      expect and every non-excluded byte remains identical to Questie's. Exclusions remove
--      whole functions whose selection belongs to the consumer rather than this provider.
--
-- Usage: lua tools/port-corrections.lua [path-to-questie]

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")
local serialize = dofile("generator/serialize.lua")

local QUESTIE = (arg and arg[1]) or os.getenv("QUESTIE_PATH") or "../Questie"

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

--- Constants are extracted once **per expansion**, because upstream evaluates them under the
--- client's expansion flags: `raceKeys.ALL_ALLIANCE` is 77 on Era but 1101 on TBC/Wrath and
--- 2098253 on Cata (QuestieDB.lua:122-150), `npcFlags.REPAIR` is `IsClassic and 16384 or 4096`
--- (npcDB.lua:63-75), `classKeys.ALL_CLASSES` walks every expansion (QuestieDB.lua:178-191).
--- Extracting under `isClassic` alone baked Era masks into every flavor's artifacts — found by
--- the cross-implementation differential as 440 TBC divergences, growing per expansion.
---
--- `flags` mirrors how a real client of that expansion presents itself to upstream's
--- conditionals; `order` feeds `Expansions.Current`. Names match `config.flavors[].expansion`.
local EXPANSIONS = {
  { name = "Classic", order = 1, flags = { isClassic = true } },
  { name = "TBC",     order = 2, flags = { isTBC = true } },
  { name = "Wotlk",   order = 3, flags = { isWotlk = true } },
  { name = "Cata",    order = 4, flags = { isCata = true } },
  { name = "MoP",     order = 5, flags = { isMoP = true } },
}

local function extractConstantsFor(expansion)
  local extracted = {}

  for _, spec in ipairs(EXTRACTIONS) do
    loader.installEnvironment(expansion.flags)
    local Expansions = QuestieLoader:ImportModule("Expansions")
    Expansions.Classic, Expansions.Era, Expansions.Tbc = 1, 1, 2
    Expansions.Wotlk, Expansions.Cata, Expansions.MoP = 3, 4, 5
    Expansions.Current = expansion.order
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
  loader.installEnvironment(expansion.flags)
  local restoreZone = loader.installPermissiveGlobals()
  local zoneOk, zoneErr = pcall(loader.executeFile, QUESTIE .. "/Database/Zones/data/zoneIds.lua")
  restoreZone()
  if not zoneOk then error(zoneErr, 0) end
  local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
  if type(ZoneDB.zoneIDs) ~= "table" then
    error("port: Database/Zones/data/zoneIds.lua did not define ZoneDB.zoneIDs", 0)
  end
  extracted.zoneIDs = ZoneDB.zoneIDs

  -- The slices evaluate under the expansion globals installed above: `Questie.Is*`
  -- reaches them through the chunk environment's `__index = _G`.
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

---@param perExpansion table expansion name -> extracted constants
---@return string rendered
---@return table varyingNames sorted list of constant names that differ by expansion
local function renderConstants(perExpansion)
  local classic = perExpansion.Classic

  local names = {}
  for name in pairs(classic) do names[#names + 1] = name end
  table.sort(names)

  -- A constant varies when any expansion's serialization differs from Classic's. The
  -- serializer is deterministic (sorted keys), so string equality is table equality.
  -- Only invariant tables are safe without flavor context and therefore emitted flat;
  -- varying tables require explicit expansion selection through `byExpansion`.
  local varying, varyingSet = {}, {}
  for _, name in ipairs(names) do
    local classicForm = serialize.value(classic[name])
    for _, expansion in ipairs(EXPANSIONS) do
      if serialize.value(perExpansion[expansion.name][name]) ~= classicForm then
        varying[#varying + 1] = name
        varyingSet[name] = true
        break
      end
    end
  end

  local out = {}
  out[#out + 1] = "-- src/corrections/enum/constants.lua"
  out[#out + 1] = "--"
  out[#out + 1] = "-- GENERATED by `lua tools/port-corrections.lua`. Do not edit by hand."
  out[#out + 1] = "--"
  out[#out + 1] = "-- The constants correction files reference, extracted from Questie's own sources rather"
  out[#out + 1] = "-- than transcribed — the same discipline as the schema, for the same reason: a"
  out[#out + 1] = "-- hand-maintained copy of someone else's table drifts."
  out[#out + 1] = "--"
  out[#out + 1] = "-- Top-level tables are expansion-invariant and safe to use without flavor context."
  out[#out + 1] = "-- Tables whose values vary by expansion exist only under `constants.byExpansion`; callers"
  out[#out + 1] = "-- must select an explicit expansion rather than inheriting an ambiguous Classic baseline."
  out[#out + 1] = ""
  out[#out + 1] = "local _, LibQuestieDB = ..."
  out[#out + 1] = ""
  out[#out + 1] = "local constants = {}"
  out[#out + 1] = ""

  for _, name in ipairs(names) do
    if not varyingSet[name] then
      out[#out + 1] = "constants." .. name .. " = " .. serialize.value(classic[name])
      out[#out + 1] = ""
    end
  end

  if #varying > 0 then
    local byExpansion = {}
    for _, expansion in ipairs(EXPANSIONS) do
      local entry = {}
      for _, name in ipairs(varying) do
        entry[name] = perExpansion[expansion.name][name]
      end
      byExpansion[expansion.name] = entry
    end
    out[#out + 1] = "constants.byExpansion = " .. serialize.value(byExpansion)
    out[#out + 1] = ""
  end

  out[#out + 1] = "if LibQuestieDB then"
  out[#out + 1] = "  LibQuestieDB.Enum = constants"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return constants"
  out[#out + 1] = ""
  return table.concat(out, "\n"), varying
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
--- `dynamic` names functions that depend only on provider-owned data or generic character and
--- game facts QuestieTDB determines itself, and therefore go through the Correction Overlay.
---
--- Blacklists, ContentPhases, Holidays and Titan quest tags are deliberately absent. Hiding,
--- phase selection and semantic quest tags are consumer policy, not entity data. See
--- DESIGN.md, the boundary rule.
local FILES = {
  -- Era
  --
  -- The four Era fix files carry NO expansion gate. Upstream applies them unconditionally on
  -- every expansion and layers TBC/Wotlk/Cata/MoP fixes on top by expansion floor
  -- (QuestieCorrections:Initialize, Database/Corrections/QuestieCorrections.lua — only the
  -- reputation fixes sit behind `if Questie.IsClassic`, with the comment "This data is only
  -- correct for Era/SoX, for the other expansions we trust the base DB"). Classic-gating
  -- these four stripped every Era-inherited static correction out of the TBC+ artifacts —
  -- found by the cross-implementation differential, invisible to verify/equivalence because
  -- generator and source mode share this manifest.
  { src = "classicQuestFixes.lua", dst = "Era/classicQuestFixes.lua", datatype = "Quest",
    sourceExpansionOrder = 1, module = "QuestieQuestFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "classicNPCFixes.lua", dst = "Era/classicNPCFixes.lua", datatype = "Npc",
    sourceExpansionOrder = 1, module = "QuestieNPCFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" },
    -- Questie owns this selection because it depends on consumer-owned calendar state.
    ownershipExclusion = { module = "QuestieNPCFixes", functionName = "LoadDarkmoonFixes" } },
  { src = "classicItemFixes.lua", dst = "Era/classicItemFixes.lua", datatype = "Item",
    sourceExpansionOrder = 1, module = "QuestieItemFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "classicObjectFixes.lua", dst = "Era/classicObjectFixes.lua", datatype = "Object",
    sourceExpansionOrder = 1, module = "QuestieObjectFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  -- Era-only per upstream's explicit `if Questie.IsClassic` gate — see the citation above.
  { src = "Automatic/classicQuestReputationFixes.lua", dst = "Era/classicQuestReputationFixes.lua",
    datatype = "Quest", expansions = { Classic = true },
    module = "QuestieQuestReputationFixes", static = { "Load" }, generated = true },

  -- TBC
  { src = "tbcQuestFixes.lua", dst = "Tbc/tbcQuestFixes.lua", datatype = "Quest", minExpansion = 2,
    module = "QuestieTBCQuestFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" },
    -- Questie owns this selection because it depends on consumer-owned content phase state.
    ownershipExclusion = { module = "QuestieTBCQuestFixes", functionName = "LoadContentPhaseFixes" } },
  { src = "tbcNPCFixes.lua", dst = "Tbc/tbcNPCFixes.lua", datatype = "Npc", minExpansion = 2,
    module = "QuestieTBCNpcFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" },
    -- Questie owns this selection because it depends on consumer-owned calendar state.
    ownershipExclusion = { module = "QuestieTBCNpcFixes", functionName = "LoadDarkmoonFixes" } },
  { src = "tbcItemFixes.lua", dst = "Tbc/tbcItemFixes.lua", datatype = "Item", minExpansion = 2,
    module = "QuestieTBCItemFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "tbcObjectFixes.lua", dst = "Tbc/tbcObjectFixes.lua", datatype = "Object", minExpansion = 2,
    module = "QuestieTBCObjectFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- Wotlk
  { src = "wotlkQuestFixes.lua", dst = "Wotlk/wotlkQuestFixes.lua", datatype = "Quest", minExpansion = 3,
    module = "QuestieWotlkQuestFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" } },
  { src = "wotlkNPCFixes.lua", dst = "Wotlk/wotlkNPCFixes.lua", datatype = "Npc", minExpansion = 3,
    module = "QuestieWotlkNpcFixes", static = { "LoadAutomatics", "Load" },
    dynamic = { "LoadFactionFixes" } },
  { src = "wotlkItemFixes.lua", dst = "Wotlk/wotlkItemFixes.lua", datatype = "Item", minExpansion = 3,
    module = "QuestieWotlkItemFixes", static = { "Load" },
    dynamic = { "LoadFactionFixes" } },
  { src = "wotlkObjectFixes.lua", dst = "Wotlk/wotlkObjectFixes.lua", datatype = "Object", minExpansion = 3,
    module = "QuestieWotlkObjectFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- Titan Reforged
  --
  -- Questie's split compiler calls the `Load*` providers static because it builds a separate
  -- Titan cache. QuestieTDB has one Wrath artifact, so every Titan function is Dynamic over
  -- the Wrath base, exactly like SoD over Era. The Titan/ directory supplies one file-level
  -- Wrath-plus-season-109 gate, and the declared order preserves base rows before overrides.
  { src = "titanReforgedQuestFixes.lua", dst = "Titan/titanReforgedQuestFixes.lua",
    datatype = "Quest", expansions = { Wotlk = true }, module = "TitanReforgedQuestFixes",
    dynamic = { "LoadQuests", "LoadQuestOverrides" } },
  { src = "titanReforgedNPCFixes.lua", dst = "Titan/titanReforgedNPCFixes.lua",
    datatype = "Npc", expansions = { Wotlk = true }, module = "TitanReforgedNpcFixes",
    dynamic = { "LoadNPCs", "LoadNPCOverrides", "LoadFactionNPCOverrides" } },
  { src = "titanReforgedItemFixes.lua", dst = "Titan/titanReforgedItemFixes.lua",
    datatype = "Item", expansions = { Wotlk = true }, module = "TitanReforgedItemFixes",
    dynamic = { "LoadItems", "LoadItemOverrides" } },
  { src = "titanReforgedObjectFixes.lua", dst = "Titan/titanReforgedObjectFixes.lua",
    datatype = "Object", expansions = { Wotlk = true }, module = "TitanReforgedObjectFixes",
    dynamic = { "LoadObjects" } },

  -- Cata
  { src = "cataQuestFixes.lua", dst = "Cata/cataQuestFixes.lua", datatype = "Quest", minExpansion = 4,
    module = "QuestieCataQuestFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataNPCFixes.lua", dst = "Cata/cataNPCFixes.lua", datatype = "Npc", minExpansion = 4,
    module = "QuestieCataNpcFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataItemFixes.lua", dst = "Cata/cataItemFixes.lua", datatype = "Item", minExpansion = 4,
    module = "QuestieCataItemFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },
  { src = "cataObjectFixes.lua", dst = "Cata/cataObjectFixes.lua", datatype = "Object", minExpansion = 4,
    module = "QuestieCataObjectFixes",
    static = { "Load" }, dynamic = { "LoadFactionFixes" } },

  -- MoP
  { src = "mopQuestFixes.lua", dst = "MoP/mopQuestFixes.lua", datatype = "Quest", minExpansion = 5,
    module = "QuestieMoPQuestFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" },
    ownershipExclusion = { module = "MopQuestFixes", functionName = "LoadContentPhaseFixes" } },
  { src = "mopNPCFixes.lua", dst = "MoP/mopNPCFixes.lua", datatype = "Npc", minExpansion = 5,
    module = "QuestieMoPNpcFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" },
    ownershipExclusion = { module = "MopNpcFixes", functionName = "LoadContentPhaseFixes" } },
  { src = "mopItemFixes.lua", dst = "MoP/mopItemFixes.lua", datatype = "Item", minExpansion = 5,
    module = "QuestieMoPItemFixes", static = { "Load" } },
  { src = "mopObjectFixes.lua", dst = "MoP/mopObjectFixes.lua", datatype = "Object", minExpansion = 5,
    module = "QuestieMoPObjectFixes", static = { "Load" }, dynamic = { "LoadFactionFixes" },
    ownershipExclusion = { module = "MopObjectFixes", functionName = "LoadContentPhaseFixes" } },

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
-- Verbatim libraries
--------------------------------------------------------------------------------------------
--
-- Not corrections, but ported under the same rule and for the same reason: a Derived Pass runs
-- upstream's algorithm, so the algorithm is copied rather than transcribed, and CI diffs the
-- copy. Paths are relative to the Questie checkout root, not to Database/Corrections/.
--
-- `OptimizeWaypoints` itself is NOT here: it is a method on QuestieCorrections, the
-- orchestrator this project replaces, so src/derived/waypoints.lua transcribes it and the
-- reference differential is what guards it. See docs/adr/0004-derived-passes.md.

local LIBRARIES = {
  { src = "Modules/Libs/RamerDouglasPeucker.lua", dst = "src/derived/RamerDouglasPeucker.lua" },
}

local function correctionSourcePath(spec)
  return "Database/Corrections/" .. spec.src
end

---Remove one top-level method together with its immediately attached comment block.
---The exact shape is intentionally strict so upstream drift cannot broaden an ownership
---exclusion without an explicit port-tool change.
---@param source string
---@param exclusion table { module: string, functionName: string }
---@param relativeSource string
---@return string
local function removeOwnershipExclusion(source, exclusion, relativeSource)
  local lines = {}
  for line in (source .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" and source:sub(-1) == "\n" then lines[#lines] = nil end

  local headerPattern = "^function%s+" .. exclusion.module .. "%s*:%s*" ..
    exclusion.functionName .. "%s*%("
  local headerIndex
  for index, line in ipairs(lines) do
    if line:find(headerPattern) then
      if headerIndex then
        error(("port: %s defines excluded function %s more than once (lines %d and %d)")
          :format(relativeSource, exclusion.functionName, headerIndex, index), 0)
      end
      headerIndex = index
    end
  end
  if not headerIndex then
    error(("port: %s does not define excluded function %s exactly as expected")
      :format(relativeSource, exclusion.functionName), 0)
  end

  local docStart = headerIndex
  while docStart > 1 and lines[docStart - 1]:find("^%-%-") do
    docStart = docStart - 1
  end
  if docStart == headerIndex then
    error(("port: %s excluded function %s has no attached comment block")
      :format(relativeSource, exclusion.functionName), 0)
  end

  local endIndex
  for index = headerIndex + 1, #lines do
    if lines[index]:find("^end%s*$") then
      endIndex = index
      break
    end
    if lines[index]:find("^function%s") then
      error(("port: %s excluded function %s reaches another top-level function before end")
        :format(relativeSource, exclusion.functionName), 0)
    end
  end
  if not endIndex then
    error(("port: %s excluded function %s has no column-0 closing end")
      :format(relativeSource, exclusion.functionName), 0)
  end

  for index = endIndex, docStart, -1 do table.remove(lines, index) end
  while lines[#lines] == "" do lines[#lines] = nil end
  return table.concat(lines, "\n") .. (source:sub(-1) == "\n" and "\n" or "")
end

---Copy one declared Questie source with a useful error when the pin no longer provides it.
local function copyDeclaredSource(relativeSource, destination)
  local source = QUESTIE .. "/" .. relativeSource
  if not lib.fileExists(source) then
    error("port: declared Questie source is missing: " .. relativeSource, 0)
  end
  lib.mkdirp(destination:match("^(.*)/[^/]+$"))
  lib.copyFile(source, destination)
end

local function copyLibraries()
  local copied = 0
  for _, spec in ipairs(LIBRARIES) do
    copyDeclaredSource(spec.src, spec.dst)
    copied = copied + 1
  end
  return copied
end

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local function copyCorrections()
  local copied = 0
  for _, spec in ipairs(FILES) do
    local relativeSource = correctionSourcePath(spec)
    local sourcePath = QUESTIE .. "/" .. relativeSource
    if not lib.fileExists(sourcePath) then
      error("port: declared Questie source is missing: " .. relativeSource, 0)
    end

    local content = lib.readAll(sourcePath)
    if spec.ownershipExclusion then
      content = removeOwnershipExclusion(content, spec.ownershipExclusion, relativeSource)
    end

    local dst = "src/corrections/" .. spec.dst
    lib.mkdirp(dst:match("^(.*)/[^/]+$"))
    lib.writeAll(dst, content)
    local derived = moduleNameOf(dst)
    if spec.module and spec.module ~= derived then
      print(("  note: %s registers as %s, not %s"):format(spec.dst, derived, spec.module))
    end
    spec.module = derived
    copied = copied + 1
  end
  return copied
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
  out[#out + 1] = "-- dynamic in the prototype demonstrates. `minExpansionOrder` also identifies the source"
  out[#out + 1] = "-- expansion; only ungated Era entries need an explicit `sourceExpansionOrder`."
  out[#out + 1] = ""
  out[#out + 1] = "local _, LibQuestieDB = ..."
  out[#out + 1] = ""
  out[#out + 1] = "local manifest = {"
  for _, spec in ipairs(FILES) do
    local parts = {
      "file = " .. serialize.quote(spec.dst),
      "module = " .. serialize.quote(spec.module),
      "datatype = " .. serialize.quote(spec.datatype),
    }
    if spec.static then parts[#parts + 1] = "static = " .. serialize.value(spec.static) end
    if spec.dynamic then parts[#parts + 1] = "dynamic = " .. serialize.value(spec.dynamic) end
    if spec.expansions then parts[#parts + 1] = "expansions = " .. serialize.value(spec.expansions) end
    if spec.minExpansion then parts[#parts + 1] = "minExpansionOrder = " .. spec.minExpansion end
    if spec.sourceExpansionOrder then
      parts[#parts + 1] = "sourceExpansionOrder = " .. spec.sourceExpansionOrder
    end
    if spec.options then parts[#parts + 1] = "options = " .. serialize.value(spec.options) end
    if spec.generated then parts[#parts + 1] = "generated = true" end
    out[#out + 1] = "  { " .. table.concat(parts, ", ") .. " },"
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

lib.assertQuestiePin(QUESTIE)

lib.mkdirp("src/corrections/enum")
local perExpansion = {}
for _, expansion in ipairs(EXPANSIONS) do
  perExpansion[expansion.name] = extractConstantsFor(expansion)
end
local rendered, varying = renderConstants(perExpansion)
lib.writeAll("src/corrections/enum/constants.lua", rendered)
local names = {}
for name in pairs(perExpansion.Classic) do names[#names + 1] = name end
table.sort(names)
print(("Extracted %d constant tables across %d expansions: %s"):format(
  #names, #EXPANSIONS, table.concat(names, ", ")))
print(("Expansion-varying: %s"):format(#varying > 0 and table.concat(varying, ", ") or "none"))

local copied = copyCorrections()
lib.writeAll("src/corrections/manifest.lua", renderManifest())
print(("Copied %d correction files, wrote src/corrections/manifest.lua"):format(copied))

local libCopied = copyLibraries()
print(("Copied %d verbatim libraries"):format(libCopied))
