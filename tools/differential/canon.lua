-- tools/differential/canon.lua
--
-- Canonical serialization shared by both dumpers. One representation per value, independent
-- of table iteration order or float printing habits, so a byte-equal line means a
-- semantically equal composed read.

local floor, abs, format = math.floor, math.abs, string.format
local sort, concat = table.sort, table.concat

local function fmtNumber(n)
  if n == floor(n) and abs(n) < 2 ^ 53 then return format("%d", n) end
  return format("%.17g", n)
end

local function fmtString(s)
  -- Escape only what breaks a one-line TSV cell; UTF-8 bytes pass through raw and compare
  -- byte-for-byte.
  return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return format("\\%03d", c:byte())
  end) .. '"'
end

local fmtValue

local function fmtKey(k)
  if type(k) == "number" then return "[" .. fmtNumber(k) .. "]" end
  return "[" .. fmtString(tostring(k)) .. "]"
end

local function fmtTable(t)
  local numberKeys, stringKeys = {}, {}
  for k in pairs(t) do
    if type(k) == "number" then numberKeys[#numberKeys + 1] = k
    else stringKeys[#stringKeys + 1] = tostring(k) end
  end
  sort(numberKeys)
  sort(stringKeys)
  local parts = {}
  for _, k in ipairs(numberKeys) do
    parts[#parts + 1] = fmtKey(k) .. "=" .. fmtValue(t[k])
  end
  for _, k in ipairs(stringKeys) do
    parts[#parts + 1] = fmtKey(k) .. "=" .. fmtValue(t[k])
  end
  return "{" .. concat(parts, ",") .. "}"
end

fmtValue = function(v)
  local kind = type(v)
  if kind == "number" then return fmtNumber(v) end
  if kind == "string" then return fmtString(v) end
  if kind == "boolean" then return tostring(v) end
  if kind == "table" then return fmtTable(v) end
  error("Uncanonicalizable value type: " .. kind)
end

return fmtValue
