-- generator/serialize.lua
--
-- The Lua-source serializer. TOC metadata stores tables as Lua source decoded by
-- `loadstring("return " .. value)`, so serialization *is* the storage format.
--
-- Two properties are load-bearing rather than cosmetic (docs/storage-format.md):
--
--   * Compactness  — no whitespace, no trailing separators. This directly determines
--                    artifact size.
--   * Determinism  — identical input must produce byte-identical output, or every
--                    regeneration produces a spurious 85 MB diff and checksums stop meaning
--                    anything.
--
-- Ported from Getters/GetterDB/Meta/DumpFunctions.lua, with three deliberate changes:
--
--   1. One generic serializer replaces `dumpCoordinates`/`dumpTriggerEnd`/
--      `dumpExtraObjectives`. Those existed because `dumpAsArray` was array-only and would
--      silently drop `[zoneId]=` keys; a serializer that handles mixed array and hash parts
--      produces byte-identical output for those shapes and generalises to the rest.
--   2. Hash keys are emitted in sorted order. The prototype iterated with `pairs()`, whose
--      order is not stable across runs — that alone violates the determinism requirement.
--   3. String quoting escapes backslashes, control characters and newlines. The prototype
--      escaped only `'`, which cannot survive a value containing a backslash, and a raw
--      newline would break the line-oriented TOC format outright.

local serialize = {}

local type, pairs, tostring, tonumber = type, pairs, tostring, tonumber
local format, gsub, byte, find = string.format, string.gsub, string.byte, string.find
local concat, sort = table.concat, table.sort
local floor = math.floor

--------------------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------------------

--- Shortest decimal literal that reads back as exactly this number.
---
--- Lua 5.1 renders numbers with `%.14g`, which is exact for the coordinates and IDs in this
--- data but not for every double. Widening to `%.17g` only when the shorter form does not
--- round-trip keeps output compact without ever being lossy.
function serialize.number(value)
  local short = tostring(value)
  if tonumber(short) == value then return short end
  local wide = format("%.17g", value)
  if tonumber(wide) == value then return wide end
  return format("%.20g", value)
end

--- Decimal integer, for metadata keys and ID lists.
function serialize.integer(value)
  if value == floor(value) and value >= -2147483648 and value <= 2147483647 then
    return format("%d", value)
  end
  return serialize.number(value)
end

--------------------------------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------------------------------

local ESCAPES = {
  ["\\"] = "\\\\",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["\0"] = "\\0",
}

local function escapeControl(char)
  local escaped = ESCAPES[char]
  if escaped then return escaped end
  return format("\\%d", byte(char))
end

--- A Lua string literal that round-trips exactly through `loadstring`.
---
--- The quote character is whichever of `'` and `"` needs fewer escapes, which is a meaningful
--- saving across a database full of names like `Sharptalon's Claw` alongside quoted titles.
--- The choice is a pure function of the input, so determinism holds.
function serialize.quote(value)
  local singles = select(2, gsub(value, "'", ""))
  local doubles = select(2, gsub(value, '"', ""))
  local quote = (doubles < singles) and '"' or "'"

  local body = gsub(value, "[%z\1-\31\127\\]", escapeControl)
  body = gsub(body, quote, "\\" .. quote)
  return quote .. body .. quote
end

--- True when a string can be stored raw as a top-level metadata value.
--- Raw storage is what makes `## X-2-1: Sharptalon's Claw` legible, but it cannot represent a
--- value containing a line break, and the empty string needs a marker of its own because an
--- absent key already means nil.
function serialize.isRawStorable(value)
  return value ~= "" and not find(value, "[%z\1-\31\127]")
end

--------------------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------------------

local function isArrayIndex(key)
  return type(key) == "number" and key >= 1 and key == floor(key)
end

--- Numbers before strings; numeric keys in numeric order, string keys lexicographically.
local function compareKeys(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  if ta == "number" then return a < b end
  return tostring(a) < tostring(b)
end

local serializeValue

--- Highest positive integer key. Sparse arrays keep their holes — `{{12676},nil,{16305}}` —
--- and the decoder relies on Lua's own table constructor semantics to restore them.
--- Trailing nils are not representable and are not observable, so they are dropped.
local function maxArrayIndex(tbl)
  local max = 0
  for key in pairs(tbl) do
    if isArrayIndex(key) and key > max then max = key end
  end
  return max
end

local function serializeTable(value, depth)
  if depth > 32 then
    error("serialize: table nesting deeper than 32 levels, refusing to recurse", 0)
  end

  local max = maxArrayIndex(value)
  local parts = {}

  for i = 1, max do
    parts[#parts + 1] = serializeValue(value[i], depth + 1)
  end

  local hashKeys
  for key in pairs(value) do
    if not (isArrayIndex(key) and key <= max) then
      hashKeys = hashKeys or {}
      hashKeys[#hashKeys + 1] = key
    end
  end
  if hashKeys then
    sort(hashKeys, compareKeys)
    for _, key in ipairs(hashKeys) do
      local encodedKey
      if type(key) == "number" then
        encodedKey = serialize.number(key)
      elseif type(key) == "string" then
        encodedKey = serialize.quote(key)
      else
        error("serialize: unsupported table key type " .. type(key), 0)
      end
      parts[#parts + 1] = "[" .. encodedKey .. "]=" .. serializeValue(value[key], depth + 1)
    end
  end

  return "{" .. concat(parts, ",") .. "}"
end

serializeValue = function(value, depth)
  local valueType = type(value)
  if value == nil then return "nil" end
  if valueType == "number" then return serialize.number(value) end
  if valueType == "string" then return serialize.quote(value) end
  if valueType == "boolean" then return tostring(value) end
  if valueType == "table" then return serializeTable(value, depth) end
  error("serialize: cannot serialize a " .. valueType, 0)
end

--- Serialize any value to Lua source.
function serialize.value(value)
  return serializeValue(value, 0)
end

--- True when a table holds no keys at all. Empty tables never come back from a read, so they
--- are never written. See docs/storage-format.md, "Nil and empty semantics".
function serialize.isEmptyTable(tbl)
  return next(tbl) == nil
end

return serialize
