-- src/meta/normalize.lua
--
-- Nil and empty semantics. The single definition of what a field read must return, shared by
-- Generation, Source mode, Baked mode and the verifier — so "what I see in dev is what ships"
-- follows from shared code rather than from a test.
--
-- The rule is to match Questie's current compiler exactly. ~290 call sites have been written
-- against these semantics, so any deviation is a silent behaviour change. See
-- docs/storage-format.md, "Nil and empty semantics".
--
--   | Source value      | Read back as                                        |
--   | number nil        | 0      — lossy and deliberate; writers emit `value or 0`
--   | number n          | n
--   | string nil        | nil
--   | string ""         | ""     — distinct from nil, must survive
--   | table nil         | nil
--   | table {}          | nil    — empty tables never come back
--   | pair {0, 0}       | nil    — Questie's documented hack
--   | unknown entity ID | nil
--   | coordinate c      | floor(c * 40.90) / 40.90 — the compiler's 12-bit grid, ADR 0003 D1
--
-- Verified against Questie/Database/compiler.lua:
--   readers["u12pair"]/["s24pair"]   `if a == 0 and b == 0 then return nil end`
--   readers["u8u24array"] and kin    `if count == 0 then return nil end`
--   writers["u8"] and kin            `stream:WriteByte(value or 0)`
--   readers["faction"]               3 -> nil, 2 -> "AH", 1 -> "H", else "A"
--   writers["faction"]               nil -> 3, "A" -> 0, "H" -> 1, "" -> 3, else -> 2

local _, LibQuestieDB = ...

local normalize = {}

local type, next = type, next
local floor = math.floor

--------------------------------------------------------------------------------------------
-- Coordinate quantization (ADR 0003, Decision 1)
--------------------------------------------------------------------------------------------
--
-- "Match Questie exactly" means matching what the ~290 existing call sites observe, which is
-- compiled reads: the compiler stores each coordinate as `floor(coord * 40.90)` in a 12-bit
-- pair and the reader divides it back out, so every consumer sees the 40.90 grid — never the
-- source literal. Reproduced here, in the shared normalizer, so Generation, Source mode, the
-- Correction Overlay and the verifier all agree without a second opinion.
--
-- The sentinel rules come from Database/compiler.lua verbatim:
--   * writers: a `{-1,-1}` instance spawn is stored as the zero pair.
--   * readers: a zero pair reads back as `{-1,-1}` — so an exact-zero or sub-quantum
--     coordinate also collapses to the instance sentinel, and a spawn's phase survives only
--     when its quantized pair is non-zero (readers emit the 2-element form for phase 0).
--   * waypoint rows never carry a third element on the read side.
--
-- Rows that do not have numeric x and y pass through untouched: shape validation belongs to
-- the validators, and quantization must not invent an opinion about malformed data.
--
-- NOT idempotent, exactly like the compiler: `floor(q * 40.90)` on a grid value can land one
-- step lower through double rounding (738 of 10,000 2dp coordinates, measured). Every path
-- must quantize a *raw* value exactly once — never re-normalize a value read back from the
-- store, and a Correction must supply authored coordinates, not coordinates it read out of
-- the database.

--- Quantize one spawn row. `keepPhase` distinguishes spawnlist rows (phase survives) from
--- waypoint rows (never a third element). The grid integers are kept un-divided until the
--- sentinel test because `floor(x * 40.90) == 0` is what "sub-quantum" means.
local function quantizeRow(row, keepPhase)
  if type(row) ~= "table" or type(row[1]) ~= "number" or type(row[2]) ~= "number" then
    return row
  end
  local qx, qy
  if row[1] == -1 and row[2] == -1 then
    qx, qy = 0, 0
  else
    qx, qy = floor(row[1] * 40.90), floor(row[2] * 40.90)
  end
  if qx == 0 and qy == 0 then
    return { -1, -1 }
  end
  if keepPhase and (row[3] or 0) ~= 0 then
    return { qx / 40.90, qy / 40.90, row[3] }
  end
  return { qx / 40.90, qy / 40.90 }
end

--- `spawnlist`: zoneId -> { {x, y, phase?}, ... }
local function quantizeSpawnlist(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for zoneId, rows in pairs(value) do
    if type(rows) == "table" then
      local outRows = {}
      for i, row in pairs(rows) do
        outRows[i] = quantizeRow(row, true)
      end
      out[zoneId] = outRows
    else
      out[zoneId] = rows
    end
  end
  return out
end

--- `waypointlist`: zoneId -> { { {x, y}, ... }, ... } — one more nesting level than spawns.
local function quantizeWaypointlist(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for zoneId, paths in pairs(value) do
    if type(paths) == "table" then
      local outPaths = {}
      for pathIndex, path in pairs(paths) do
        if type(path) == "table" then
          local outPath = {}
          for i, row in pairs(path) do
            outPath[i] = quantizeRow(row, false)
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

--- `trigger`: { text, spawnlist }. Only the nested spawnlist quantizes.
local function quantizeTrigger(value)
  if type(value) ~= "table" or type(value[2]) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = v end
  out[2] = quantizeSpawnlist(value[2])
  return out
end

--- `extraobjectives`: rows of { spawnlist, icon, text, index, reflist }. Only each row's
--- nested spawnlist quantizes; everything else is preserved verbatim.
local function quantizeExtraObjectives(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for i, row in pairs(value) do
    if type(row) == "table" and type(row[1]) == "table" then
      local outRow = {}
      for k, v in pairs(row) do outRow[k] = v end
      outRow[1] = quantizeSpawnlist(row[1])
      out[i] = outRow
    else
      out[i] = row
    end
  end
  return out
end

local quantizeByStructure = {
  spawnlist = quantizeSpawnlist,
  waypointlist = quantizeWaypointlist,
  trigger = quantizeTrigger,
  extraobjectives = quantizeExtraObjectives,
}

--------------------------------------------------------------------------------------------
-- Named normalizers
--------------------------------------------------------------------------------------------

--- `friendlyToFaction` carries "A", "H", or both. Questie encodes it as one byte and collapses
--- every "both" spelling to "AH"; nil and "" are indistinguishable after the round trip.
function normalize.faction(value)
  if value == nil or value == "" then return nil end
  if value == "A" then return "A" end
  if value == "H" then return "H" end
  return "AH"
end

normalize.byName = {
  faction = normalize.faction,
}

--------------------------------------------------------------------------------------------
-- Field normalization
--------------------------------------------------------------------------------------------

--- Canonical read-back value for one field of one entity.
---
--- This is deliberately total: given the raw source value it returns exactly what every read
--- path must produce, so Generation can decide what to store, Source mode can serve raw
--- tables, and the verifier can compute an expectation without a fourth opinion.
---@param meta table Entity meta from src/meta/<entity>Meta.lua
---@param fieldIndex number
---@param value any Raw source value
---@return any
function normalize.field(meta, fieldIndex, value)
  local storage = meta.types[fieldIndex]

  if storage == "number" then
    -- Numeric getters default to 0, never nil. 0 is truthy in Lua, so consumers already test
    -- `~= 0`; returning nil would change behaviour at every one of those sites.
    if value == nil then return 0 end
    return value
  end

  if storage == "string" then
    local named = meta.normalize[fieldIndex]
    if named then
      local fn = normalize.byName[named]
      if not fn then
        error("normalize: unknown normalizer '" .. tostring(named) .. "'", 0)
      end
      return fn(value)
    end
    -- nil stays nil; "" stays "" and is distinct from nil.
    return value
  end

  if storage == "table" then
    if value == nil then return nil end
    if type(value) ~= "table" then return value end
    -- Empty tables never come back. Both nil and {} collapse to nil.
    if next(value) == nil then return nil end
    if meta.zeroPairIsNil[fieldIndex] and (value[1] or 0) == 0 and (value[2] or 0) == 0 then
      return nil
    end
    local quantizer = meta.structures and quantizeByStructure[meta.structures[fieldIndex]]
    if quantizer then return quantizer(value) end
    return value
  end

  error("normalize: field " .. tostring(fieldIndex) .. " of " .. tostring(meta.entity) ..
        " has unknown storage type " .. tostring(storage), 0)
end

--- Default value for a field that has no stored metadata. Numbers default to 0, everything
--- else to nil.
function normalize.default(meta, fieldIndex)
  if meta.types[fieldIndex] == "number" then return 0 end
  return nil
end

if LibQuestieDB then
  LibQuestieDB.Meta = LibQuestieDB.Meta or {}
  LibQuestieDB.Meta.normalize = normalize
end

return normalize
