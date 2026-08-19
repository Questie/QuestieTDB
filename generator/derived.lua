-- generator/derived.lua
--
-- Runs Derived Passes offline, over the same tables Generation is about to encode.
--
-- Mirrors generator/corrections.lua: the passes themselves live in src/derived/ and are shared
-- with Source mode, so this file only supplies the context they need — entity tables, schema,
-- flavor, and the sliver of support data a pass reads.

local corrections = dofile("generator/corrections.lua")
local runtime = dofile("generator/runtime.lua")
local lib = dofile("generator/lib.lua")

local derived = {}

--- Support files a pass needs, enumerated rather than discovered — the same rule the rest of
--- the generator follows. `zoneIds.lua` backs the waypoint pass's ZONE_SCALES, which is read
--- from the shipped data rather than hardcoded so the constants cannot drift from Questie's.
local SUPPORT_FILES = {
  "support/Zones/zoneIds.lua",
}

local supportModules

--- Load support data under a scoped `QuestieLoader` mock and return a `name -> module`
--- accessor with the same shape `LibQuestieDB.Support.Get` has at runtime.
local function supportProvider()
  if not supportModules then
    supportModules = {}
    local previous = rawget(_G, "QuestieLoader")
    local function moduleFor(_, name)
      supportModules[name] = supportModules[name] or {}
      return supportModules[name]
    end
    _G.QuestieLoader = { ImportModule = moduleFor, CreateModule = moduleFor }
    for _, path in ipairs(SUPPORT_FILES) do
      if lib.fileExists(path) then runtime.execute(path, "QuestieTDB", {}) end
    end
    _G.QuestieLoader = previous
  end
  return function(name) return supportModules[name] end
end

--- Run every Derived Pass over one flavor's loaded tables.
---
--- Called from generator/flavor.lua after Static Corrections, which puts it in the pipeline
--- for generate.lua, verify.lua and reconstruct.lua at once — they all route through
--- flavorLoader.load, so they cannot disagree about what the stored bytes should be.
---@param loaded table entityTypeName -> { meta, entities, path }
---@param flavor table An entry from config.flavors
---@return number ran How many passes executed
function derived.run(loaded, flavor)
  local LibQuestieDB = corrections.prepare(flavor).lib
  local registry = LibQuestieDB and LibQuestieDB.Derived
  if not registry then return 0 end

  local support = supportProvider()

  return registry.Run(nil, {
    flavor = flavor,
    support = support,
    entities = function(name)
      local entry = loaded[name]
      return entry and entry.entities or nil
    end,
    meta = function(name)
      local entry = loaded[name]
      return entry and entry.meta or nil
    end,
  })
end

return derived
