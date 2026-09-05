-- tools/differential/dump_a.lua
--
-- Dump this tree's composed public reads for one flavor as canonical TSV.
-- Source mode via the offline emulator, with Dynamic Corrections applied at addon load.
-- Defaults to Alliance / Human / Warrior / no active season; options select SoD or Horde.
-- Source/Baked equality is checked separately by equivalence.lua.
--
-- Usage (cwd must be the QuestieTDB root):
--   lua tools/differential/dump_a.lua Vanilla <outFile> [--compiler-coordinates] [--season=SoD] [--faction=Horde]
--     [--only=Quest.requiredRaces]

local flavorName = assert(arg[1], "flavor argument required")
local outPath = assert(arg[2], "output path argument required")
local season, faction, only, coordinateMode = nil, "Alliance", nil, nil
for i = 3, #arg do
  local value = arg[i]
  if value == "--compiler-coordinates" then coordinateMode = value
  elseif value:match("^%-%-season=") then season = value:sub(10)
  elseif value:match("^%-%-faction=") then faction = value:sub(11)
  elseif value:match("^%-%-only=") then only = value:sub(8)
  else error("Unknown option: " .. value, 0) end
end
assert(faction == "Alliance" or faction == "Horde", "unsupported faction")
assert(not only or only == "Quest.requiredRaces", "--only supports Quest.requiredRaces")
assert(not season or season == "SoD" or season == "TitanReforged", "unsupported season")
assert(season ~= "SoD" or flavorName == "Vanilla", "SoD requires Vanilla")
assert(season ~= "TitanReforged" or flavorName == "Wrath", "TitanReforged requires Wrath")

local config = dofile("src/config.lua")
local emulator = dofile("emulator/metadata.lua")
local client = dofile("emulator/client.lua")
local canon = dofile("tools/differential/canon.lua")
-- Default/Golden dumps stay raw. Only the explicit compiler view adapts base coordinates;
-- Dynamic Correction overlays remain raw in both modes.
local adaptDumpValue = dofile("tools/differential/dump_value.lua").forMode(coordinateMode)

local flavor
for _, f in ipairs(config.flavors) do
  if f.name == flavorName then flavor = f end
end
assert(flavor, "unknown flavor " .. flavorName)

client.reset()
client.install({ expansion = flavor.expansion, season = season, faction = faction,
  raceName = faction == "Horde" and "Orc" or "Human",
  raceFile = faction == "Horde" and "Orc" or "Human",
  raceId = faction == "Horde" and 2 or 1, level = season == "SoD" and 25 or 60 })
local Lib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
assert(Lib.readMode == "source", "expected source mode")
assert(Lib.read.source.expansion == flavor.expansion, "source mode selected wrong expansion")

-- A focused dump writes nil explicitly, so absent fields cannot hide an existing quest.
if only then
  local out = assert(io.open(outPath, "w"))
  local ids = Lib.Quest.GetAllIds()
  table.sort(ids)
  for _, id in ipairs(ids) do
    local value = Lib.Quest.Get(id, Lib.Meta.Quest.keys.requiredRaces)
    out:write("Quest\t", id, "\trequiredRaces\t", value == nil and "nil" or canon(value), "\n")
  end
  out:close()
  io.write(("A %s %s: %d quests\n"):format(flavorName, only, #ids))
  return
end

local out = assert(io.open(outPath, "w"))
local lines, fields = 0, 0

for _, entityType in ipairs(config.entityTypes) do
  local entity = Lib[entityType.name]
  local meta = Lib.Meta[entityType.name]
  local ids = entity.GetAllIds()
  local sorted = {}
  for i = 1, #ids do sorted[i] = ids[i] end
  table.sort(sorted)
  for _, id in ipairs(sorted) do
    for fieldIndex = 1, meta.fieldCount do
      fields = fields + 1
      local value = entity.Get(id, fieldIndex)
      if value ~= nil then
        value = adaptDumpValue(meta, fieldIndex, value, entity.overlay[id])
        out:write(entityType.name, "\t", id, "\t", meta.names[fieldIndex], "\t",
          canon(value), "\n")
        lines = lines + 1
      end
    end
  end
  io.write(("A %s %s: %d ids\n"):format(flavorName, entityType.name, #sorted))
end

out:close()
io.write(("A dump complete: %d non-nil lines, %d fields read\n"):format(lines, fields))
