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
local client = dofile("emulator/client.lua")
local flavorLoader = dofile("generator/flavor.lua")
local freezeLib = dofile("emulator/freeze.lua")

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
  client.reset()
  client.install({ expansion = flavor.expansion })
  emulator.install(config.addonName, map)
  local LibQuestieDB = emulator.loadAddon(tocPath, config.addonName)
  if opts.freeze then freezeLib.install(LibQuestieDB) end

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

  -- No line may exceed what the client will actually read. Measured on Classic Era 1.15.9:
  -- `GetAddOnMetadata` silently truncates beyond lib.TOC_LINE_LIMIT and reports nothing, so
  -- an over-long line is data corruption with no symptom until a consumer reads a short
  -- value. This is the check that would have caught it: the emulator reads the file directly
  -- and never truncates, so nothing else offline can see the problem.
  do
    local overLimit, worst, worstKey = 0, 0, nil
    local file = assert(io.open(tocPath, "rb"))
    for line in file:lines() do
      line = line:gsub("\r$", "")
      if line:sub(1, 5) == "## X-" and #line > lib.TOC_LINE_LIMIT then
        overLimit = overLimit + 1
        if #line > worst then
          worst = #line
          worstKey = line:match("^## ([^:]+):")
        end
      end
    end
    file:close()
    if overLimit > 0 then
      io.write(("  LINE LIMIT %s: %d lines exceed %d bytes (worst %d, key %s) — the client " ..
        "will truncate these silently\n"):format(tocPath, overLimit, lib.TOC_LINE_LIMIT, worst,
        tostring(worstKey)))
      report.errors = report.errors + overLimit
    end
  end

  -- No stored value — whole or chunk part — may begin or end with a byte the client trims.
  -- Measured on Classic Era 1.15.9 (docs/client-metadata-probes.md §1): `GetAddOnMetadata`
  -- strips edge whitespace from every value, so an edge-whitespace part loses a byte during
  -- reassembly with no symptom offline. The emulator preserves those bytes, which is exactly
  -- why only this raw-file scan can see the problem.
  do
    local edgeWhitespace, exampleKey = 0, nil
    local file = assert(io.open(tocPath, "rb"))
    for line in file:lines() do
      line = line:gsub("\r$", "")
      if line:sub(1, 5) == "## X-" then
        local key, value = line:match("^## ([^:]+): (.*)$")
        if value and #value > 0 then
          local first, lastByte = value:byte(1), value:byte(#value)
          if lib.TRIMMABLE[first] or lib.TRIMMABLE[lastByte] then
            edgeWhitespace = edgeWhitespace + 1
            exampleKey = exampleKey or key
          end
        end
      end
    end
    file:close()
    if edgeWhitespace > 0 then
      io.write(("  EDGE WHITESPACE %s: %d stored values begin or end with a byte the client " ..
        "trims (first: %s) — reassembly loses those bytes in-client\n")
        :format(tocPath, edgeWhitespace, tostring(exampleKey)))
      report.errors = report.errors + edgeWhitespace
    end
  end

  local normalize = LibQuestieDB.Meta.normalize
  local seenKeys = {}

  -- The same corrected tables the generator wrote, so this checks the storage round trip
  -- rather than accidentally re-checking whether corrections were applied.
  local loadedFlavor = flavorLoader.load(flavor, opts.types)

  for _, entityType in ipairs(config.entityTypes) do
    if not opts.types or opts.types[entityType.name] then
      local entity = LibQuestieDB[entityType.name]
      local meta = LibQuestieDB.Meta[entityType.name]
      local sourceEntities = loadedFlavor[entityType.name].entities

      -- The ID list must round-trip in both forms consumers build from it. This reads the
      -- BACKEND's list, not `entity.GetAllIds()`: public enumeration is the composed view
      -- (ADR 0003 D7), which legitimately includes entities Dynamic Corrections add, while
      -- this check's subject is the stored artifact alone.
      local sourceIds = lib.sortedIds(sourceEntities)
      local storedList, storedMap = entity.backend.getAllIds()
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
          -- GetRaw bypasses the Correction Overlay: Dynamic Corrections are applied at
          -- runtime in both modes and are not part of what the artifact stores. Equivalence
          -- covers the composed path.
          local actual = entity.GetRaw(id, fieldIndex)
          report.fields = report.fields + 1
          if not lib.deepEqual(expected, actual) then
            reportMismatch(report, entityType.name, id, fieldIndex, meta.names[fieldIndex], expected, actual)
          end
          -- Named getter and generic getter must agree, both through the overlay.
          local named = entity[meta.names[fieldIndex]](id)
          local generic = entity.Get(id, fieldIndex)
          if not lib.deepEqual(generic, named) then
            reportMismatch(report, entityType.name, id, fieldIndex,
              meta.names[fieldIndex] .. " (named vs generic getter)", generic, named)
          end
          if encode.field(meta, fieldIndex, row[fieldIndex]) ~= nil then
            seenKeys["X-" .. meta.metaPrefix .. id .. "-" .. fieldIndex] = true
          end
         end
        end
      end

      -- An unknown entity ID reads as nil for every field — numeric defaults are gated on
      -- existence (ADR 0003 Decision 6), so a missing entity can never masquerade as a valid
      -- all-zero row. Checked through both the raw and the composed getter.
      local absentId = sourceIds[#sourceIds] + 1000000
      for fieldIndex = 1, meta.fieldCount do
       if not opts.fields or opts.fields[meta.names[fieldIndex]] then
        local value = entity.GetRaw(absentId, fieldIndex)
        if value ~= nil then
          io.write(("  MISMATCH %s unknown id %d field %d: expected nil, got %s\n")
            :format(entityType.name, absentId, fieldIndex, tostring(value)))
          report.errors = report.errors + 1
        end
        local composedValue = entity.Get(absentId, fieldIndex)
        if composedValue ~= nil then
          io.write(("  MISMATCH %s unknown id %d field %d (composed): expected nil, got %s\n")
            :format(entityType.name, absentId, fieldIndex, tostring(composedValue)))
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
      ["X-BUILD-COMMIT"] = true, ["X-BUILD-TIME"] = true, ["X-QUESTIE-COMMIT"] = true,
    }
    local orphans = 0
    for key in pairs(map) do
     -- Localization keys are verified separately, below.
     if not headerKeys[key] and not key:find("^X%-" .. config.l10nMetaPrefix) then
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

  if opts.freeze then
    local changed = freezeLib.audit()
    if changed > 0 then
      io.write(("  MUTATION %s: %d frozen tables were modified during the run\n"):format(tocPath, changed))
      report.errors = report.errors + changed
    end
    freezeLib.reset()
  end

  -- Localization: every stored value must split into the declared number of locale segments,
  -- and every segment must be non-empty or absent — an empty segment means "no translation"
  -- and the reader falls back, so a stray one is a silent English string in a German client.
  local l10nFields, l10nSegments = 0, 0
  local l10nGen = dofile("generator/l10n.lua")
  local listFieldByType = {}
  for typeName, typeCfg in pairs(l10nGen.types) do
    listFieldByType[typeName] = {}
    for fieldPos, fieldCfg in ipairs(typeCfg.fields) do
      if fieldCfg.list then listFieldByType[typeName][fieldPos] = true end
    end
  end
  local function splitLocales(joined)
    local segments, pos = {}, 1
    while true do
      local s, e = joined:find(config.localeSeparator, pos, true)
      if not s then
        segments[#segments + 1] = joined:sub(pos)
        return segments
      end
      segments[#segments + 1] = joined:sub(pos, s - 1)
      pos = e + 1
    end
  end
  for key, value in pairs(map) do
    -- `X-l10n-<Type>-<id>-<fieldIndex>`. A chunk part carries a fourth number and is skipped.
    local typeName, fieldPos = key:match("^X%-l10n%-(%a+)%-%d+%-(%d+)$")
    if typeName then
      l10nFields = l10nFields + 1
      local joined = emulator.getValue(map, key)
      local segments = splitLocales(joined)
      if #segments > #config.locales then
        io.write(("  L10N %s: %d locale segments, only %d locales declared\n")
          :format(key, #segments, #config.locales))
        report.errors = report.errors + 1
      end
      -- A list-valued field's segments are Lua table literals — the shape contract of
      -- ADR 0003 Decision 3. Every non-empty segment must decode to a table.
      if listFieldByType[typeName] and listFieldByType[typeName][tonumber(fieldPos)] then
        for i = 1, #segments do
          local segment = segments[i]
          if segment ~= "" then
            local chunk = loadstring("return " .. segment)
            local ok, decoded = false, nil
            if chunk then ok, decoded = pcall(chunk) end
            if not ok or type(decoded) ~= "table" then
              io.write(("  L10N %s segment %d does not decode to a table: %s\n")
                :format(key, i, segment:sub(1, 80)))
              report.errors = report.errors + 1
              break
            end
          end
        end
      end
    end
  end
  for _, entityType in ipairs(config.entityTypes) do
    if not opts.types or opts.types[entityType.name] then
      local entity = LibQuestieDB[entityType.name]
      local l10n = LibQuestieDB.l10n
      if entity and l10n and entity.HasL10nProvider and entity.HasL10nProvider() then
        for _, locale in ipairs(config.locales) do
          l10n.SetLocale(locale)
          local ids = entity.GetAllIds()
          local translated = 0
          for i = 1, math.min(#ids, 500) do
            local value = entity.Get(ids[i], "name")
            if type(value) == "string" and value ~= "" then translated = translated + 1 end
          end
          if translated == 0 then
            io.write(("  L10N %s/%s: no name resolved across 500 ids\n"):format(entityType.name, locale))
            report.errors = report.errors + 1
          end
          l10nSegments = l10nSegments + translated
        end
        l10n.SetLocale("enUS")
      end
    end
  end
  if l10nFields > 0 then
    say(("       l10n: %d stored values, %d segments resolved across %d locales")
      :format(l10nFields, l10nSegments, #config.locales))
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
