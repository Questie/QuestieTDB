#!/usr/bin/env lua
-- reconstruct.lua
--
-- Byte-exact reconstruction of an artifact's metadata store, independently of generation.
--
-- The round-trip verifier (`verify.lua`) proves the stored bytes DECODE to the source values;
-- the CI determinism check proves regenerating yields the same SHA. This gate closes the gap
-- between them: it re-derives every `## X-` data directive the current generator code would
-- emit — same loaders, same corrections, same encoders, same chunking — and compares the
-- result against the artifact on disk line by line, in order, as exact bytes. A mismatch is
-- localized to a named key instead of a differing checksum, and an artifact produced by
-- older or dirty generator code fails loudly even when it decodes correctly.
--
-- The emission loops below deliberately mirror `generate.lua`'s writeEntityMetadata and l10n
-- append. If generation's emission ever changes shape without this file following, the gate
-- fails against a freshly generated artifact — which is the alarm working, not a nuisance.
--
-- Usage:
--   lua reconstruct.lua                 Vanilla
--   lua reconstruct.lua Cata Mists     named flavors
--   lua reconstruct.lua --toc-dir=.out/x --questie=../Questie --count-only --quiet
--
-- `--count-only` prints a single number (the mismatch count) for negative-control harnesses.
-- Exits non-zero on any mismatch.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local encode = dofile("generator/encode.lua")
local flavorLoader = dofile("generator/flavor.lua")
local l10nGen = dofile("generator/l10n.lua")

if lib.fileExists("src/corrections/manifest.lua") then
  config.correctionManifest = dofile("src/corrections/manifest.lua")
end

local MAX_REPORTED = 10

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

local opts = { flavors = {}, tocDir = ".", questie = "../Questie", quiet = false, countOnly = false }
for _, value in ipairs(arg or {}) do
  local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
  if key == "toc-dir" then
    opts.tocDir = val
  elseif key == "questie" then
    opts.questie = val
  elseif value == "--count-only" then
    opts.countOnly, opts.quiet = true, true
  elseif value == "--quiet" then
    opts.quiet = true
  elseif value:sub(1, 2) == "--" then
    error("Unknown option: " .. value, 0)
  else
    opts.flavors[#opts.flavors + 1] = value
  end
end

local function say(...)
  if not opts.quiet then print(...) end
end

--------------------------------------------------------------------------------------------
-- Expected lines: what the current generator code would emit
--------------------------------------------------------------------------------------------

--- A write sink for `lib.writeMetadata`: collects complete lines. Every writeMetadata call
--- emits whole lines ending in "\n", so buffering plus a split is exact.
local function newSink()
  local sink = { chunks = {} }
  function sink:write(...)
    for i = 1, select("#", ...) do
      self.chunks[#self.chunks + 1] = select(i, ...)
    end
  end
  function sink:lines()
    local out = {}
    for line in table.concat(self.chunks):gmatch("([^\n]+)\n") do out[#out + 1] = line end
    return out
  end
  return sink
end

local function expectedLines(flavor)
  local sink = newSink()
  local loaded = flavorLoader.load(flavor, nil)

  -- Entity sections, in config order — the mirror of generate.lua's writeEntityMetadata.
  for _, entityType in ipairs(config.entityTypes) do
    local entry = loaded[entityType.name]
    if entry then
      local meta, entities = entry.meta, entry.entities
      local ids = lib.sortedIds(entities)
      local prefix = "X-" .. meta.metaPrefix
      for _, id in ipairs(ids) do
        local row = entities[id]
        local key = prefix .. id .. "-"
        for fieldIndex = 1, meta.fieldCount do
          local encoded = encode.field(meta, fieldIndex, row[fieldIndex])
          if encoded ~= nil then
            lib.writeMetadata(sink, key .. fieldIndex, encoded, config.maxValueLength)
          end
        end
      end
      lib.writeMetadata(sink, prefix .. "IDS-LIST", encode.idList(ids), config.maxValueLength)
    end
  end

  -- Localization, appended after entity data — the mirror of generate.lua's l10n block.
  if lib.fileExists(opts.questie .. "/Localization/lookups/" .. flavor.expansion) then
    for _, entityType in ipairs(config.entityTypes) do
      local entry = loaded[entityType.name]
      if entry then
        local knownIds = {}
        for id in pairs(entry.entities) do knownIds[id] = true end
        local values = l10nGen.extract(opts.questie, flavor, entityType.name, knownIds)
        l10nGen.writeMetadata(sink, entityType.name, values)
        values = nil
        collectgarbage()
      end
    end
  end

  return sink:lines()
end

--------------------------------------------------------------------------------------------
-- Artifact lines: the data directives on disk
--------------------------------------------------------------------------------------------

--- Header directives generation writes outside the data store; excluded from comparison
--- because two of them (build commit/time) legitimately vary between builds.
local HEADER_KEYS = {
  ["X-Contract-Version"] = true, ["X-Flavor"] = true, ["X-Mode"] = true,
  ["X-BUILD-COMMIT"] = true, ["X-BUILD-TIME"] = true,
}

local function artifactLines(tocPath)
  local out = {}
  local content = lib.readAll(tocPath)
  for line in content:gmatch("([^\n]*)\n?") do
    local key = line:match("^## ([^:]+):")
    if key and key:sub(1, 2) == "X-" and not HEADER_KEYS[key] then
      out[#out + 1] = (line:gsub("\r$", ""))
    end
  end
  return out
end

--------------------------------------------------------------------------------------------
-- Comparison
--------------------------------------------------------------------------------------------

local function keyOf(line)
  return line and line:match("^## ([^:]+):") or "?"
end

local function compareFlavor(flavor)
  local tocPath = (opts.tocDir or ".") .. "/" .. config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    say(("[SKIP] %s: %s not generated"):format(flavor.name, tocPath))
    return 0, true
  end

  local started = os.clock()
  local expected = expectedLines(flavor)
  local actual = artifactLines(tocPath)

  local mismatches, reported = 0, 0
  local count = math.max(#expected, #actual)
  for i = 1, count do
    if expected[i] ~= actual[i] then
      mismatches = mismatches + 1
      if not opts.quiet and reported < MAX_REPORTED then
        reported = reported + 1
        io.write(("  MISMATCH at data line %d (expected key %s, artifact key %s)\n")
          :format(i, keyOf(expected[i]), keyOf(actual[i])))
        io.write(("    expected: %s\n"):format(tostring(expected[i]):sub(1, 160)))
        io.write(("    artifact: %s\n"):format(tostring(actual[i]):sub(1, 160)))
      elseif not opts.quiet and reported == MAX_REPORTED then
        reported = reported + 1
        io.write("  ... further mismatches suppressed\n")
      end
    end
  end

  say(("[%s] %s: %d expected data lines, %d in artifact, %d mismatches, %.1fs")
    :format(mismatches == 0 and "PASS" or "FAIL", flavor.name, #expected, #actual,
            mismatches, os.clock() - started))
  return mismatches, false
end

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local flavors = {}
if #opts.flavors == 0 then
  flavors = { config.flavorByName.Vanilla }
else
  for _, name in ipairs(opts.flavors) do
    local flavor = config.flavorByName[name]
    if not flavor then error("Unknown flavor: " .. name, 0) end
    flavors[#flavors + 1] = flavor
  end
end

local total, checked = 0, 0
for _, flavor in ipairs(flavors) do
  local mismatches, skipped = compareFlavor(flavor)
  total = total + mismatches
  if not skipped then checked = checked + 1 end
  collectgarbage()
end

if opts.countOnly then print(total) end

if checked == 0 then
  io.write("reconstruct: nothing to compare — no generated TOC found.\n")
  os.exit(1)
end
os.exit(total == 0 and 0 or 1)
