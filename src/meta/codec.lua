-- src/meta/codec.lua
--
-- Literal markers and localization decoding for the unchanged l10n metadata store.
-- Entity rows, table fields and ID headers use C_EncodingUtil directly in src/read/baked.lua.
--
-- Three tilde-delimited markers remain in the metadata format:
--
--   ~<N>~   Chunked metadata value with N parts. Reassembled by concatenation.
--   ~E~     The empty string in literal-safe strings.
--   ~Q~...  A Lua string literal for values a TOC line cannot carry raw.

local _, LibQuestieDB = ...

local codec = {}

local tonumber, loadstring = tonumber, loadstring
local match, sub = string.match, string.sub

codec.EMPTY_STRING = "~E~"
codec.QUOTED_PREFIX = "~Q~"

--------------------------------------------------------------------------------------------
-- Chunk headers
--------------------------------------------------------------------------------------------

--- Memoized `~N~` -> N. A chunk header is the only stored value of that exact shape.
codec.chunkCount = setmetatable({}, {
  __index = function(self, key)
    local count = match(key, "^~(%d+)~$")
    if count then
      count = tonumber(count)
      self[key] = count
      return count
    end
    return nil
  end,
})
-- Warm the common cases so the hot path never builds a pattern match.
for i = 1, 32 do codec.chunkCount["~" .. i .. "~"] = i end

--------------------------------------------------------------------------------------------
-- Literal-safe l10n strings
--------------------------------------------------------------------------------------------

function codec.decodeString(value)
  if value == codec.EMPTY_STRING then return "" end
  if sub(value, 1, 3) == codec.QUOTED_PREFIX then
    local chunk = loadstring("return " .. sub(value, 4))
    if not chunk then return nil end
    return chunk()
  end
  return value
end

function codec.decodeNumber(value)
  return tonumber(value)
end

--------------------------------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------------------------------

--- Extract the Nth segment of a separator-joined localized value without materialising the
--- others. An empty segment means "no translation for this locale".
---@param value string
---@param index number 1-based locale index
---@param separator string
function codec.localeSegment(value, index, separator)
  local sepLen = #separator
  local pos = 1
  local current = 1
  while true do
    local segStart, segEnd = string.find(value, separator, pos, true)
    if current == index then
      local segment = segStart and sub(value, pos, segStart - 1) or sub(value, pos)
      if segment == "" then return nil end
      return segment
    end
    if not segStart then return nil end
    pos = segEnd + 1
    current = current + 1
    if sepLen == 0 then return nil end
  end
end

if LibQuestieDB then
  LibQuestieDB.Meta = LibQuestieDB.Meta or {}
  LibQuestieDB.Meta.codec = codec
end

return codec
