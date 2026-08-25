-- tools/differential/dump_b.lua
--
-- Dump the sibling `-pi` implementation's composed public reads for one flavor as canonical
-- TSV, without writing anything into that tree.
--
-- Stack: B's own generation loaders build the statically-corrected base exactly as B's
-- generate.lua does (raw entity source -> derived schema -> ApplyStatic under owner
-- QuestieTDB), then B's production Dynamic Correction runtime composes over it through
-- emulator/with_dynamic_view.lua with the persona matched to A's offline default —
-- Alliance / Human / Warrior / no active season.
--
-- Usage: lua tools/differential/dump_b.lua Vanilla <outFile> <B-project-root> [A-root]

local flavorName = assert(arg[1], "flavor argument required")
local outPath = assert(arg[2], "output path argument required")
local projectRoot = assert(arg[3], "B project root argument required")

local scriptPath = assert(debug.getinfo(1, "S").source):sub(2)
local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."
local canon = dofile(scriptDir .. "/canon.lua")

local config = dofile(projectRoot .. "/src/config.lua")
local loadEntitySource = dofile(projectRoot .. "/emulator/load_entity_source.lua")
local loadEntitySchema = dofile(projectRoot .. "/emulator/load_entity_schema.lua")
local loadStaticCorrections = dofile(projectRoot .. "/emulator/load_static_corrections.lua")
local entitySchema = dofile(projectRoot .. "/src/generation/entity_schema.lua")
local withDynamicView = dofile(projectRoot .. "/emulator/with_dynamic_view.lua")

local questieRoot = projectRoot .. "/data"
local flavor = config.selectFlavors(flavorName)[1]
assert(flavor, "unknown flavor " .. flavorName)

-- Statically-corrected base, replicating generate.lua's pre-emission pipeline.
local generatedEntities = {}
for entityTypeIndex, entityType in ipairs(config.entityTypes) do
  local sourcePath = config.rawSourcePath(questieRoot, flavor, entityType)
  local schemaPath = questieRoot .. "/" .. entityType.schemaFile
  local data, rawKeys = loadEntitySource(entityType, sourcePath)
  local schema = entitySchema.build(loadEntitySchema(entityType, rawKeys, schemaPath, flavor))
  generatedEntities[entityTypeIndex] = {
    config = entityType, data = data, rawKeys = rawKeys, schema = schema,
    emittedFieldCount = 0,
  }
end

local mutableEntities = {}
for _, generated in ipairs(generatedEntities) do
  mutableEntities[generated.config.name] = generated
end
local staticCorrections = loadStaticCorrections(flavor, generatedEntities)
staticCorrections:ApplyStatic("QuestieTDB", mutableEntities, {
  flavor = flavor,
  entityTypes = config.entityTypes,
  normalizeValue = entitySchema.normalizeValue,
})

local correctedState = {}
for _, generated in ipairs(generatedEntities) do
  correctedState[generated.config.name] = { data = generated.data, schema = generated.schema }
end

local out = assert(io.open(outPath, "w"))
local lines, fieldsRead = 0, 0

withDynamicView(flavor, correctedState, {
  faction = "Alliance",
  class = "WARRIOR",
  raceDisplayName = "Human",
  race = "Human",
  raceId = 1,
  -- seasonId omitted: no active season, matching A's offline default.
}, function(entities)
  for _, entityType in ipairs(config.entityTypes) do
    local entity = entities[entityType.name]
    local fields = correctedState[entityType.name].schema
    local ids = entity.GetAllIds()
    local sorted = {}
    for i = 1, #ids do sorted[i] = ids[i] end
    table.sort(sorted)
    for _, id in ipairs(sorted) do
      for fieldIndex, field in ipairs(fields) do
        fieldsRead = fieldsRead + 1
        local value = entity.Get(id, fieldIndex)
        if value ~= nil then
          out:write(entityType.name, "\t", id, "\t", field.name, "\t", canon(value), "\n")
          lines = lines + 1
        end
      end
    end
    io.write(("B %s %s: %d ids\n"):format(flavorName, entityType.name, #sorted))
  end
end)

out:close()
io.write(("B dump complete: %d non-nil lines, %d fields read\n"):format(lines, fieldsRead))
