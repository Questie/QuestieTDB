#!/usr/bin/env lua
-- verify.lua
--
-- Round-trip verification: for every entity and every field, the value read back through the
-- shipped reader must equal what the storage format says that source value reads back as.
--
-- This is a required CI gate, not a smoke test. It is also the feedback signal every other
-- part of the build leans on, so it runs the *real* runtime files out of src/ against the
-- metadata emulator rather than a reimplementation of them.
--
-- Usage:
--   lua verify.lua                     every generated flavor found on disk
--   lua verify.lua Vanilla TBC         named flavors
--   lua verify.lua Vanilla --types=Quest
--   lua verify.lua Vanilla --sample=500      check N ids per type instead of all
--
-- Exits non-zero on any mismatch.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")
local schema = dofile("generator/schema.lua")
local encode = dofile("generator/encode.lua")
local emulator = dofile("emulator/metadata.lua")

local MAX_REPORTED = 12

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

local function parseArgs(argv)
  local opts = { flavors = {}, types = nil, fields = nil, sample = nil, quiet = false, tocDir = "." }
  for _, value in ipairs(argv or {}) do
    local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
    if key == "types" then
      opts.types = {}
      for name in val:gmatch("[^,]+") do opts.types[name] = true end
    elseif key == "fields" then
      opts.fields = {}
      for name in val:gmatch("[^,]+") do opts.fields[name] = true end
    elseif key == "sample" then
      opts.sample = tonumber(val)
    elseif key == "toc-dir" then
      opts.tocDir = val
    elseif value == "--quiet" then
      opts.quiet = true
    elseif value:sub(1, 2) == "--" then
      error("Unknown option: " .. value, 0)
    else
      opts.flavors[#opts.flavors + 1] = value
    end
  end
  return opts
end

local opts = parseArgs(arg)
local function say(...)
  if not opts.quiet then print(...) end
end

--------------------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------------------

local function reportMismatch(report, entityName, id, fieldIndex, fieldName, expected, actual)
  report.errors = report.errors + 1
  if report.errors <= MAX_REPORTED then
    io.write(("  MISMATCH %s %s field %d (%s)\n"):format(entityName, tostring(id), fieldIndex, fieldName))
    io.write(("    expected: %s\n"):format(lib.show(expected):sub(1, 200)))
    io.write(("    actual:   %s\n"):format(lib.show(actual):sub(1, 200)))
  elseif report.errors == MAX_REPORTED + 1 then
    io.write("  ... further mismatches suppressed\n")
  end
end

--- Verify one flavor's generated TOC against the raw entity data it was generated from.
local function verifyFlavor(flavor, opts)
  local tocPath = (opts.tocDir or ".") .. "/" .. config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    say(("[SKIP] %s: %s not generated"):format(flavor.name, tocPath))
    return 0, true
  end

  local report = { errors = 0, entities = 0, fields = 0, chunked = 0 }
  local started = os.clock()

  -- Install the emulator before loading the addon: src/read/baked.lua captures
  -- GetAddOnMetadata at load time, exactly as it does in a client.
  local map, header = emulator.parse(tocPath)
  emulator.install(config.addonName, map)
  local LibQuestieDB = emulator.loadAddon(tocPath, config.addonName)

  if header["X-Flavor"] ~= flavor.name then
    io.write(("  HEADER %s: X-Flavor is %s, expected %s\n"):format(tocPath, tostring(header["X-Flavor"]), flavor.name))
    report.errors = report.errors + 1
  end
  if header["X-Contract-Version"] ~= tostring(config.contractVersion) then
    io.write(("  HEADER %s: X-Contract-Version is %s, expected %s\n")
      :format(tocPath, tostring(header["X-Contract-Version"]), tostring(config.contractVersion)))
    report.errors = report.errors + 1
  end

  for key, value in pairs(map) do
    if value:match("^~%d+~$") then report.chunked = report.chunked + 1 end
  end

  local normalize = LibQuestieDB.Meta.normalize
  local seenKeys = {}

  for _, entityType in ipairs(config.entityTypes) do
    if not opts.types or opts.types[entityType.name] then
      local entity = LibQuestieDB[entityType.name]
      local meta = LibQuestieDB.Meta[entityType.name]
      local sourceEntities = loader.loadEntityData(config.dataPath(flavor, entityType), entityType)

      -- The ID list must round-trip in both forms consumers build from it.
      local sourceIds = lib.sortedIds(sourceEntities)
      local storedList = entity.GetAllIds()
      local storedMap = entity.GetAllIds(true)
      if not lib.deepEqual(sourceIds, storedList) then
        io.write(("  MISMATCH %s IDS-LIST: %d source ids, %d stored\n")
          :format(entityType.name, #sourceIds, #storedList))
        report.errors = report.errors + 1
      end
      for _, id in ipairs(sourceIds) do
        if storedMap[id] ~= true then
          io.write(("  MISMATCH %s IDS-LIST hashmap missing id %d\n"):format(entityType.name, id))
          report.errors = report.errors + 1
          break
        end
      end
      seenKeys["X-" .. meta.metaPrefix .. "IDS-LIST"] = true

      local checkIds = sourceIds
      if opts.sample and #sourceIds > opts.sample then
        checkIds = {}
        local stride = math.floor(#sourceIds / opts.sample)
        for i = 1, #sourceIds, stride do checkIds[#checkIds + 1] = sourceIds[i] end
      end

      for _, id in ipairs(checkIds) do
        report.entities = report.entities + 1
        local row = sourceEntities[id]
        for fieldIndex = 1, meta.fieldCount do
         if not opts.fields or opts.fields[meta.names[fieldIndex]] then
          local expected = normalize.field(meta, fieldIndex, row[fieldIndex])
          local actual = entity.Get(id, fieldIndex)
          report.fields = report.fields + 1
          if not lib.deepEqual(expected, actual) then
            reportMismatch(report, entityType.name, id, fieldIndex, meta.names[fieldIndex], expected, actual)
          end
          -- Named getter and generic getter must agree.
          local named = entity[meta.names[fieldIndex]](id)
          if not lib.deepEqual(actual, named) then
            reportMismatch(report, entityType.name, id, fieldIndex,
              meta.names[fieldIndex] .. " (named getter)", actual, named)
          end
          if encode.field(meta, fieldIndex, row[fieldIndex]) ~= nil then
            seenKeys["X-" .. meta.metaPrefix .. id .. "-" .. fieldIndex] = true
          end
         end
        end
      end

      -- An unknown entity ID must read as nil, never as a stray default.
      local absentId = sourceIds[#sourceIds] + 1000000
      for fieldIndex = 1, meta.fieldCount do
       if not opts.fields or opts.fields[meta.names[fieldIndex]] then
        local value = entity.Get(absentId, fieldIndex)
        local expectedAbsent = normalize.default(meta, fieldIndex)
        if value ~= expectedAbsent then
          io.write(("  MISMATCH %s unknown id %d field %d: expected %s, got %s\n")
            :format(entityType.name, absentId, fieldIndex, tostring(expectedAbsent), tostring(value)))
          report.errors = report.errors + 1
        end
       end
      end
    end
  end

  -- Orphan keys mean the generator wrote something no read will ever reach.
  if not opts.types and not opts.sample and not opts.fields then
    local headerKeys = {
      ["X-Contract-Version"] = true, ["X-Flavor"] = true, ["X-Mode"] = true,
      ["X-BUILD-COMMIT"] = true, ["X-BUILD-TIME"] = true,
    }
    local orphans = 0
    for key in pairs(map) do
     if not headerKeys[key] then
      if not seenKeys[key] and not key:match("%-%d+$") then
        orphans = orphans + 1
      elseif not seenKeys[key] then
        -- Chunk parts are named `<baseKey>-<n>`; accept them when their base key is known.
        local base = key:match("^(.*)%-%d+$")
        if not (base and seenKeys[base]) then orphans = orphans + 1 end
      end
     end
    end
    if orphans > 0 then
      io.write(("  ORPHANS %s: %d stored keys no read path reaches\n"):format(tocPath, orphans))
      report.errors = report.errors + orphans
    end
  end

  say(("[%s] %s: %d entities, %d fields, %d chunked values, %d errors, %.1fs")
    :format(report.errors == 0 and "PASS" or "FAIL", flavor.name,
            report.entities, report.fields, report.chunked, report.errors, os.clock() - started))
  return report.errors, false
end

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local flavors = {}
if #opts.flavors == 0 then
  flavors = config.flavors
else
  for _, name in ipairs(opts.flavors) do
    local flavor = config.flavorByName[name]
    if not flavor then error("Unknown flavor: " .. name, 0) end
    flavors[#flavors + 1] = flavor
  end
end

local totalErrors, checked = 0, 0
for _, flavor in ipairs(flavors) do
  local errors, skipped = verifyFlavor(flavor, opts)
  totalErrors = totalErrors + errors
  if not skipped then checked = checked + 1 end
end

if checked == 0 then
  io.write("verify: nothing to verify — no generated TOC found. Run `lua generate.lua all` first.\n")
  os.exit(1)
end

os.exit(totalErrors == 0 and 0 or 1)
