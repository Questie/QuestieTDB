-- emulator/metadata.lua
--
-- Stands in for the WoW client's addon-metadata API so a generated database can be proven
-- correct without launching the game.
--
-- Written as a library because Questie's test harness consumes it too: the same emulator
-- backs QuestieTDB's round-trip verification, the source/baked equivalence test, and Questie's
-- own unit tests against a real generated artifact.
--
-- Chunk reassembly deliberately does NOT happen here. `GetAddOnMetadata` in a live client
-- returns exactly what is on the line, so an emulator that transparently joined chunks would
-- hide the very code path most likely to be wrong. Reassembly is src/read/baked.lua's job and
-- is exercised through it. `emulator.getValue` is available for callers that want the joined
-- form directly.

local emulator = {}

local concat = table.concat

--------------------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------------------

--- Parse a generated .toc into a key/value map.
---
--- `map` holds the `## X-...` directives, which is what the storage format uses and what a
--- client returns from `GetAddOnMetadata`. `header` holds every directive including those, so
--- a caller can check `Interface` and `X-Flavor` without knowing which bucket they land in.
--- A value may legitimately be empty, so the pattern accepts one.
---@param path string
---@return table map key -> value, `X-` directives only
---@return table header every `## Key: value` directive
function emulator.parse(path)
  local map, header = {}, {}
  local file = assert(io.open(path, "rb"), "Cannot open: " .. tostring(path))
  local lineNumber = 0

  for line in file:lines() do
    lineNumber = lineNumber + 1
    -- Tolerate CRLF, which a Windows checkout or a naive editor will introduce.
    line = line:gsub("\r$", "")
    local key, value = line:match("^## ([^:]+): ?(.*)$")
    if key then
      header[key] = value
      if key:sub(1, 2) == "X-" then
        if map[key] ~= nil then
          error(("%s:%d duplicate metadata key %s"):format(path, lineNumber, key), 0)
        end
        map[key] = value
      end
    end
  end

  file:close()
  return map, header
end

--------------------------------------------------------------------------------------------
-- Installation
--------------------------------------------------------------------------------------------

--- Install `C_AddOns.GetAddOnMetadata` over a parsed map, matching the client's signature:
--- `GetAddOnMetadata(addonName, key) -> value or nil`.
---
--- Returns a handle so a caller can swap the backing map — which is how the equivalence test
--- and the corruption test drive the same reader over different data.
---@param addonName string
---@param map table
function emulator.install(addonName, map)
  local handle = { addonName = addonName, map = map }

  local function getAddOnMetadata(requestedAddon, key)
    if requestedAddon ~= handle.addonName then return nil end
    return handle.map[key]
  end

  _G.C_AddOns = _G.C_AddOns or {}
  _G.C_AddOns.GetAddOnMetadata = getAddOnMetadata
  _G.GetAddOnMetadata = getAddOnMetadata

  handle.get = getAddOnMetadata
  return handle
end

--- Parse and install in one step.
---@return table handle
---@return table header
function emulator.load(path, addonName)
  local map, header = emulator.parse(path)
  local handle = emulator.install(addonName or "QuestieTDB", map)
  handle.header = header
  return handle, header
end

--------------------------------------------------------------------------------------------
-- Direct access
--------------------------------------------------------------------------------------------

--- Read a value with Chunked metadata values joined. For callers that want the stored value
--- without going through the runtime reader.
function emulator.getValue(map, key)
  local value = map[key]
  if value == nil then return nil end
  local parts = value:match("^~(%d+)~$")
  if not parts then return value end
  parts = tonumber(parts)
  local buffer = {}
  for i = 1, parts do
    local part = map[key .. "-" .. i]
    if part == nil then
      return nil, ("key %s declares %d parts but part %d is missing"):format(key, parts, i)
    end
    buffer[i] = part
  end
  return concat(buffer)
end

--------------------------------------------------------------------------------------------
-- Addon bootstrap
--------------------------------------------------------------------------------------------

--- Execute the Lua files a generated TOC lists, in order, inside a mocked addon environment.
--- This is what makes the offline harness exercise the *shipped* reader rather than a copy of
--- it: the same src/ files the client loads, loaded the same way.
---
--- `baseDir` resolves the listed files against another root — pointing it at an unpacked
--- release zip loads the runtime a user actually installs (with its static correction bodies
--- stripped by tools/strip-static.lua) instead of the working tree's copies.
---@param tocPath string
---@param addonName string?
---@param baseDir string? Root the TOC's file list resolves against; default the working dir
---@return table addonTable The addon namespace, i.e. LibQuestieDB
---@return table files The file list the TOC declared, as loaded
function emulator.loadAddon(tocPath, addonName, baseDir)
  addonName = addonName or "QuestieTDB"
  local addonTable = {}

  local file = assert(io.open(tocPath, "rb"), "Cannot open: " .. tostring(tocPath))
  local files = {}
  for line in file:lines() do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" and not line:find("%.xml$") then
      files[#files + 1] = line:gsub("\\", "/")
    end
  end
  file:close()

  for _, relativePath in ipairs(files) do
    local path = baseDir and (baseDir .. "/" .. relativePath) or relativePath
    local chunk, err = loadfile(path)
    if not chunk then
      error("Cannot load " .. path .. ": " .. tostring(err), 0)
    end
    local ok, execErr = pcall(chunk, addonName, addonTable)
    if not ok then
      error("Error loading " .. path .. ": " .. tostring(execErr), 0)
    end
  end

  return addonTable, files
end

return emulator
