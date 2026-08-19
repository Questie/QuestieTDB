#!/usr/bin/env lua
-- generate.lua
--
-- Turns raw entity data plus Static Corrections into a TOC metadata store.
--
-- Usage:
--   lua generate.lua meta                 materialize src/meta/*Meta.lua from Questie's schema
--   lua generate.lua all                  every flavor
--   lua generate.lua Vanilla [TBC ...]    named flavors
--
-- Options:
--   --types=Quest,Npc      restrict entity types
--   --fields=name,zoneOrSort   restrict fields (tracer-bullet slices only)
--   --no-base-toc          skip rewriting the committed base TOC (parallel-safe)
--   --quiet
--
-- Runs on a plain Lua 5.1 interpreter. No `lfs`, no other C dependency — inputs are
-- enumerated in src/config.lua rather than discovered by scanning directories, which keeps
-- the option of shipping a bare `lua` binary for contributors.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")
local schema = dofile("generator/schema.lua")
local encode = dofile("generator/encode.lua")
local corrections = dofile("generator/corrections.lua")
local flavorLoader = dofile("generator/flavor.lua")
local l10nGen = dofile("generator/l10n.lua")

-- The correction manifest drives which files each TOC lists. It is optional: a bare data
-- round-trip works before any corrections are ported.
if lib.fileExists("src/corrections/manifest.lua") then
  config.correctionManifest = dofile("src/corrections/manifest.lua")
end

local generate = {}

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

local function parseArgs(argv)
  local opts = { flavors = {}, types = nil, fields = nil, quiet = false, target = nil }
  for _, value in ipairs(argv) do
    local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
    if key == "types" then
      opts.types = {}
      for name in val:gmatch("[^,]+") do opts.types[name] = true end
    elseif key == "fields" then
      opts.fields = {}
      for name in val:gmatch("[^,]+") do opts.fields[name] = true end
    elseif key == "questie" then
      opts.questie = val
    elseif value == "--no-l10n" then
      opts.noL10n = true
    elseif value == "--no-base-toc" then
      opts.noBaseToc = true
    elseif value == "--quiet" then
      opts.quiet = true
    elseif value:sub(1, 2) == "--" then
      error("Unknown option: " .. value, 0)
    elseif value == "meta" or value == "all" or value == "toc" then
      opts.target = value
    else
      opts.flavors[#opts.flavors + 1] = value
    end
  end
  return opts
end

local QUIET = false
local function say(...)
  if not QUIET then print(...) end
end

--------------------------------------------------------------------------------------------
-- Schema materialization
--------------------------------------------------------------------------------------------

--- Derive the schema from Questie's `*Keys` and `*CompilerTypes` and write src/meta/*Meta.lua.
---
--- Questie's schema files are the only source of `*CompilerTypes`, and they die with the
--- compiler. Materializing captures the type map before it disappears; the key enum keeps
--- deriving afterwards because every data file carries its own copy.
function generate.materializeMeta(questiePath)
  questiePath = questiePath or "../Questie"
  lib.mkdirp("src/meta")

  for _, entityType in ipairs(config.entityTypes) do
    local schemaFile = questiePath .. "/Database/" .. entityType.name:lower() .. "DB.lua"
    if not lib.fileExists(schemaFile) then
      error("Cannot derive schema: " .. schemaFile .. " not found. Pass the path to a Questie " ..
            "checkout as the second argument.", 0)
    end
    local keys, compilerTypes = loader.loadSchemaFile(schemaFile, entityType, { isClassic = true, expansion = 1 })
    local meta = schema.derive(entityType, keys, compilerTypes)

    -- Cross-check against every flavor's data file, since the key enum travels with the data.
    for _, flavor in ipairs(config.flavors) do
      local dataPath = config.dataPath(flavor, entityType)
      if lib.fileExists(dataPath) then
        local entities, dataKeys = loader.loadEntityData(dataPath, entityType)
        local omitted = schema.checkKeys(meta, dataKeys, dataPath)
        schema.assertNoDataBeyondKeys(meta, entities, dataKeys, dataPath)
        for name, index in pairs(omitted) do
          say(string.format("  note: %s omits '%s' (field %d) — no row in that file uses it",
            dataPath, name, index))
        end
      end
    end

    local path = schema.metaPath(entityType)
    lib.writeAll(path, schema.render(meta))
    say(string.format("Materialized %s (%d fields)", path, meta.fieldCount))
  end
end

--------------------------------------------------------------------------------------------
-- TOC emission
--------------------------------------------------------------------------------------------

local BUILD

local function writeHeader(out, flavor, fileList)
  out:write("# GENERATED by `lua generate.lua ", flavor.name, "`. Do not edit, do not commit.\n")
  out:write("# Baked mode: entity reads resolve from the TOC metadata store below.\n")
  out:write("## Interface: ", flavor.interface, "\n")
  out:write("## Title: QuestieTDB\n")
  out:write("## Notes: The database Questie consumes.\n")
  out:write("## Author: Questie contributors\n")
  out:write("## Version: 0.0.0\n")
  out:write("## X-Contract-Version: ", tostring(config.contractVersion), "\n")
  out:write("## X-Flavor: ", flavor.name, "\n")
  out:write("## X-Mode: baked\n")
  out:write("## X-BUILD-COMMIT: ", BUILD.commit, "\n")
  out:write("## X-BUILD-TIME: ", BUILD.time, "\n")
  out:write("\n")
  for _, file in ipairs(fileList) do
    out:write(file:gsub("/", "\\"), "\n")
  end
  out:write("\n")
end

--- Write the committed base TOC, which is what the client falls back to when no suffixed TOC
--- matches — and therefore what selects Source mode, at no cost.
function generate.baseToc()
  local path = config.addonName .. ".toc"
  local out = assert(io.open(path, "wb"), "Cannot write " .. path)
  out:write("# GENERATED by `lua generate.lua toc`, and COMMITTED.\n")
  out:write("# Source mode: entity reads resolve from raw entity data in data/.\n")
  out:write("#\n")
  out:write("# The client searches for flavour-suffixed TOCs first and uses this one only if\n")
  out:write("# none are found, so a generated artifact wins simply by existing. A fresh clone\n")
  out:write("# has no suffixed TOC, which is what makes it a working dev environment.\n")
  out:write("## Interface: ", config.allInterfaceVersions(), "\n")
  out:write("## Title: QuestieTDB |cFFFFD100(source mode)|r\n")
  out:write("## Notes: The database Questie consumes. No generated artifact present.\n")
  out:write("## Author: Questie contributors\n")
  out:write("## Version: 0.0.0\n")
  out:write("## X-Contract-Version: ", tostring(config.contractVersion), "\n")
  out:write("## X-Mode: source\n")
  out:write("\n")
  for _, file in ipairs(config.sourceFileList()) do
    out:write(file:gsub("/", "\\"), "\n")
  end
  out:close()
  say(string.format("Generated %s (%d files, source mode)", path, #config.sourceFileList()))
end

--- Emit every metadata line for one entity type.
---@return number entityCount
---@return number fieldCount
---@return number lineCount
local function writeEntityMetadata(out, meta, entities, fieldFilter)
  local ids = lib.sortedIds(entities)
  local fieldCount, lineCount = 0, 0
  local prefix = "X-" .. meta.metaPrefix

  for _, id in ipairs(ids) do
    local row = entities[id]
    local key = prefix .. id .. "-"
    for fieldIndex = 1, meta.fieldCount do
      if not fieldFilter or fieldFilter[meta.names[fieldIndex]] then
        local ok, encoded = pcall(encode.field, meta, fieldIndex, row[fieldIndex])
        if not ok then
          error(string.format("%s id %d: %s", meta.entity, id, tostring(encoded)), 0)
        end
        if encoded ~= nil then
          lineCount = lineCount + lib.writeMetadata(out, key .. fieldIndex, encoded, config.maxValueLength)
          fieldCount = fieldCount + 1
        end
      end
    end
  end

  lineCount = lineCount + lib.writeMetadata(out, prefix .. "IDS-LIST", encode.idList(ids), config.maxValueLength)
  return #ids, fieldCount, lineCount
end

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

--- Load every entity type for one flavor, apply Static Corrections, and return the tables.
--- Shared with verify.lua so both see identical corrected data.
function generate.loadFlavor(flavor, typeFilter, applyCorrections)
  return flavorLoader.load(flavor, typeFilter, applyCorrections)
end

function generate.flavor(flavor, opts)
  local started = os.clock()
  local loaded, stats = generate.loadFlavor(flavor, opts.types)
  if stats.applied > 0 then
    say(string.format("  corrections: %d values from %d registered functions across %d files",
      stats.applied, stats.corrections and stats.corrections.registered or 0,
      stats.corrections and stats.corrections.files or 0))
  end

  local tocPath = config.tocPath(flavor)
  local out = assert(io.open(tocPath, "wb"), "Cannot write " .. tocPath)
  writeHeader(out, flavor, config.bakedFileList(flavor))

  local totals = { entities = 0, fields = 0, lines = 0 }
  for _, entityType in ipairs(config.entityTypes) do
    local entry = loaded[entityType.name]
    if entry then
      local entities, fields, lines = writeEntityMetadata(out, entry.meta, entry.entities, opts.fields)
      totals.entities = totals.entities + entities
      totals.fields = totals.fields + fields
      totals.lines = totals.lines + lines
      say(string.format("  %-7s %6d entities  %8d fields", entityType.name, entities, fields))
    end
  end

  out:close()

  -- Localization, appended after entity data. It is ~72% of the artifact, and it lives in the
  -- same store rather than a separate addon because TOC metadata is client-side storage, not
  -- Lua heap: a German user never touches the other eight locales' strings.
  if not opts.noL10n then
    local questiePath = opts.questie or "../Questie"
    if lib.fileExists(questiePath .. "/Localization/lookups/" .. flavor.expansion) then
      out = assert(io.open(tocPath, "ab"), "Cannot append to " .. tocPath)
      for _, entityType in ipairs(config.entityTypes) do
        local entry = loaded[entityType.name]
        if entry then
          local knownIds = {}
          for id in pairs(entry.entities) do knownIds[id] = true end
          local values, stats = l10nGen.extract(questiePath, flavor, entityType.name, knownIds)
          local entries, fields = l10nGen.writeMetadata(out, entityType.name, values)
          totals.l10nEntries = (totals.l10nEntries or 0) + entries
          totals.l10nFields = (totals.l10nFields or 0) + fields
          say(string.format("  l10n %-7s %6d entities  %8d fields  (%d locales, %d filtered)",
            entityType.name, entries, fields, stats.locales, stats.filtered))
          values = nil
          collectgarbage()
        end
      end
      out:close()
    else
      say("  l10n: skipped, no Questie lookup tree at " .. questiePath)
    end
  end

  local size = #lib.readAll(tocPath)
  say(string.format("Generated %s — %d entities, %d fields, %.1f MB, %.1fs",
    tocPath, totals.entities, totals.fields, size / 1048576, os.clock() - started))
  return totals
end

--------------------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------------------

local opts = parseArgs(arg or {})
QUIET = opts.quiet
BUILD = { commit = lib.gitCommit(), time = lib.buildTime() }

if opts.target == "meta" then
  generate.materializeMeta(opts.flavors[1])
  os.exit(0)
end

if opts.target == "toc" then
  generate.baseToc()
  os.exit(0)
end

local flavors = {}
if opts.target == "all" or #opts.flavors == 0 then
  flavors = config.flavors
else
  for _, name in ipairs(opts.flavors) do
    local flavor = config.flavorByName[name]
    if not flavor then
      error("Unknown flavor: " .. name .. ". Known: Vanilla, TBC, Wrath, Cata, Mists", 0)
    end
    flavors[#flavors + 1] = flavor
  end
end

-- The base TOC is not flavour-scoped, so every invocation would rewrite the same file. That is
-- harmless sequentially and a race when flavours are generated in parallel (tools/check.sh),
-- which writes it once up front and then passes --no-base-toc.
if not opts.noBaseToc then
  generate.baseToc()
end

for _, flavor in ipairs(flavors) do
  generate.flavor(flavor, opts)
end
