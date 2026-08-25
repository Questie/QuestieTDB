-- generator/encode.lua
--
-- Encoding side of the on-disk contract; the mirror of src/meta/codec.lua.
--
-- Everything here runs through src/meta/normalize.lua first, so the generator never invents a
-- second opinion about nil and empty semantics — it stores exactly what a read must return,
-- and omits the line entirely whenever the read would produce the field's default.

local serialize = dofile("generator/serialize.lua")
local codec = dofile("src/meta/codec.lua")
local normalize = dofile("src/meta/normalize.lua")

local encode = {}

local type, next = type, next
local find, concat = string.find, table.concat

--------------------------------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------------------------------

--- True when a raw string would be mistaken for one of the tilde markers.
local function collidesWithMarker(value)
  if value == codec.EMPTY_STRING then return true end
  if value:sub(1, 3) == codec.QUOTED_PREFIX then return true end
  if codec.chunkCount[value] then return true end
  return false
end

--- Store a string raw where possible, because that is what makes a generated TOC legible and
--- keeps the artifact small. Fall back to a Lua literal for anything a line-oriented format
--- cannot carry — control characters, marker lookalikes, and strings the client's own parser
--- would alter: it trims leading and trailing whitespace from every metadata value (measured,
--- docs/client-metadata-probes.md §1), so an edge-whitespace string survives only in quoted
--- form, where the quote characters become the value's edges.
function encode.string(value)
  if value == "" then return codec.EMPTY_STRING end
  if find(value, "[%z\1-\31\127]") or collidesWithMarker(value)
     or find(value, "^ ") or find(value, " $") then
    return codec.QUOTED_PREFIX .. serialize.quote(value)
  end
  return value
end

--------------------------------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------------------------------

---Whether a normalized field needs a metadata line.
---Verification calls this after normalization so it shares Generation's omission rules
---without serializing every table a second time.
---@param meta table
---@param fieldIndex number
---@param normalized any Value returned by `normalize.field`
---@return boolean
local function hasStoredValue(meta, fieldIndex, normalized)
  -- A constant field's schema placeholder reconstructs the value in both read modes. Storing
  -- the same value once per entity would be redundant, including for non-zero placeholders.
  local constantValues = meta.constantValues
  if constantValues and constantValues[fieldIndex] ~= nil then return false end
  if normalized == nil then return false end

  local storage = meta.types[fieldIndex]
  if storage ~= "number" and storage ~= "string" and storage ~= "table" then
    error("encode: unknown storage type " .. tostring(storage), 0)
  end
  if type(normalized) ~= storage then
    error(string.format("%s field %d (%s): expected a %s, got %s (%s)",
      meta.entity, fieldIndex, tostring(meta.names[fieldIndex]), storage, type(normalized),
      tostring(normalized)), 0)
  end

  if storage == "number" then return normalized ~= 0 end
  if storage == "table" then return next(normalized) ~= nil end
  return true
end

encode.hasStoredValue = hasStoredValue

--- Encode one field of one entity, or return nil when no line should be written.
---
--- Absence is the encoding for constants, nil, numeric zero, and empty tables whose read-time
--- default is already in the schema.
---@param meta table
---@param fieldIndex number
---@param value any Raw source value
---@return string? encoded
function encode.field(meta, fieldIndex, value)
  local normalized = normalize.field(meta, fieldIndex, value)
  if not hasStoredValue(meta, fieldIndex, normalized) then return nil end

  local storage = meta.types[fieldIndex]
  if storage == "number" then return serialize.number(normalized) end
  if storage == "string" then return encode.string(normalized) end
  return serialize.value(normalized)
end

--------------------------------------------------------------------------------------------
-- ID list
--------------------------------------------------------------------------------------------

--- Comma-separated decimal IDs, ascending. Chunking applies to this value like any other.
function encode.idList(ids)
  local parts = {}
  for i = 1, #ids do parts[i] = serialize.integer(ids[i]) end
  return concat(parts, ",")
end

encode.EMPTY_STRING = codec.EMPTY_STRING
encode.QUOTED_PREFIX = codec.QUOTED_PREFIX

return encode
