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

--- The longest TOC line the client will read. **Measured, not assumed** — on Classic Era
--- 1.15.9, `C_AddOns.GetAddOnMetadata` returns a silently truncated value for any line beyond
--- this, with no error of any kind:
---
---     key `X-Object-IDS-LIST-1`  (line 1024) -> value came back 999 bytes of 1000
---     key `X-Npc-5797-8-1`       (line 1019) -> value came back intact
---
--- A 1024-byte buffer including its terminator. This is the whole reason `writeMetadata`
--- budgets by *line* rather than by value: the key counts against the same limit, and the
--- per-type prefixes this format uses (`X-Object-`, `X-l10n-Quest-`) make keys long enough to
--- matter. Chunking the value alone dropped 17 object IDs from a 43-part ID list, and 27,690
--- lines across the five artifacts were over the limit before this was found.
lib.TOC_LINE_LIMIT = 1023

--- `"## "` and `": "` — what a line costs before the key and value.
lib.TOC_LINE_OVERHEAD = 5

--- Largest value that fits on one line under a given key.
function lib.maxValueLengthFor(key, requested)
  local allowed = lib.TOC_LINE_LIMIT - lib.TOC_LINE_OVERHEAD - #key
  if requested and requested < allowed then return requested end
  return allowed
end

--- Bytes the client's TOC parser trims from the edges of a metadata value. **Measured, not
--- assumed** — see docs/client-metadata-probes.md §1: a chunk part stored with a trailing
--- space came back 997 bytes of 998 on Classic Era 1.15.9, and the reassembled Russian quest
--- text was missing the space. Any part that begins or ends with one of these bytes is
--- silently corrupted on a real client while every offline gate passes.
lib.TRIMMABLE = { [9] = true, [10] = true, [13] = true, [32] = true }

--- Split a value into parts of at most `size` bytes.
---
--- Two constraints on every split point, both measured against a real client:
---
---   * UTF-8 safe — the split backs up while the *next* byte is a continuation byte
---     (0x80-0xBF), so a multi-byte sequence is never cut. Localized names make this
---     reachable in practice, not theoretical.
---   * Trim safe — no part may end, and no following part may begin, with a byte the
---     client trims (space, tab, CR, LF). The client returns each part with its edge
---     whitespace stripped, so a split landing beside a space loses that byte during
---     reassembly with no error anywhere.
---
--- The two compose: after every backup step the loop re-checks both conditions. A value
--- carrying a whitespace run longer than a whole part cannot satisfy the invariant and is a
--- build failure — display text with hundreds of consecutive spaces is corrupt input, not a
--- storage problem.
local function splitValue(value, size)
  local parts = {}
  local pos, len = 1, #value
  while pos <= len do
    local endPos = pos + size - 1
    if endPos >= len then
      parts[#parts + 1] = sub(value, pos)
      break
    end
    while endPos > pos do
      local nextByte = byte(value, endPos + 1)
      if nextByte >= 0x80 and nextByte <= 0xBF then
        endPos = endPos - 1
      elseif lib.TRIMMABLE[nextByte] or lib.TRIMMABLE[byte(value, endPos)] then
        endPos = endPos - 1
      else
        break
      end
    end
    if endPos == pos and (lib.TRIMMABLE[byte(value, pos)] or lib.TRIMMABLE[byte(value, pos + 1)]) then
      error("splitValue: value contains a whitespace run longer than a chunk part and cannot " ..
            "be split trim-safely: " .. sub(value, pos, pos + 60), 0)
    end
    parts[#parts + 1] = sub(value, pos, endPos)
    pos = endPos + 1
  end
  return parts
end

--- Write one metadata directive, splitting into a Chunked metadata value when it does not fit
--- on a single line.
---
--- Part keys are `<key>-<n>`, so they are longer than the base key and grow as the part count
--- gains digits — which feeds back into how much value fits per part. Rather than reason about
--- that fixed point, this splits with an assumed digit count and then *checks every line it is
--- about to write*, retrying with a smaller budget if any would exceed the limit. The check is
--- the contract; the arithmetic is just a good first guess.
---
--- See docs/storage-format.md, "Chunked values".
--- Every key written through one handle, case-folded. `GetAddOnMetadata` folds key case
--- (measured — docs/client-metadata-probes.md §2), so two keys differing only in case are one
--- key to the client and the second silently shadows the first. Weakly keyed so a closed
--- handle's registry can be collected. One artifact written across two handles (entity pass,
--- then l10n append) gets two registries; cross-family safety is covered by the static prefix
--- test in test.lua, since the families' prefixes differ by more than case.
local keyRegistries = setmetatable({}, { __mode = "k" })

local function registerKey(out, key)
  local registry = keyRegistries[out]
  if not registry then registry = {}; keyRegistries[out] = registry end
  local folded = key:lower()
  if registry[folded] then
    error(("writeMetadata: key %q collides case-insensitively with already-written %q — the " ..
      "client folds key case, so one would silently shadow the other"):format(key, registry[folded]), 0)
  end
  registry[folded] = key
end

---@param out file* Open output handle
---@param key string Metadata key, without the leading "## " or trailing ":"
---@param value string Encoded value
---@param maxLen number Upper bound on a part, before the key budget is applied
---@return number lines
function lib.writeMetadata(out, key, value, maxLen)
  -- The client trims the whole value's edges exactly as it trims a chunk part's. A value
  -- arriving here with a trimmable edge would read back changed; the encoders are responsible
  -- for never producing one (quoted string form, trimmed translations), and this chokepoint
  -- turns any lapse into a build failure instead of silent in-client corruption.
  if #value > 0 and (lib.TRIMMABLE[byte(value, 1)] or lib.TRIMMABLE[byte(value, #value)]) then
    error(("writeMetadata: value for key %q begins or ends with a byte the client trims"):format(key), 0)
  end
  registerKey(out, key)

  if lib.TOC_LINE_OVERHEAD + #key + #value <= lib.TOC_LINE_LIMIT then
    out:write("## ", key, ": ", value, "\n")
    return 1
  end

  local parts
  local digits = 1
  for _ = 1, 6 do
    local size = lib.maxValueLengthFor(key .. "-" .. rep("9", digits), maxLen)
    if size < 1 then
      error(("writeMetadata: key %q is too long to carry any value on one line"):format(key), 0)
    end
    parts = splitValue(value, size)

    local grew = #tostring(#parts) > digits
    local fits = true
    for i = 1, #parts do
      if lib.TOC_LINE_OVERHEAD + #key + 1 + #tostring(i) + #parts[i] > lib.TOC_LINE_LIMIT then
        fits = false
        break
      end
    end
    if fits and not grew then break end
    digits = math.max(digits + 1, #tostring(#parts))
    parts = nil
  end

  if not parts then
    error(("writeMetadata: could not find a chunk size for key %q"):format(key), 0)
  end

  out:write("## ", key, ": ~", tostring(#parts), "~\n")
  for i = 1, #parts do
    registerKey(out, key .. "-" .. tostring(i))
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

---@param str string
---@return string trimmed
local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Quotes one value for the POSIX shell used by the offline Git helper.
---@param value string
---@return string quoted
local function shellQuote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

--- `git rev-parse HEAD`, or forty zeros when git is unavailable. With `dir`, the commit of
--- that checkout instead — used to record the Questie input commit.
--- See docs/storage-format.md, "Build metadata".
---@param dir string? Git checkout, defaulting to the current directory.
---@return string commit
function lib.gitCommit(dir)
  local cmd = dir and ("git -C " .. shellQuote(dir) .. " rev-parse HEAD 2>/dev/null")
                   or "git rev-parse HEAD 2>/dev/null"
  local pipe = io.popen(cmd, "r")
  if pipe then
    local output = trim(pipe:read("*a") or "")
    pipe:close()
    if output:match("^[0-9a-fA-F]+$") and #output == 40 then return output end
  end
  return rep("0", 40)
end

---Fails unless a Questie checkout is at the reviewed input commit.
---@param questiePath string Questie checkout to validate.
---@param pinPath string? Pin file, defaulting to `QUESTIE_COMMIT`.
---@return string commit The validated Questie commit.
function lib.assertQuestiePin(questiePath, pinPath)
  pinPath = pinPath or "QUESTIE_COMMIT"
  if not lib.fileExists(pinPath) then
    error("Questie pin file not found: " .. pinPath, 0)
  end

  local expected = trim(lib.readAll(pinPath))
  if #expected ~= 40 or not expected:match("^[0-9a-f]+$") then
    error(pinPath .. " must contain one lowercase 40-character Git SHA", 0)
  end

  local actual = lib.gitCommit(questiePath)
  if actual ~= expected then
    error(("Questie checkout %s is at %s, expected pinned commit %s. Check out the pin or " ..
      "update QUESTIE_COMMIT and review the resulting schema, Correction, differential, and " ..
      "Golden changes."):format(questiePath, actual, expected), 0)
  end
  return actual
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
