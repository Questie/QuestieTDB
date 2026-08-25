-- src/derived/waypoints.lua
--
-- Derived Pass: waypoint simplification, reproducing `QuestieCorrections:PreCompile` and
-- `QuestieCorrections:OptimizeWaypoints` (Questie/Database/Corrections/QuestieCorrections.lua).
--
-- Upstream runs this from `QuestieInit.lua` only, never from `cli/validate-*.lua`, so it is
-- invisible to Questie's own CI as well as to a naive differential. It is not a size
-- optimization: it changes the waypoints consumers draw, on 454 of the 480 Vanilla NPCs that
-- have them.
--
-- Two stages, in this order:
--
--   1. Ramer-Douglas-Peucker at tolerance 0.1, highest quality. Removes points.
--   2. Subdivision: any segment longer than `1.5 * (ZONE_SCALES[zone] or 1)` is replaced by
--      `ceil(dist/minDist)` interpolated points. ADDS points, because a waypoint line's
--      clickable area is a square, so long lines have to be broken up.
--
-- It also normalizes shape: a bare `{{x,y}, ...}` zone entry becomes `{{{x,y}, ...}}`.
--
-- ## Why this is a transcription rather than a byte-copy
--
-- `RamerDouglasPeucker.lua` IS byte-copied (src/derived/RamerDouglasPeucker.lua, diffed by
-- tools/port-corrections.lua). `OptimizeWaypoints` cannot be: it is a method on
-- `QuestieCorrections`, the orchestrator QuestieTDB deliberately replaced, and copying that
-- file would drag in the correction-loading this project owns. So this is hand-carried code,
-- and the guard against upstream drift is the reference differential — if upstream changes the
-- algorithm, `Npc.waypoints` leaves zero and compiler_diff reports it. That is the only gate
-- watching this file; see docs/questie-handover.md.
--
-- ## Ordering
--
-- Runs on corrected raw coordinates, which production preserves through storage and reads.
-- Upstream simplified before compilation; the migration-only compiler adapter applies its
-- legacy grid after this pass as well, so the differential compares the same ordering.

local _, LibQuestieDB = ...

local pairs, type = pairs, type
local abs, sqrt, ceil = math.abs, math.sqrt, math.ceil

local waypoints = {}

--- Upstream's value, with its own comment: "todo: make this a config value maybe?"
local WAYPOINT_MIN_DISTANCE = 1.5

--- Capital cities are drawn at half scale, so their waypoints subdivide twice as finely.
--- Resolved from the shipped zone support data rather than hardcoded, so the constants stay
--- derived from one source the way the schema and the correction files do.
local function zoneScales(support)
  local zoneDB = support and support("ZoneDB")
  local zoneIDs = zoneDB and zoneDB.zoneIDs
  if not zoneIDs then
    error("waypoints pass: ZoneDB.zoneIDs unavailable - support data must load before " ..
          "derived passes run", 0)
  end
  return {
    [zoneIDs.STORMWIND_CITY] = 0.5,
    [zoneIDs.IRONFORGE] = 0.5,
    [zoneIDs.TELDRASSIL] = 0.5,
    [zoneIDs.ORGRIMMAR] = 0.5,
    [zoneIDs.THUNDER_BLUFF] = 0.5,
    [zoneIDs.UNDERCITY] = 0.5,
  }
end

local function euclid(x, y, i, e)
  local xd = abs(x - i)
  local yd = abs(y - e)
  return sqrt(xd * xd + yd * yd)
end

--- Transcribed from QuestieCorrections:OptimizeWaypoints. Iteration uses `pairs` exactly as
--- upstream does; the determinism gate (regenerate, compare SHA) is what proves that is safe
--- for an artifact rather than an in-memory table.
---@param waypointData table zoneId -> waypoint list(s)
---@param rdp function The byte-copied RamerDouglasPeucker
---@param scales table zoneId -> scale
function waypoints.Optimize(waypointData, rdp, scales)
  local newWaypointZones = {}
  for zone, waypointList in pairs(waypointData) do
    local newWaypointList = {}
    if waypointList[1] and type(waypointList[1][1]) == "number" then
      -- corrections support both {{x,y}, ...} and {{{x,y}, ...}, {{x,y}, ...}, ...}
      waypointList = { waypointList }
    end
    for _, wps in pairs(waypointList) do
      local minDist = WAYPOINT_MIN_DISTANCE * (scales[zone] or 1)
      local newWaypoints = rdp(wps, 0.1, true)

      wps = newWaypoints
      newWaypoints = {}

      local lastWay
      for _, way in pairs(wps) do
        if lastWay then
          local dist = euclid(way[1], way[2], lastWay[1], lastWay[2])
          if dist > minDist then
            local divs = ceil(dist / minDist)
            for i = 1, divs do
              local mul0 = i / divs
              local mul1 = 1 - mul0
              newWaypoints[#newWaypoints + 1] = {
                way[1] * mul0 + lastWay[1] * mul1,
                way[2] * mul0 + lastWay[2] * mul1,
              }
            end
          else
            newWaypoints[#newWaypoints + 1] = way
          end
        else
          newWaypoints[#newWaypoints + 1] = way
        end
        lastWay = way
      end
      newWaypointList[#newWaypointList + 1] = newWaypoints
    end
    newWaypointZones[zone] = newWaypointList
  end
  return newWaypointZones
end

--- Build the pass spec for one entity type. Upstream runs the same loop over npcData and
--- objectData; objects only carry waypoints from Cata onward, so it is a no-op before that.
function waypoints.Spec(entityType, order)
  return {
    name = "waypointSimplification:" .. entityType,
    writes = entityType,
    reads = { entityType },
    order = order,
    run = function(ctx)
      -- A run may be restricted to a subset of entity types (`generate.lua --types=Quest`),
      -- so an absent table is ordinary rather than an error.
      local entities = ctx.entities(entityType)
      if not entities then return end
      local meta = ctx.meta(entityType)
      local index = meta and meta.keys and meta.keys.waypoints
      if not index then return end

      local rdp = LibQuestieDB.RamerDouglasPeucker
      if not rdp then error("waypoints pass: RamerDouglasPeucker not loaded", 0) end
      local scales = zoneScales(ctx.support)

      for _, row in pairs(entities) do
        local value = row[index]
        if type(value) == "table" then
          row[index] = waypoints.Optimize(value, rdp, scales)
        end
      end
    end,
  }
end

if LibQuestieDB then
  LibQuestieDB.DerivedWaypoints = waypoints
end

return waypoints
