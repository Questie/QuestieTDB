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
