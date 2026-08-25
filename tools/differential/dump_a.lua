-- tools/differential/dump_a.lua
--
-- Dump this tree's composed public reads for one flavor as canonical TSV.
-- Stack: Source mode via the offline emulator (proven byte-equivalent to Baked by
-- equivalence.lua), default persona — Alliance / Human / Warrior / no active season — with
-- this tree's Dynamic Corrections applied exactly as they are at addon load.
--
-- Usage (cwd must be the QuestieTDB root): lua tools/differential/dump_a.lua Vanilla <outFile>

local flavorName = assert(arg[1], "flavor argument required")
local outPath = assert(arg[2], "output path argument required")

local config = dofile("src/config.lua")
local emulator = dofile("emulator/metadata.lua")
local client = dofile("emulator/client.lua")
local canon = dofile("tools/differential/canon.lua")

local flavor
for _, f in ipairs(config.flavors) do
  if f.name == flavorName then flavor = f end
end
assert(flavor, "unknown flavor " .. flavorName)

client.reset()
client.install({ expansion = flavor.expansion })
local Lib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
assert(Lib.readMode == "source", "expected source mode")
assert(Lib.read.source.expansion == flavor.expansion, "source mode selected wrong expansion")

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
