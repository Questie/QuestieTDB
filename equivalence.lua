#!/usr/bin/env lua
-- equivalence.lua
--
-- Proof that what a contributor sees in Source mode is exactly what ships in Baked mode.
--
-- This is the load-bearing test in the system. Unlike the compiled/TOC differential it never
-- retires: two permanent read modes mean it guards forever. Both readers are stood up in one
-- process, over the real `src/` files, and every entity and every field is compared — through
-- every public read form, not just `Get`:
--
--   * `Get` and `GetRaw`, by field index for every id, and by field name on a deterministic
--     id sample (the two spellings share a lookup, so the sample guards the mapping while the
--     index sweep guards the values).
--   * `GetProvenance` — a Dynamic Correction must be attributed identically in both modes.
--   * Unknown and invalid ids: nil everywhere, `Exists` false, `GetAll` nil, and no read form
--     may raise (ADR 0003 D6).
--   * Fresh-per-read value ownership: two reads return distinct tables with equal content,
--     and mutating one never reaches the next (ADR 0003 D10).
--   * Composed enumeration: an entity added by a runtime Dynamic Correction is readable,
--     enumerable and existing in both modes, and withdrawal removes all three (ADR 0003 D7).
--   * Baked localization shape: every locale's segment of every localized field decodes, and
--     list-typed fields remain tables (ADR 0003 D3). Source mode deliberately has no l10n
--     store, so this is a baked-side invariant sweep; the cross-mode comparison itself runs
--     under enUS, where both modes read base data.
--   * A season pass for Classic: with Season of Discovery active in both modes, the SoD
--     Dynamic sets must register and compose identically (ADR 0003 D9).
--
-- The gate then proves it can fail: one stored value is deliberately mutated in the baked
-- map, the mutated id is re-compared through the same comparison code, and exactly one
-- divergence must be detected. Equivalence that cannot fail is not a gate.
--
-- Usage:
--   lua equivalence.lua                     every generated flavor
--   lua equivalence.lua Vanilla
--   lua equivalence.lua --sample=2000       a representative subset per entity type
--   lua equivalence.lua --toc-dir=.out/x    read artifacts from elsewhere
--   lua equivalence.lua --no-self-proof     skip the sensitivity check (negative controls)
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
  local opts = { flavors = {}, types = nil, sample = nil, quiet = false, tocDir = ".",
                 selfProof = true }
  for _, value in ipairs(argv or {}) do
    local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
    if key == "types" then
      opts.types = {}
      for name in val:gmatch("[^,]+") do opts.types[name] = true end
    elseif key == "sample" then
      opts.sample = tonumber(val)
    elseif key == "toc-dir" then
      opts.tocDir = val
    elseif key == "baked-root" then
      opts.bakedRoot = val
    elseif value == "--freeze" then
      opts.freeze = true
    elseif value == "--no-self-proof" then
      opts.selfProof = false
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
-- Reporting
--------------------------------------------------------------------------------------------

local function diverge(report, kind, format, ...)
  report.byKind[kind] = (report.byKind[kind] or 0) + 1
  report.errors = report.errors + 1
  if report.silent then return end
  if report.errors <= MAX_REPORTED then
    io.write("  DIVERGENCE ", format:format(...), "\n")
  elseif report.errors == MAX_REPORTED + 1 then
    io.write("  ... further divergences suppressed\n")
  end
end

local function compareValues(report, kindPrefix, sourceValue, bakedValue, format, ...)
  if lib.deepEqual(sourceValue, bakedValue) then return true end
  local kind = classify(sourceValue, bakedValue)
  local where = format:format(...)
  diverge(report, kindPrefix .. kind, "[%s] %s\n    source: %s\n    baked:  %s",
    kind, where, lib.show(sourceValue):sub(1, 160), lib.show(bakedValue):sub(1, 160))
  return false
end

--------------------------------------------------------------------------------------------
-- Loading both modes
--------------------------------------------------------------------------------------------

local function loadSourceMode(flavor, clientOpts)
  client.reset()
  clientOpts = clientOpts or {}
  clientOpts.expansion = flavor.expansion
  client.install(clientOpts)
  local Lib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
  if opts.freeze then freezeLib.install(Lib) end
  return Lib
end

--- `mutate(map)` may alter the parsed metadata before install — the self-proof's injection
--- point, at the data level rather than a wrapper over the comparison's own calls.
---
--- `--baked-root=<dir>` resolves the TOC's file list against another root, so the baked side
--- can be an unpacked release package — the runtime a user installs, static-stripped by
--- tools/strip-static.lua — while source mode keeps reading the working tree.
local function loadBakedMode(tocPath, clientOpts, mutate)
  client.reset()
  client.install(clientOpts or {})
  local map = emulator.parse(tocPath)
  if mutate then mutate(map) end
  emulator.install(config.addonName, map)
  local Lib = emulator.loadAddon(tocPath, config.addonName, opts.bakedRoot)
  if opts.freeze then freezeLib.install(Lib) end
  return Lib
end

--------------------------------------------------------------------------------------------
-- Per-entity comparison pieces
--------------------------------------------------------------------------------------------

--- The core sweep: every field of every given id, through Get and GetRaw by index.
local function compareIdRange(report, entityName, sourceEntity, bakedEntity, meta, ids)
  for _, id in ipairs(ids) do
    report.entities = report.entities + 1
    for fieldIndex = 1, meta.fieldCount do
      report.fields = report.fields + 1
      compareValues(report, "", sourceEntity.Get(id, fieldIndex), bakedEntity.Get(id, fieldIndex),
        "%s %d field %d (%s)", entityName, id, fieldIndex, meta.names[fieldIndex])
      compareValues(report, "RAW-", sourceEntity.GetRaw(id, fieldIndex), bakedEntity.GetRaw(id, fieldIndex),
        "GetRaw %s %d field %d (%s)", entityName, id, fieldIndex, meta.names[fieldIndex])
    end
  end
end

--- Field-name spelling and provenance, on a deterministic sample: the name→index mapping and
--- the provenance table are shared per type, so a stride sample guards them completely.
local function compareNamedForms(report, Lib, entityName, sourceEntity, bakedEntity, meta, ids)
  local sourceLib, bakedLib = Lib.source, Lib.baked
  local stride = math.max(1, math.floor(#ids / 50))
  for i = 1, #ids, stride do
    local id = ids[i]
    for fieldIndex = 1, meta.fieldCount do
      local name = meta.names[fieldIndex]
      compareValues(report, "NAME-", sourceEntity.Get(id, name), bakedEntity.Get(id, name),
        "%s %d by name %s", entityName, id, name)
      compareValues(report, "NAME-RAW-", sourceEntity.GetRaw(id, name), bakedEntity.GetRaw(id, name),
        "GetRaw %s %d by name %s", entityName, id, name)
      local sourceOwner = sourceLib.GetProvenance(entityName, id, name)
      local bakedOwner = bakedLib.GetProvenance(entityName, id, name)
      if sourceOwner ~= bakedOwner then
        diverge(report, "PROVENANCE", "%s %d %s provenance: source %s, baked %s",
          entityName, id, name, tostring(sourceOwner), tostring(bakedOwner))
      end
    end
  end
end

--- Unknown and invalid ids behave identically — nil everywhere, never an error (ADR D6).
local function compareUnknownIds(report, entityName, sourceEntity, bakedEntity, meta, ids)
  local absentId = (ids[#ids] or 0) + 1000000
  for fieldIndex = 1, meta.fieldCount do
    compareValues(report, "UNKNOWN-", sourceEntity.Get(absentId, fieldIndex),
      bakedEntity.Get(absentId, fieldIndex),
      "%s unknown id field %d (%s)", entityName, fieldIndex, meta.names[fieldIndex])
  end
  for _, probe in ipairs({
    { "Exists(unknown)", sourceEntity.Exists(absentId), bakedEntity.Exists(absentId), false },
    { "GetAll(unknown)", sourceEntity.GetAll(absentId, { meta.names[1] }),
                         bakedEntity.GetAll(absentId, { meta.names[1] }), nil },
    { "GetRaw(unknown)", sourceEntity.GetRaw(absentId, 1), bakedEntity.GetRaw(absentId, 1), nil },
  }) do
    local label, sourceValue, bakedValue, expected = probe[1], probe[2], probe[3], probe[4]
    if sourceValue ~= expected or bakedValue ~= expected then
      diverge(report, "UNKNOWN-CONTRACT", "%s %s: expected %s, source %s, baked %s",
        entityName, label, tostring(expected), tostring(sourceValue), tostring(bakedValue))
    end
  end
  for _, badCall in ipairs({
    function(entity) return entity.Get(nil, 1) end,
    function(entity) return entity.Get("2", meta.names[1]) end,
    function(entity) return entity.GetRaw(nil, 1) end,
    function(entity) return entity.Get(ids[1], meta.fieldCount + 40) end,
    function(entity) return entity.GetRaw(ids[1], -5) end,
    function(entity) return entity.GetRaw(ids[1], "no-such-field") end,
  }) do
    local sourceOk, sourceValue = pcall(badCall, sourceEntity)
    local bakedOk, bakedValue = pcall(badCall, bakedEntity)
    if not sourceOk or not bakedOk or sourceValue ~= nil or bakedValue ~= nil then
      diverge(report, "INVALID-CALL", "%s invalid call: source %s/%s, baked %s/%s",
        entityName, tostring(sourceOk), tostring(sourceValue), tostring(bakedOk), tostring(bakedValue))
    end
  end
end

--- Fresh-per-read ownership (ADR D10), on the first id that has a table-valued field.
local function compareOwnership(report, entityName, entities, meta, ids)
  for _, id in ipairs(ids) do
    for fieldIndex = 1, meta.fieldCount do
      for label, entity in pairs(entities) do
        local first = entity.Get(id, fieldIndex)
        if type(first) == "table" then
          local second = entity.Get(id, fieldIndex)
          if first == second then
            diverge(report, "OWNERSHIP", "%s %s %d field %d: two reads returned the same table",
              label, entityName, id, fieldIndex)
          elseif not lib.deepEqual(first, second) then
            diverge(report, "OWNERSHIP", "%s %s %d field %d: fresh copies differ in content",
              label, entityName, id, fieldIndex)
          else
            -- A never-nil structure legitimately reads back as `{}` (ADR 0004), so there may be
            -- no existing key to overwrite; `next` would then index with nil and raise.
            local existingKey = next(first)
            if existingKey ~= nil then first[existingKey] = "equivalence scribble" end
            first.__scribble = true
            if not lib.deepEqual(entity.Get(id, fieldIndex), second) then
              diverge(report, "OWNERSHIP", "%s %s %d field %d: a caller mutation reached a later read",
                label, entityName, id, fieldIndex)
            end
          end
        end
      end
      -- One table-valued field per type is enough: every table field shares the producer path.
      -- It has to be a POPULATED one, or the check would settle for an empty never-nil field
      -- and never exercise a real value's copy semantics.
      local raw = entities.source.GetRaw(id, fieldIndex)
      if type(raw) == "table" and next(raw) ~= nil then return end
    end
  end
end

--- Composed enumeration (ADR D7): a runtime Dynamic add is first-class in both modes.
local function compareComposedAdd(report, Lib, entityName, sourceEntity, bakedEntity, ids)
  local addedId = (ids[#ids] or 0) + 2000000
  local owner = "EquivalenceGate"
  for _, libSide in pairs({ Lib.source, Lib.baked }) do
    libSide.Corrections.RegisterRuntimeCorrection(owner, entityName, "equiv-add",
      function() return { [addedId] = { [1] = "Equivalence Added" } } end, 10)
    libSide.Corrections.ApplyRegisteredCorrections(owner)
  end

  compareValues(report, "COMPOSED-", sourceEntity.Get(addedId, 1), bakedEntity.Get(addedId, 1),
    "%s added id read", entityName)
  if not (sourceEntity.Exists(addedId) and bakedEntity.Exists(addedId)) then
    diverge(report, "COMPOSED-EXISTS", "%s added id exists: source %s, baked %s",
      entityName, tostring(sourceEntity.Exists(addedId)), tostring(bakedEntity.Exists(addedId)))
  end
  local sourceMap, bakedMap = sourceEntity.GetAllIds(true), bakedEntity.GetAllIds(true)
  if sourceMap[addedId] ~= true or bakedMap[addedId] ~= true then
    diverge(report, "COMPOSED-MAP", "%s added id in hashmap: source %s, baked %s",
      entityName, tostring(sourceMap[addedId]), tostring(bakedMap[addedId]))
  end
  -- Content comparison, never identity: the no-additions fast path aliases backend tables by
  -- design, and after withdrawal both modes are back on it.
  if not lib.deepEqual(sourceEntity.GetAllIds(), bakedEntity.GetAllIds()) then
    diverge(report, "COMPOSED-LIST", "%s id lists diverge while the add is applied", entityName)
  end

  for _, libSide in pairs({ Lib.source, Lib.baked }) do
    libSide.Corrections.UnregisterCorrection(owner, entityName, "equiv-add")
    libSide.Corrections.ApplyRegisteredCorrections(owner)
  end
  if sourceEntity.Exists(addedId) or bakedEntity.Exists(addedId) then
    diverge(report, "COMPOSED-WITHDRAW", "%s added id survived withdrawal", entityName)
  end
  if not lib.deepEqual(sourceEntity.GetAllIds(), bakedEntity.GetAllIds()) then
    diverge(report, "COMPOSED-LIST", "%s id lists diverge after withdrawal", entityName)
  end
end

--- Baked l10n shape (ADR D3): every locale's segment decodes and keeps the field's type.
--- Source mode has no l10n store by design, so this is a baked-side invariant rather than a
--- cross-mode comparison. Legitimate locale-specific element counts are reported separately.
local function checkBakedL10nShape(report, bakedLib, entityName, bakedEntity, meta, ids)
  local l10n = bakedLib.l10n
  local typeFields = l10n.fields[entityName]
  if not typeFields or not bakedEntity.HasL10nProvider() then return 0 end

  local checked = 0
  local baseCounts, baseKinds = {}, {}
  for _, fieldCfg in ipairs(typeFields) do
    local fieldIndex = meta.keys[fieldCfg.name]
    baseCounts[fieldCfg.name], baseKinds[fieldCfg.name] = {}, {}
    for _, id in ipairs(ids) do
      local base = bakedEntity.Get(id, fieldIndex)
      baseKinds[fieldCfg.name][id] = type(base)
      if fieldCfg.list and type(base) == "table" then
        baseCounts[fieldCfg.name][id] = #base
      end
    end
  end

  for _, locale in ipairs(l10n.locales) do
    l10n.SetLocale(locale)
    for _, fieldCfg in ipairs(typeFields) do
      local fieldIndex = meta.keys[fieldCfg.name]
      for _, id in ipairs(ids) do
        checked = checked + 1
        local ok, value = pcall(bakedEntity.Get, id, fieldIndex)
        if not ok then
          diverge(report, "L10N-DECODE", "%s %d %s under %s raised: %s",
            entityName, id, fieldCfg.name, locale, tostring(value):sub(1, 120))
        elseif value ~= nil and type(value) ~= baseKinds[fieldCfg.name][id] and
               baseKinds[fieldCfg.name][id] ~= "nil" then
          diverge(report, "L10N-TYPE", "%s %d %s under %s is a %s, base is a %s",
            entityName, id, fieldCfg.name, locale, type(value), baseKinds[fieldCfg.name][id])
        elseif fieldCfg.list and type(value) == "table" and
               baseCounts[fieldCfg.name][id] and #value ~= baseCounts[fieldCfg.name][id] then
          -- Not a divergence: upstream lookups legitimately carry a different element count
          -- (zhCN/zhTW combine objectives into one string), and preserving the lookup's own
          -- shape is what Questie ships today. Counted so the summary shows the scale; byte
          -- fidelity against the extraction is reconstruct.lua's job.
          report.l10nShapeVaries = (report.l10nShapeVaries or 0) + 1
        end
      end
    end
  end
  l10n.SetLocale("enUS")
  return checked
end

--------------------------------------------------------------------------------------------
-- Flavor comparison
--------------------------------------------------------------------------------------------

local function sampleIds(sourceIds)
  if not opts.sample or #sourceIds <= opts.sample then return sourceIds end
  local checkIds = {}
  local stride = math.floor(#sourceIds / opts.sample)
  for i = 1, #sourceIds, stride do checkIds[#checkIds + 1] = sourceIds[i] end
  return checkIds
end

--- One full cross-mode comparison. `label` names the pass; `clientOpts` selects the persona.
local function comparePass(report, flavor, tocPath, label, clientOpts, idStride)
  local sourceLib = loadSourceMode(flavor, clientOpts and { faction = clientOpts.faction,
    season = clientOpts.season } or nil)
  local bakedLib = loadBakedMode(tocPath, clientOpts)

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
  if bakedLib.l10n.currentLocale ~= "enUS" then
    io.write("  ERROR: cross-mode sweep must run under enUS\n")
    report.errors = report.errors + 1
  end

  local Lib = { source = sourceLib, baked = bakedLib }

  for _, entityType in ipairs(config.entityTypes) do
    if not opts.types or opts.types[entityType.name] then
      local sourceEntity = sourceLib[entityType.name]
      local bakedEntity = bakedLib[entityType.name]
      local meta = bakedLib.Meta[entityType.name]

      local sourceIds = sourceEntity.GetAllIds()
      if not lib.deepEqual(sourceIds, bakedEntity.GetAllIds()) then
        diverge(report, "IDS", "%s GetAllIds: source %d ids, baked %d",
          entityType.name, #sourceIds, #bakedEntity.GetAllIds())
      end
      if not lib.deepEqual(sourceEntity.GetAllIds(true), bakedEntity.GetAllIds(true)) then
        diverge(report, "IDS-MAP", "%s GetAllIds(true) hashmaps differ", entityType.name)
      end

      local checkIds = sampleIds(sourceIds)
      if idStride and idStride > 1 then
        local strided = {}
        for i = 1, #checkIds, idStride do strided[#strided + 1] = checkIds[i] end
        checkIds = strided
      end

      compareIdRange(report, entityType.name, sourceEntity, bakedEntity, meta, checkIds)
      compareNamedForms(report, Lib, entityType.name, sourceEntity, bakedEntity, meta, checkIds)
      compareUnknownIds(report, entityType.name, sourceEntity, bakedEntity, meta, sourceIds)

      if not idStride then
        compareOwnership(report, entityType.name,
          { source = sourceEntity, baked = bakedEntity }, meta, checkIds)
        compareComposedAdd(report, Lib, entityType.name, sourceEntity, bakedEntity, sourceIds)
        report.l10nChecked = (report.l10nChecked or 0) +
          checkBakedL10nShape(report, bakedLib, entityType.name, bakedEntity, meta, checkIds)
      end
    end
  end

  if opts.freeze then
    local changed = freezeLib.audit()
    if changed > 0 then
      io.write(("  MUTATION %s: %d frozen tables were modified during the run\n"):format(label, changed))
      report.errors = report.errors + changed
    end
    freezeLib.reset()
  end

  return sourceLib, bakedLib
end

--- The sensitivity self-proof: mutate one stored value at the data level, re-compare that id
--- through the same comparison code, and require exactly one divergence.
local function selfProof(flavor, tocPath)
  local mutatedKey, mutatedId
  local function mutate(map)
    -- The first quest whose name is stored unchunked: mutate the stored bytes themselves.
    for key, value in pairs(map) do
      local id = key:match("^X%-Quest%-(%d+)%-1$")
      if id and not value:find("^~") then
        if not mutatedId or tonumber(id) < mutatedId then
          mutatedId, mutatedKey = tonumber(id), key
        end
      end
    end
    assert(mutatedKey, "self-proof found no unchunked quest name to mutate")
    map[mutatedKey] = map[mutatedKey] .. "X"
  end

  -- Source first, then the mutated baked map — same order as every comparison pass, so no
  -- installed-metadata accessor is left behind when source mode loads.
  local sourceLib = loadSourceMode(flavor)

  client.reset()
  client.install({})
  local map = emulator.parse(tocPath)
  mutate(map)
  emulator.install(config.addonName, map)
  local bakedLib = emulator.loadAddon(tocPath, config.addonName, opts.bakedRoot)

  -- The divergences this pass finds are the injected ones — expected, so not reported.
  local report = { errors = 0, fields = 0, entities = 0, byKind = {}, silent = true }
  local meta = bakedLib.Meta.Quest
  compareIdRange(report, "Quest", sourceLib.Quest, bakedLib.Quest, meta, { mutatedId })

  -- One mutation, two read forms: the sweep checks every field through Get AND GetRaw, so the
  -- injected divergence must be detected exactly once per form and nowhere else.
  if report.errors ~= 2 or (report.byKind.STRING or 0) ~= 1 or (report.byKind["RAW-STRING"] or 0) ~= 1 then
    io.write(("  SELF-PROOF FAILED: injected one string mutation at %s, detected %d divergences\n")
      :format(tostring(mutatedKey), report.errors))
    return 1
  end
  return 0
end

local function compareFlavor(flavor)
  local tocPath = (opts.tocDir or ".") .. "/" .. config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    say(("[SKIP] %s: %s not generated"):format(flavor.name, tocPath))
    return 0, true
  end

  local started = os.clock()
  local report = { errors = 0, fields = 0, entities = 0, byKind = {} }

  comparePass(report, flavor, tocPath, flavor.name, nil, nil)

  -- The season pass: SoD is a Dynamic Correction set over Era, so with the season active the
  -- composed view must still be identical across modes — including the entities the SoD base
  -- sets add. A strided sweep suffices: the full sweep above already proved the base data, so
  -- this pass exists to prove the *gated* layer composes identically.
  local seasonChecks = 0
  if flavor.expansion == "Classic" then
    local before = report.entities
    local seasonReport = { errors = 0, fields = 0, entities = 0, byKind = {} }
    local sourceLib = comparePass(seasonReport, flavor, tocPath, flavor.name .. "+SoD",
      { season = "SoD" }, 7)
    report.errors = report.errors + seasonReport.errors
    for kind, count in pairs(seasonReport.byKind) do
      report.byKind[kind] = (report.byKind[kind] or 0) + count
    end
    seasonChecks = seasonReport.fields
    report.fields = report.fields + seasonReport.fields
    report.entities = before + seasonReport.entities

    -- The gate must actually have engaged: an active season registers SoD Dynamic sets.
    local sodEntries = 0
    for _, entry in ipairs(sourceLib.Corrections.Select({ dynamic = true })) do
      if entry.name:find("^Sod/") then sodEntries = sodEntries + 1 end
    end
    if sodEntries == 0 then
      io.write("  ERROR: season pass registered no SoD correction sets\n")
      report.errors = report.errors + 1
    end
  end

  local proofFailures = 0
  if opts.selfProof then
    proofFailures = selfProof(flavor, tocPath)
    report.errors = report.errors + proofFailures
  end

  local kinds = {}
  for kind, count in pairs(report.byKind) do kinds[#kinds + 1] = kind .. "=" .. count end
  table.sort(kinds)

  say(("[%s] %s: %d entities, %d fields, %d l10n reads (%d locale-shaped), %d season fields, %d divergences%s%s, %.1fs")
    :format(report.errors == 0 and "PASS" or "FAIL", flavor.name, report.entities, report.fields,
            report.l10nChecked or 0, report.l10nShapeVaries or 0, seasonChecks, report.errors,
            #kinds > 0 and (" [" .. table.concat(kinds, " ") .. "]") or "",
            opts.selfProof and (proofFailures == 0 and ", self-proof ok" or ", SELF-PROOF FAILED") or "",
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
