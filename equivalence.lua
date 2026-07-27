#!/usr/bin/env lua
-- equivalence.lua
--
-- Proof that what a contributor sees in Source mode is exactly what ships in Baked mode.
--
-- This is the load-bearing test in the system. Unlike the compiled/TOC differential it never
-- retires: two permanent read modes mean it guards forever. Both readers are stood up in one
-- process, over the real `src/` files, and every entity and every field is compared.
--
-- Usage:
--   lua equivalence.lua                     every generated flavor
--   lua equivalence.lua Vanilla
--   lua equivalence.lua --sample=2000       a representative subset per entity type
--   lua equivalence.lua --toc-dir=.out/x    read artifacts from elsewhere
--
-- Exits non-zero on any divergence.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local emulator = dofile("emulator/metadata.lua")
local freezeLib = dofile("emulator/freeze.lua")
local client = dofile("emulator/client.lua")

local MAX_REPORTED = 12

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

local function parseArgs(argv)
  local opts = { flavors = {}, types = nil, sample = nil, quiet = false, tocDir = "." }
  for _, value in ipairs(argv or {}) do
    local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
    if key == "types" then
      opts.types = {}
      for name in val:gmatch("[^,]+") do opts.types[name] = true end
    elseif key == "sample" then
      opts.sample = tonumber(val)
    elseif key == "toc-dir" then
      opts.tocDir = val
    elseif value == "--freeze" then
      opts.freeze = true
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
-- Divergence classification
--------------------------------------------------------------------------------------------

--- Nil versus empty table is the predicted failure mode — the whole `EMPTY` sentinel argument
--- turns on it — so it is named rather than lumped in with everything else.
local function classify(sourceValue, bakedValue)
  local function isEmptyTable(v) return type(v) == "table" and next(v) == nil end
  if (sourceValue == nil and isEmptyTable(bakedValue)) or
     (bakedValue == nil and isEmptyTable(sourceValue)) then
    return "NIL-VS-EMPTY-TABLE"
  end
  if type(sourceValue) ~= type(bakedValue) then return "TYPE" end
  if type(sourceValue) == "number" then return "NUMBER" end
  if type(sourceValue) == "string" then return "STRING" end
  return "VALUE"
end

--------------------------------------------------------------------------------------------
-- Loading both modes
--------------------------------------------------------------------------------------------

local function loadSourceMode(flavor)
  client.reset()
  client.install({ expansion = flavor.expansion })
  local Lib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
  if opts.freeze then freezeLib.install(Lib) end
  return Lib
end

local function loadBakedMode(tocPath)
  client.reset()
  client.install({})
  local map = emulator.parse(tocPath)
  emulator.install(config.addonName, map)
  local Lib = emulator.loadAddon(tocPath, config.addonName)
  if opts.freeze then freezeLib.install(Lib) end
  return Lib
end

--------------------------------------------------------------------------------------------
-- Comparison
--------------------------------------------------------------------------------------------

local function compareFlavor(flavor)
  local tocPath = (opts.tocDir or ".") .. "/" .. config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    say(("[SKIP] %s: %s not generated"):format(flavor.name, tocPath))
    return 0, true
  end

  local started = os.clock()
  local report = { errors = 0, fields = 0, entities = 0, byKind = {} }

  local sourceLib = loadSourceMode(flavor)
  local bakedLib = loadBakedMode(tocPath)

  if sourceLib.readMode ~= "source" then
    io.write("  ERROR: base TOC did not select source mode\n")
    report.errors = report.errors + 1
  end
  if bakedLib.readMode ~= "baked" then
    io.write("  ERROR: generated TOC did not select baked mode\n")
    report.errors = report.errors + 1
  end
  if sourceLib.read.source.expansion ~= flavor.expansion then
    io.write(("  ERROR: source mode selected %s, expected %s\n")
      :format(tostring(sourceLib.read.source.expansion), flavor.expansion))
    report.errors = report.errors + 1
  end

  for _, entityType in ipairs(config.entityTypes) do
    if not opts.types or opts.types[entityType.name] then
      local sourceEntity = sourceLib[entityType.name]
      local bakedEntity = bakedLib[entityType.name]
      local meta = bakedLib.Meta[entityType.name]

      local sourceIds = sourceEntity.GetAllIds()
      local bakedIds = bakedEntity.GetAllIds()
      if not lib.deepEqual(sourceIds, bakedIds) then
        io.write(("  DIVERGENCE %s GetAllIds: source %d ids, baked %d\n")
          :format(entityType.name, #sourceIds, #bakedIds))
        report.errors = report.errors + 1
      end

      local checkIds = sourceIds
      if opts.sample and #sourceIds > opts.sample then
        checkIds = {}
        local stride = math.floor(#sourceIds / opts.sample)
        for i = 1, #sourceIds, stride do checkIds[#checkIds + 1] = sourceIds[i] end
      end

      for _, id in ipairs(checkIds) do
        report.entities = report.entities + 1
        for fieldIndex = 1, meta.fieldCount do
          report.fields = report.fields + 1
          local sourceValue = sourceEntity.Get(id, fieldIndex)
          local bakedValue = bakedEntity.Get(id, fieldIndex)
          if not lib.deepEqual(sourceValue, bakedValue) then
            local kind = classify(sourceValue, bakedValue)
            report.byKind[kind] = (report.byKind[kind] or 0) + 1
            report.errors = report.errors + 1
            if report.errors <= MAX_REPORTED then
              io.write(("  DIVERGENCE [%s] %s %d field %d (%s)\n")
                :format(kind, entityType.name, id, fieldIndex, meta.names[fieldIndex]))
              io.write(("    source: %s\n"):format(lib.show(sourceValue):sub(1, 160)))
              io.write(("    baked:  %s\n"):format(lib.show(bakedValue):sub(1, 160)))
            elseif report.errors == MAX_REPORTED + 1 then
              io.write("  ... further divergences suppressed\n")
            end
          end
        end
      end

      -- An unknown ID must behave the same in both modes.
      local absentId = sourceIds[#sourceIds] + 1000000
      for fieldIndex = 1, meta.fieldCount do
        if sourceEntity.Get(absentId, fieldIndex) ~= bakedEntity.Get(absentId, fieldIndex) then
          io.write(("  DIVERGENCE %s unknown id, field %d (%s)\n")
            :format(entityType.name, fieldIndex, meta.names[fieldIndex]))
          report.errors = report.errors + 1
        end
      end
    end
  end

  if opts.freeze then
    local changed = freezeLib.audit()
    if changed > 0 then
      io.write(("  MUTATION %s: %d frozen tables were modified during the run\n"):format(flavor.name, changed))
      report.errors = report.errors + changed
    end
    freezeLib.reset()
  end

  local kinds = {}
  for kind, count in pairs(report.byKind) do kinds[#kinds + 1] = kind .. "=" .. count end
  table.sort(kinds)

  say(("[%s] %s: %d entities, %d fields, %d divergences%s, %.1fs")
    :format(report.errors == 0 and "PASS" or "FAIL", flavor.name, report.entities, report.fields,
            report.errors, #kinds > 0 and (" [" .. table.concat(kinds, " ") .. "]") or "",
            os.clock() - started))
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
  local errors, skipped = compareFlavor(flavor)
  totalErrors = totalErrors + errors
  if not skipped then checked = checked + 1 end
  collectgarbage()
end

if checked == 0 then
  io.write("equivalence: nothing to compare — no generated TOC found.\n")
  os.exit(1)
end

os.exit(totalErrors == 0 and 0 or 1)
