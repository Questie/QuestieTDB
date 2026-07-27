-- src/read/source.lua
--
-- Source mode: entity reads resolve from raw entity data, with Static Corrections applied
-- live, because no generated TOC metadata store is present.
--
-- A fresh clone junctioned into `AddOns` is a working development environment with no
-- download and no Lua toolchain. Generating or bootstrapping a suffixed TOC switches the same
-- folder to Baked mode with no code change, because the client searches for flavour-suffixed
-- TOCs first and falls back to the base one only if none are found.
--
-- This file and src/read/baked.lua are the only two places the modes diverge. Both provide
-- exactly `readField(id, fieldIndex)` and `getAllIds()`.
--
-- ## Why this file loads before the data
--
-- The base TOC has to serve every client, so it lists all five expansions' data files — 78 MB
-- of Lua. Loading all of it would be absurd. Instead this file installs a `QuestieLoader`
-- shim ahead of them: each expansion's block is preceded by a marker file naming it, and the
-- shim discards a payload assignment whose expansion is not the running client's. The
-- discarded chunk's string constant becomes collectable as soon as that file returns, so peak
-- cost is one file rather than twenty.

local _, LibQuestieDB = ...

local config = LibQuestieDB.config
local normalize = LibQuestieDB.Meta.normalize

local source = {}

--------------------------------------------------------------------------------------------
-- Flavor detection
--------------------------------------------------------------------------------------------

-- Blizzard's project IDs, the same mapping Questie's Expansions module uses. Defaulting to
-- Classic Era matches Questie's behaviour on an unrecognised client.
local PROJECT_TO_EXPANSION = {
  [2] = "Classic",  -- WOW_PROJECT_CLASSIC
  [5] = "TBC",      -- WOW_PROJECT_BURNING_CRUSADE_CLASSIC
  [11] = "Wotlk",   -- WOW_PROJECT_WRATH_CLASSIC
  [14] = "Cata",    -- WOW_PROJECT_CATACLYSM_CLASSIC
  [19] = "MoP",     -- WOW_PROJECT_MISTS_CLASSIC
}

--- Which expansion's raw data this client should keep.
function source.DetectExpansion()
  local override = LibQuestieDB.__forceExpansion
  if override then return override end
  return PROJECT_TO_EXPANSION[rawget(_G, "WOW_PROJECT_ID") or 2] or "Classic"
end

source.expansion = source.DetectExpansion()

for _, flavor in ipairs(config.flavors) do
  if flavor.expansion == source.expansion then source.flavor = flavor end
end

--------------------------------------------------------------------------------------------
-- Payload capture
--------------------------------------------------------------------------------------------

--- entityTypeName -> the `[[return {...}]]` payload string for the running client
source.payloads = {}

--- The data files assign both their key enum and their payload. Only the payload for the
--- running client's expansion is retained; everything else is dropped on assignment.
local capture = setmetatable({}, {
  __newindex = function(tbl, key, value)
    for _, entityType in ipairs(config.entityTypes) do
      if key == entityType.dataField then
        if LibQuestieDB.__loadingExpansion == source.expansion then
          source.payloads[entityType.name] = value
        end
        return
      end
    end
    -- Key enums and anything else a data file assigns are harmless and small; keep them so a
    -- file that reads back what it wrote still works.
    rawset(tbl, key, value)
  end,
})

--- Install the shim, remembering whatever was there so it can be handed back. QuestieTDB
--- loads before its consumer, so squatting on `QuestieLoader` for the duration of the data
--- block is safe as long as it is given up afterwards.
function source.InstallLoaderShim()
  source.previousQuestieLoader = rawget(_G, "QuestieLoader")
  local modules = { QuestieDB = capture }
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
end

--- Hand `QuestieLoader` back. Called by the marker file that closes the data block.
function source.RemoveLoaderShim()
  _G.QuestieLoader = source.previousQuestieLoader
  source.previousQuestieLoader = nil
end

source.InstallLoaderShim()

--------------------------------------------------------------------------------------------
-- Backend
--------------------------------------------------------------------------------------------

--- entityTypeName -> decoded id -> field array. Populated on first read.
source.entities = {}

--- Decode one entity type's payload and fold in Static Corrections.
---
--- Generation applies Static Corrections through this same path, which is what makes "what I
--- see in dev is what ships" a property of shared code rather than of a test — and why
--- *deleting* a correction is observable here, which an overlay-based dev addon could never
--- manage.
local function materialize(entityTypeName)
  local existing = source.entities[entityTypeName]
  if existing then return existing end

  local payload = source.payloads[entityTypeName]
  local entities
  if payload == nil then
    entities = {}
  elseif type(payload) == "table" then
    entities = payload
  else
    local chunk = loadstring(payload, "QuestieTDB:" .. entityTypeName .. "Data")
    entities = chunk and chunk() or {}
  end

  source.entities[entityTypeName] = entities
  source.payloads[entityTypeName] = nil -- release the string

  local corrections = LibQuestieDB.Corrections
  if corrections and corrections.ApplyStaticToEntities then
    corrections.ApplyStaticToEntities(entityTypeName, entities, source.flavor)
  end

  -- Base data is frozen after load, so neither a Correction nor a consumer can corrupt it.
  if LibQuestieDB.shared and LibQuestieDB.shared.Freeze then
    LibQuestieDB.shared.Freeze(entities)
  end

  return entities
end

source.Materialize = materialize

--- Build the Source-mode backend for one entity type.
function source.CreateBackend(meta)
  local backend = { mode = "source" }
  local idList, idMap

  function backend.readField(id, fieldIndex)
    local row = materialize(meta.entity)[id]
    if row == nil then return nil end
    -- Normalization runs here rather than in shared.lua so that both modes reach the same
    -- value by construction: Generation encodes through the same function, so an empty table
    -- or a {0,0} pair is nil in exactly the same places.
    return normalize.field(meta, fieldIndex, row[fieldIndex])
  end

  function backend.getAllIds()
    if not idList then
      local entities = materialize(meta.entity)
      idList, idMap = {}, {}
      for id in pairs(entities) do
        if type(id) == "number" then
          idList[#idList + 1] = id
          idMap[id] = true
        end
      end
      table.sort(idList)
    end
    return idList, idMap
  end

  return backend
end

LibQuestieDB.read = LibQuestieDB.read or {}
LibQuestieDB.read.source = source
LibQuestieDB.mode = "source"

return source
