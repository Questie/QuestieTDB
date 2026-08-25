-- tools/differential/compiler_coordinates.lua
--
-- Adapts QuestieTDB's raw coordinates to the values returned by Questie's retired binary
-- compiler. This belongs to the migration differential, never Generation or runtime reads:
-- the TOC store preserves source precision, while this oracle can only compare at its legacy
-- 12-bit precision.
--
-- Quantization is not idempotent. Apply this adapter exactly once to QuestieTDB's raw side and
-- never to the already-compiled Questie side. Dynamic Correction values bypassed compilation
-- in Questie and therefore bypass this adapter too.

local compilerCoordinates = {}

local type = type
local floor = math.floor

---Reproduce one coordinate tuple as Questie's compiler would read it.
---@param row any Coordinate tuple or malformed value.
---@param keepPhase boolean Whether a nonzero spawn phase survives.
---@return any adapted Fresh tuple for valid coordinates; malformed values pass through.
local function adaptCoordinateRow(row, keepPhase)
  if type(row) ~= "table" or type(row[1]) ~= "number" or type(row[2]) ~= "number" then
    return row
  end

  local qx, qy
  if row[1] == -1 and row[2] == -1 then
    qx, qy = 0, 0
  else
    qx, qy = floor(row[1] * 40.90), floor(row[2] * 40.90)
  end

  if qx == 0 and qy == 0 then return { -1, -1 } end
  if keepPhase and (row[3] or 0) ~= 0 then
    return { qx / 40.90, qy / 40.90, row[3] }
  end
  return { qx / 40.90, qy / 40.90 }
end

---Adapt `spawnlist`: zoneId -> { {x, y, phase?}, ... }.
---@param value any
---@return any adapted
local function adaptSpawnlist(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for zoneId, rows in pairs(value) do
    if type(rows) == "table" then
      local outRows = {}
      for i, row in pairs(rows) do
        outRows[i] = adaptCoordinateRow(row, true)
      end
      out[zoneId] = outRows
    else
      out[zoneId] = rows
    end
  end
  return out
end

---Adapt `waypointlist`, whose paths add one nesting level over spawns.
---@param value any
---@return any adapted
local function adaptWaypointlist(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for zoneId, paths in pairs(value) do
    if type(paths) == "table" then
      local outPaths = {}
      for pathIndex, path in pairs(paths) do
        if type(path) == "table" then
          local outPath = {}
          for i, row in pairs(path) do
            outPath[i] = adaptCoordinateRow(row, false)
          end
          outPaths[pathIndex] = outPath
        else
          outPaths[pathIndex] = path
        end
      end
      out[zoneId] = outPaths
    else
      out[zoneId] = paths
    end
  end
  return out
end

---Adapt the spawnlist nested in `trigger`: { text, spawnlist }.
---@param value any
---@return any adapted
local function adaptTrigger(value)
  if type(value) ~= "table" or type(value[2]) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = v end
  out[2] = adaptSpawnlist(value[2])
  return out
end

---Adapt spawnlists inside `extraobjectives` while preserving every other slot.
---@param value any
---@return any adapted
local function adaptExtraObjectives(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for i, row in pairs(value) do
    if type(row) == "table" and type(row[1]) == "table" then
      local outRow = {}
      for k, v in pairs(row) do outRow[k] = v end
      outRow[1] = adaptSpawnlist(row[1])
      out[i] = outRow
    else
      out[i] = row
    end
  end
  return out
end

local adaptByStructure = {
  spawnlist = adaptSpawnlist,
  waypointlist = adaptWaypointlist,
  trigger = adaptTrigger,
  extraobjectives = adaptExtraObjectives,
}

---Adapt one QuestieTDB field for comparison with Questie's compiled public read.
---@param meta table Entity metadata containing per-field structure names.
---@param fieldIndex number Positional field index.
---@param value any Raw QuestieTDB public value.
---@param fromOverlay boolean Whether a Dynamic Correction supplied the composed value.
---@return any adapted
function compilerCoordinates.adaptField(meta, fieldIndex, value, fromOverlay)
  if fromOverlay then return value end
  local structure = meta.structures and meta.structures[fieldIndex]
  local adapt = structure and adaptByStructure[structure]
  if not adapt then return value end
  return adapt(value)
end

return compilerCoordinates
