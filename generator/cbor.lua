-- generator/cbor.lua
--
-- Deterministic CBOR encoding for generated artifacts. The vendored codec keeps its
-- Blizzard-compatible default order for compatibility tests; generation opts into sorted
-- encoded map keys at every nesting level.

local BlizzardCBOR = dofile("generator/vendor/BlizzardCBOR.lua")

local cbor = {}

---@param value any
---@return string bytes
function cbor.encode(value)
  return BlizzardCBOR.SerializeCBOR(value, { deterministicMapOrder = true })
end

---@param bytes string
---@return any value
function cbor.decode(bytes)
  return BlizzardCBOR.DeserializeCBOR(bytes)
end

return cbor
