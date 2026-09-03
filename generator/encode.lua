-- generator/encode.lua
--
-- Encoding side of the on-disk contract. Entity rows, table fields, ID headers and
-- localization blocks use deterministic CBOR.
--
-- Entity fields run through src/meta/normalize.lua first, so the generator never invents a
-- second opinion about nil and empty semantics. It stores exactly what a read must return and
-- omits values whose read-time result is already the schema default.

local normalize = dofile("src/meta/normalize.lua")
local base64 = dofile("generator/base64.lua")
local cbor = dofile("generator/cbor.lua")
local LibDeflate = dofile("generator/vendor/LibDeflate.lua")

local encode = {}

local type, next = type, next

--------------------------------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------------------------------

---Whether a normalized field needs storage in a Scalar row or table Metadata field.
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

---Encode one stored table field as base64 CBOR, or nil when its normalized value is absent.
---Scalar fields are collected by generator/rows.lua and encoded together through `row`.
---@param meta table
---@param fieldIndex number
---@param value any Raw source value
---@return string? encoded
function encode.field(meta, fieldIndex, value)
  local normalized = normalize.field(meta, fieldIndex, value)
  if not hasStoredValue(meta, fieldIndex, normalized) then return nil end
  if meta.types[fieldIndex] ~= "table" then
    error("encode.field: scalar fields belong in the entity row", 2)
  end
  return base64.encode(cbor.encode(normalized))
end

---Encode one Scalar row as base64 CBOR.
---@param scalarRow table
---@return string encoded
function encode.row(scalarRow)
  return base64.encode(cbor.encode(scalarRow))
end

--------------------------------------------------------------------------------------------
-- Compressed blocks
--------------------------------------------------------------------------------------------

---Encode one value as deterministic CBOR, zlib level 9, then base64.
---@param value any
---@return string encoded
function encode.compressedCbor(value)
  local compressed = LibDeflate:CompressZlib(cbor.encode(value), { level = 9 })
  if not compressed then error("encode.compressedCbor: zlib compression failed", 2) end
  return base64.encode(compressed)
end

---Encode an ascending ID list as compressed CBOR.
---@param ids number[]
---@return string encoded
function encode.idList(ids)
  return encode.compressedCbor(ids)
end

return encode
