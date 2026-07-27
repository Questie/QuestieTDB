-- generator/lib.lua
--
-- Offline utilities shared by generate.lua, verify.lua, test.lua and the validators.
-- Pure Lua 5.1. No C dependencies — in particular no `lfs`; inputs are enumerated in
-- src/config.lua rather than discovered by scanning directories.

local lib = {}

local floor = math.floor
local sub, byte, rep, format = string.sub, string.byte, string.rep, string.format
local concat = table.concat

--------------------------------------------------------------------------------------------
-- Metadata emission
--------------------------------------------------------------------------------------------

--- Write one metadata directive, splitting into a Chunked metadata value when the encoded
--- value exceeds `maxLen`.
---
--- Splitting is UTF-8 safe: the split point backs up while the *next* byte is a continuation
--- byte (0x80-0xBF), so a multi-byte sequence is never cut. Localized names make this
--- reachable in practice.
---
--- See docs/storage-format.md, "Chunked values".
---@param out file* Open output handle
---@param key string Metadata key, without the leading "## " or trailing ":"
---@param value string Encoded value
---@param maxLen number Chunk threshold in bytes
function lib.writeMetadata(out, key, value, maxLen)
  if #value <= maxLen then
    out:write("## ", key, ": ", value, "\n")
    return 1
  end

  local parts = {}
  local pos, len = 1, #value
  while pos <= len do
    local endPos = pos + maxLen - 1
    if endPos >= len then
      parts[#parts + 1] = sub(value, pos)
      break
    end
    -- Back up while the next byte is a UTF-8 continuation byte.
    local nextByte = byte(value, endPos + 1)
    while endPos > pos and nextByte >= 0x80 and nextByte <= 0xBF do
      endPos = endPos - 1
      nextByte = byte(value, endPos + 1)
    end
    parts[#parts + 1] = sub(value, pos, endPos)
    pos = endPos + 1
  end

  out:write("## ", key, ": ~", tostring(#parts), "~\n")
  for i = 1, #parts do
    out:write("## ", key, "-", tostring(i), ": ", parts[i], "\n")
  end
  return #parts + 1
end

--------------------------------------------------------------------------------------------
-- File helpers
--------------------------------------------------------------------------------------------

function lib.fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function lib.readAll(path)
  local f = assert(io.open(path, "rb"), "Cannot open: " .. tostring(path))
  local content = f:read("*a")
  f:close()
  return content
end

function lib.writeAll(path, content)
  local f = assert(io.open(path, "wb"), "Cannot open for writing: " .. tostring(path))
  f:write(content)
  f:close()
end

function lib.copyFile(src, dst)
  lib.writeAll(dst, lib.readAll(src))
end

--- Create a directory, including parents. Uses os.execute rather than lfs, deliberately.
function lib.mkdirp(path)
  if path == "" or path == "." then return end
  -- `mkdir -p` on POSIX; `mkdir` on Windows creates intermediate dirs by default.
  local ok = os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  if ok ~= 0 and ok ~= true then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  end
end

--------------------------------------------------------------------------------------------
-- Build provenance
--------------------------------------------------------------------------------------------

local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- `git rev-parse HEAD`, or forty zeros when git is unavailable.
--- See docs/storage-format.md, "Build metadata".
function lib.gitCommit()
  local pipe = io.popen("git rev-parse HEAD 2>/dev/null", "r")
  if pipe then
    local output = trim(pipe:read("*a") or "")
    pipe:close()
    if output:match("^[0-9a-fA-F]+$") and #output == 40 then
      return output
    end
  end
  return rep("0", 40)
end

--- SOURCE_DATE_EPOCH is honoured so a release build can be byte-reproducible.
function lib.buildTime()
  local epoch = os.getenv("SOURCE_DATE_EPOCH")
  if epoch and tonumber(epoch) then
    return os.date("!%Y-%m-%dT%H:%M:%SZ", tonumber(epoch))
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--------------------------------------------------------------------------------------------
-- Comparison and display
--------------------------------------------------------------------------------------------

--- Deep structural equality. Treats nil and absent identically, which is what the storage
--- format's nil semantics require.
function lib.deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  for k, v in pairs(a) do
    if not lib.deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- Human-readable rendering for mismatch reports. Not a storage encoder.
function lib.show(v, depth)
  depth = depth or 0
  if v == nil then return "nil" end
  local t = type(v)
  if t == "string" then return format("%q", v) end
  if t ~= "table" then return tostring(v) end
  if depth > 6 then return "{...}" end

  local maxIndex = 0
  for k in pairs(v) do
    if type(k) == "number" and k > 0 and k == floor(k) and k > maxIndex then maxIndex = k end
  end

  local parts = {}
  for i = 1, maxIndex do
    parts[#parts + 1] = lib.show(v[i], depth + 1)
  end
  local extra = {}
  for k in pairs(v) do
    if not (type(k) == "number" and k > 0 and k <= maxIndex and k == floor(k)) then
      extra[#extra + 1] = k
    end
  end
  table.sort(extra, function(x, y) return tostring(x) < tostring(y) end)
  for _, k in ipairs(extra) do
    parts[#parts + 1] = "[" .. lib.show(k, depth + 1) .. "]=" .. lib.show(v[k], depth + 1)
  end
  return "{" .. concat(parts, ",") .. "}"
end

--------------------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------------------

--- Numerically sorted list of a table's integer keys.
function lib.sortedIds(tbl)
  local ids = {}
  for id in pairs(tbl) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

function lib.count(tbl)
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

return lib
