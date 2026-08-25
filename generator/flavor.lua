-- generator/flavor.lua
--
-- Loads one flavor's raw entity data and folds in Static Corrections.
--
-- Shared by generate.lua and verify.lua on purpose: the verifier has to compare against the
-- same corrected data the generator wrote, or it would be checking the storage round-trip
-- against the wrong expectation and would fail the moment a correction lands.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")
local schema = dofile("generator/schema.lua")
local corrections = dofile("generator/corrections.lua")
local derived = dofile("generator/derived.lua")

local flavorLoader = {}

---Loads selected output types and any inputs needed to derive them for one flavor.
---@param flavor table An entry from config.flavors
---@param typeFilter table? name -> true
---@param applyCorrections boolean? false to get raw data untouched
---@return table loaded Selected output entityTypeName -> { meta, entities, path }
---@return table stats
function flavorLoader.load(flavor, typeFilter, applyCorrections)
  -- Derived inputs belong to the working set, not the output selection. Raw callers do not
  -- run passes, so their filter stays untouched and they pay no dependency-loading cost.
  local loadFilter = typeFilter
  if applyCorrections ~= false then
    loadFilter = derived.expandReadDependencies(typeFilter, flavor)
  end

  local loaded = {}
  for _, entityType in ipairs(config.entityTypes) do
    if not loadFilter or loadFilter[entityType.name] then
      local path = config.dataPath(flavor, entityType)
      local entities, keys = loader.loadEntityData(path, entityType)
      local meta = schema.loadMaterialized(entityType)
      schema.checkKeys(meta, keys, path)
      schema.assertNoDataBeyondKeys(meta, entities, keys, path)
      loaded[entityType.name] = { meta = meta, entities = entities, path = path }
    end
  end

  local stats = { applied = 0 }
  if applyCorrections ~= false then
    stats.applied, stats.corrections = corrections.applyStatic(loaded, flavor)
    -- Derived Passes run after corrections and before anything encodes or normalizes, which
    -- is the order Questie uses and the only order quantization survives (ADR 0004 D3).
    stats.derived = derived.run(loaded, flavor)
  end

  -- Dependency-only tables have done their job. Returning them would make generate.lua emit
  -- entity types the caller did not request, changing the meaning of `--types`.
  if typeFilter then
    for typeName in pairs(loaded) do
      if not typeFilter[typeName] then loaded[typeName] = nil end
    end
  end

  return loaded, stats
end

return flavorLoader
