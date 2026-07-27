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
--- cannot carry.
function encode.string(value)
  if value == "" then return codec.EMPTY_STRING end
  if find(value, "[%z\1-\31\127]") or collidesWithMarker(value) then
    return codec.QUOTED_PREFIX .. serialize.quote(value)
  end
  return value
end

--------------------------------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------------------------------

--- Encode one field of one entity, or return nil when no line should be written.
---
--- Absence is the encoding for nil, and for a numeric zero — a numeric read with no stored
--- metadata returns 0, so writing `0` explicitly would cost bytes and say nothing.
---@param meta table
---@param fieldIndex number
---@param value any Raw source value
---@return string? encoded
function encode.field(meta, fieldIndex, value)
  local normalized = normalize.field(meta, fieldIndex, value)
  if normalized == nil then return nil end

  local storage = meta.types[fieldIndex]

  if storage == "number" then
    if type(normalized) ~= "number" then
      error(string.format("%s field %d (%s): expected a number, got %s (%s)",
        meta.entity, fieldIndex, tostring(meta.names[fieldIndex]), type(normalized),
        tostring(normalized)), 0)
    end
    if normalized == 0 then return nil end
    return serialize.number(normalized)
  end

  if storage == "string" then
    if type(normalized) ~= "string" then
      error(string.format("%s field %d (%s): expected a string, got %s (%s)",
        meta.entity, fieldIndex, tostring(meta.names[fieldIndex]), type(normalized),
        tostring(normalized)), 0)
    end
    return encode.string(normalized)
  end

  if storage == "table" then
    if type(normalized) ~= "table" then
      error(string.format("%s field %d (%s): expected a table, got %s (%s)",
        meta.entity, fieldIndex, tostring(meta.names[fieldIndex]), type(normalized),
        tostring(normalized)), 0)
    end
    return serialize.value(normalized)
  end

  error("encode: unknown storage type " .. tostring(storage), 0)
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
