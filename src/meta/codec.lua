-- src/meta/codec.lua
--
-- Decoding side of the on-disk contract. See docs/storage-format.md.
--
--   number  decimal literal                     ## X-Quest-2-4: 20
--   string  raw text, unquoted                  ## X-Quest-2-1: Sharptalon's Claw
--   table   Lua table source                    ## X-Quest-2-2: {{12676},nil,{16305}}
--
-- Three tilde-delimited markers sit in front of that, and are checked before the value is
-- interpreted as its declared type:
--
--   ~<N>~   Chunked metadata value with N parts. Reassembled by concatenation.
--   ~E~     The empty string. Needed because an absent key already means nil, so "" has no
--           other way to distinguish itself.
--   ~Q~...  A Lua string literal, for the rare value that cannot be stored raw — one holding
--           a control character or a line break, which the line-oriented TOC format cannot
--           carry, or one that would otherwise collide with a marker.
--
-- Ordinary values cannot be mistaken for a marker: numbers are digits, table literals start
-- with `{`, and any raw string that happens to look like a marker is written in `~Q~` form
-- instead. Encoding lives in generator/encode.lua and shares these constants.

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
-- Value decoding
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

--- Compile a stored table literal into a producer function. Each call of the producer
--- executes the chunk and yields a **fresh, mutable, deeply independent** table — the
--- fresh-per-read mechanism of ADR 0003 Decision 10. Lua literal syntax cannot express
--- aliasing or cycles, so every execution is a tree the caller owns outright.
---
--- Measured on Classic Era build 69109: re-execution costs 0.13–1.8 µs for typical field
--- shapes (19 µs for the largest spawn tables) — the same class as a decoded-cache hit,
--- which is what voided the design's original reason for rejecting fresh-per-read values.
---@return function? producer nil when the stored text does not compile
function codec.compileTable(value)
  return (loadstring("return " .. value))
end

function codec.decodeTable(value)
  local chunk = codec.compileTable(value)
  if not chunk then return nil end
  return chunk()
end

codec.decoders = {
  string = codec.decodeString,
  number = codec.decodeNumber,
  table = codec.decodeTable,
}

--------------------------------------------------------------------------------------------
-- ID lists
--------------------------------------------------------------------------------------------

--- `## X-<prefix>IDS-LIST: 2,5,7,12,...` — comma-separated decimal IDs, ascending.
function codec.decodeIdList(value)
  if not value or value == "" then return {} end
  local chunk = loadstring("return {" .. value .. "}")
  if not chunk then return {} end
  return chunk()
end

--- Same source, built directly as a hashmap so `GetAllIds(true)` is a drop-in for Questie's
--- `*Pointers[id]` existence checks.
function codec.decodeIdMap(value)
  if not value or value == "" then return {} end
  local chunk = loadstring("return {" .. value:gsub("(%d+)", "[%1]=true") .. "}")
  if not chunk then return {} end
  return chunk()
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
