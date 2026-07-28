-- validators/zones.lua
--
-- Area-to-UiMap resolution over the support data QuestieTDB owns.
--
-- Four of the fifteen invariant checks ask "does this spawn's area ID resolve to a map?", and
-- in Questie that question is answered by `ZoneDB:GetUiMapIdByAreaId` — a module that stays
-- with the consumer. Re-deriving the lookup here is what lets validation run with **no consumer
-- checkout required**, which is the whole point of moving the job.
--
-- Only the lookup is reimplemented, not the module: `zoneDB.lua` also does dungeon location
-- resolution, parent-zone walking and map-change handling, none of which a validator needs.

local runtime = dofile("generator/runtime.lua")
local client = dofile("emulator/client.lua")

local zones = {}

--- The support-data files store their big tables as Lua long strings that the consuming module
--- `loadstring`s. Doing the same here keeps the data files byte-identical to Questie's.
local function materialize(value)
  if type(value) == "table" then return value end
  if type(value) ~= "string" then return {} end
  local chunk = loadstring(value)
  if not chunk then return {} end
  return chunk()
end

--- Load one flavor's support data and return `getUiMapIdByAreaId(areaId) -> uiMapId | nil`.
---
--- Override first, then the generated table — the order `ZoneDB` uses, and the reason the
--- hand-authored override table exists at all.
function zones.BuildAreaLookup(flavor)
  local config = dofile("src/config.lua")
  local LibQuestieDB = { config = config, flavor = flavor }

  runtime.execute("src/corrections/enum/constants.lua", "QuestieTDB", LibQuestieDB)
  runtime.execute("src/support/data.lua", "QuestieTDB", LibQuestieDB)

  -- `dungeons.lua` reads `UnitFactionGroup` at load time to pick faction-specific entry
  -- coordinates, so the client stubs have to be in place even for a pure data load.
  client.install({ expansion = flavor and flavor.expansion or "Classic" })

  local support = LibQuestieDB.Support
  support.Install(flavor)
  for _, file in ipairs(config.supportFiles(flavor)) do
    if file:match("^support/Zones/") then
      runtime.execute(file, "QuestieTDB", LibQuestieDB)
    end
  end
  support.Remove()

  local ZoneDB = support.Get("ZoneDB") or { private = {} }
  local override = materialize(ZoneDB.private.areaIdToUiMapIdOverride)
  local generated = materialize(ZoneDB.private.areaIdToUiMapId)

  zones.lastCounts = { override = 0, generated = 0 }
  for _ in pairs(override) do zones.lastCounts.override = zones.lastCounts.override + 1 end
  for _ in pairs(generated) do zones.lastCounts.generated = zones.lastCounts.generated + 1 end

  return function(areaId)
    local uiMapId = override[areaId]
    if uiMapId ~= nil then return uiMapId end
    return generated[areaId]
  end
end

return zones
