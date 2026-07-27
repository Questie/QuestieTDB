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

local flavorLoader = {}

--- Load every entity type for one flavor.
---@param flavor table An entry from config.flavors
---@param typeFilter table? name -> true
---@param applyCorrections boolean? false to get raw data untouched
---@return table loaded entityTypeName -> { meta, entities, path }
---@return table stats
function flavorLoader.load(flavor, typeFilter, applyCorrections)
  local loaded = {}
  for _, entityType in ipairs(config.entityTypes) do
    if not typeFilter or typeFilter[entityType.name] then
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
  end

  return loaded, stats
end

return flavorLoader
