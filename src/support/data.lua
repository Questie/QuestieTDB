-- src/support/data.lua
--
-- Support data: game reference data consumed as whole tables rather than through the TOC
-- metadata store — zone mappings, quest XP, drop tables, faction templates.
--
-- It stays plain Lua rather than becoming metadata because callers want the whole table, not
-- lazy per-field access. Lazy decoding buys nothing when the first read materialises
-- everything anyway.
--
-- **Only the data moves.** The modules that wrap it — `zoneDB.lua`, `QuestieXP.lua`,
-- `dropDB.lua` — are `QuestieLoader` modules with runtime behaviour and stay with the
-- consumer. They read what this file publishes.
--
-- Baked TOCs list only applicable files. Source scope markers switch admission before
-- variant files load; rejected modules never enter the public module table.

local _, LibQuestieDB = ...

local support = {}

--- moduleName -> the table that module's data files assigned into.
--- e.g. `Support.Get("ZoneDB").private.areaIdToUiMapId`, `Support.Get("QuestXP").db`
support.modules = {}

local saved
local admitted = true
local discarded = {}

local EXPANSION_ORDER = { Classic = 1, TBC = 2, Wotlk = 3, Cata = 4, MoP = 5 }

--- Install a `QuestieLoader` shim that routes support-data assignments here instead of into
--- the consumer's modules. Scoped exactly like the entity-data and correction shims.
---
--- `dungeons.lua` is the one support file that is data *and* logic: it branches on
--- `Expansions.Current` to fix up three dungeon entries per expansion. The module is therefore
--- seeded rather than left empty, or those branches compare against nil.
---@param flavor table? An entry from config.flavors
function support.Install(flavor)
  saved = rawget(_G, "QuestieLoader")
  support.modules = {}
  admitted, discarded = true, {}

  ---@param name string
  ---@return table module
  local function moduleFor(name)
    local modules = admitted and support.modules or discarded
    local module = modules[name]
    if not module then
      module = { private = {} }
      modules[name] = module
    end
    return module
  end

  -- `itemDropCorrections.lua` reads `DropDB.correctionKeys` — negative sentinels that mark a
  -- correction's provenance (Wowhead, private server, manual). They live in `dropDB.lua`, the
  -- logic module staying with the consumer, so they are extracted alongside the entity
  -- constants and seeded here.
  local constants = LibQuestieDB.Enum
  if constants and constants.dropCorrectionKeys then
    moduleFor("DropDB").correctionKeys = constants.dropCorrectionKeys
  end

  local expansions = moduleFor("Expansions")
  expansions.Era, expansions.Classic, expansions.Tbc = 1, 1, 2
  expansions.Wotlk, expansions.Cata, expansions.MoP = 3, 4, 5
  expansions.Current = (flavor and EXPANSION_ORDER[flavor.expansion]) or 1

  _G.QuestieLoader = {
    ImportModule = function(_, name) return moduleFor(name) end,
    CreateModule = function(_, name) return moduleFor(name) end,
  }
end

---Source markers admit only their applicable variant assignments. Keep rejected data
---out of GetAll as well as Get; switching scope releases the previous discarded payloads.
---@param applies boolean
---@return nil
function support.SelectScope(applies)
  admitted, discarded = applies, {}
end

function support.Remove()
  _G.QuestieLoader = saved
  saved = nil
  admitted, discarded = true, {}
end

--- Whole-table access, which is the entire point of keeping this out of metadata.
---@param moduleName string "ZoneDB" | "QuestXP" | "DropDB" | "QuestieDB" | ...
function support.Get(moduleName)
  return support.modules[moduleName]
end

--- Every module the loaded support files populated, for a consumer that wants to enumerate.
function support.GetAll()
  return support.modules
end

LibQuestieDB.Support = support

return support
