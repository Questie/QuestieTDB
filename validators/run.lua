#!/usr/bin/env lua
-- validators/run.lua
--
-- The database validates itself. Cross-entity invariants — quest starters that exist,
-- objectives referencing real IDs, parent/child consistency, spawn areas that resolve — run
-- here, against data this repo owns, with no consumer checkout required.
--
-- This moves the single heaviest job out of Questie's CI.
--
-- Usage:
--   lua validators/run.lua                 every flavor
--   lua validators/run.lua Vanilla TBC
--   lua validators/run.lua --out=.out/v    where diagnostics land
--   lua validators/run.lua --raw           validate uncorrected data, to see what corrections fix
--   lua validators/run.lua --update-baseline    re-record the accepted findings
--   lua validators/run.lua --self-check    prove fingerprinting and baseline comparison are live
--
-- Exits non-zero on any finding that is not in the flavor's baseline.
--
-- ## Why there is a baseline
--
-- Some invariants can only hold once *consumer policy* is applied. Questie's own validators run
-- after `QuestieEvent`, `ContentPhases` and the blacklists have had their say — and by
-- DESIGN.md's boundary rule those stay in Questie, because hiding an entity and gating it on a
-- calendar date are decisions, not database facts. A holiday quest that only exists during
-- Lunar Festival will always look like a broken quest-starter link to a database that does not
-- know about holidays.
--
-- So the accepted findings per flavor are committed under `validators/baseline/`, and a run
-- fails on anything *new*. That makes this a regression gate from day one instead of a wall of
-- known noise, and the baseline file is an explicit, reviewable record of exactly how much the
-- boundary rule costs.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local flavorLoader = dofile("generator/flavor.lua")
local Validators = dofile("validators/checks.lua")
local zones = dofile("validators/zones.lua")

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

---@class ValidatorOptions
---@field flavors string[]
---@field out string
---@field raw boolean
---@field quiet boolean
---@field updateBaseline? boolean
---@field selfCheck? boolean

---@param argv string[]?
---@return ValidatorOptions opts
local function parseArgs(argv)
  local opts = { flavors = {}, out = ".out/validators", raw = false, quiet = false }
  for _, value in ipairs(argv or {}) do
    local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
    if key == "out" then
      opts.out = val
    elseif value == "--raw" then
      opts.raw = true
    elseif value == "--update-baseline" then
      opts.updateBaseline = true
    elseif value == "--quiet" then
      opts.quiet = true
    elseif value == "--self-check" then
      opts.selfCheck = true
    elseif value:sub(1, 2) == "--" then
      error("Unknown option: " .. value, 0)
    else
      opts.flavors[#opts.flavors + 1] = value
    end
  end
  return opts
end

local opts = parseArgs(arg)

---@param ... any
---@return nil
local function say(...)
  if not opts.quiet then print(...) end
end

--------------------------------------------------------------------------------------------
-- Failure capture
--------------------------------------------------------------------------------------------
--
-- Questie's checks report by printing and by writing suggested correction files. Both are
-- kept: the printed lines are captured so a run can be summarised and retained as an artifact,
-- and the correction files land in the output directory ready to paste into a fix.

---@type string[]?
local captured
local realPrint = print

---@return nil
local function beginCapture()
  captured = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    captured[#captured + 1] = table.concat(parts, "\t")
  end
end

---@return string[] output
local function endCapture()
  _G.print = realPrint
  return captured
end

--- Strip ANSI colour so a finding's fingerprint is stable across terminals.
---@param line string
---@return string clean
local function strip(line)
  return (line:gsub("\27%[[%d;]*m", ""))
end

---@type table<string, string>
local ENTITY_TYPE = { quest = "Quest", npc = "Npc", object = "Object", item = "Item" }

---Extracts stable finding fingerprints from one check's human-readable output.
---Owner headings establish context for their indented reasons but are not findings themselves.
---@param checkName string
---@param output string[]
---@return string[] fingerprints
local function fingerprintOutput(checkName, output)
  local fingerprints = {}
  local owner

  ---Records one reason under its owning entity.
  ---@param entity string Canonical `Type:id` identity.
  ---@param reason string Finding text without the display-only owner heading.
  ---@return nil
  local function add(entity, reason)
    reason = reason:gsub("^%s+", ""):gsub("%s+$", "")
    fingerprints[#fingerprints + 1] = checkName .. "|" .. entity .. "|" .. reason
  end

  for _, line in ipairs(output) do
    local clean = strip(line)
    local typeName, id, tail = clean:match("^%-%s+([%a]+)%s+(%d+)(.*)$")
    local canonicalType = typeName and ENTITY_TYPE[typeName:lower()]

    if canonicalType then
      owner = canonicalType .. ":" .. id
      if not tail:match("^%s*:%s*$") then
        local parenthesized, after = tail:match("^%s*(%b())%s*:?(.*)$")
        local reason
        if parenthesized and after:match("%S") then
          -- Display names are unstable and add no identity; the area detail is the finding.
          reason = after
        elseif parenthesized then
          reason = parenthesized:sub(2, -2)
        else
          reason = tail:gsub("^%s*:%s*", "")
          if reason == "" then reason = "entity" end
        end
        add(owner, reason)
      end
    else
      local nestedReason = owner and clean:match("^%s+%-%s+(.+)$")
      if nestedReason then
        add(owner, nestedReason)
      elseif clean:match("%S") then
        owner = nil
      end
    end
  end

  return fingerprints
end

---Counts the findings in a validator's owner-indexed result table.
---A list of reason strings contributes one finding per reason. Other values, including
---number lists such as unknown area IDs, describe one finding for their owning entity.
---@param findings table?
---@return integer count
local function structuredFindingCount(findings)
  if type(findings) ~= "table" then return 0 end

  local count = 0
  for _, detail in pairs(findings) do
    local reasonCount = 0
    if type(detail) == "table" and #detail > 0 then
      reasonCount = #detail
      for index = 1, #detail do
        if type(detail[index]) ~= "string" then
          reasonCount = 0
          break
        end
      end
    end
    count = count + (reasonCount > 0 and reasonCount or 1)
  end
  return count
end

---Reports when display-output parsing did not preserve the validator's structured findings.
---@param failed boolean
---@param structuredFindings table?
---@param parsedCount integer
---@return string? errorMessage
local function fingerprintCountError(failed, structuredFindings, parsedCount)
  if not failed then return nil end

  local expected = structuredFindingCount(structuredFindings)
  if expected == 0 then
    return "check failed but returned no structured findings"
  end
  if parsedCount ~= expected then
    return ("check returned %d structured findings but output produced %d fingerprints")
      :format(expected, parsedCount)
  end
  return nil
end

---Counts validator execution or fingerprint errors.
---@param results table[]
---@return integer count
local function countResultErrors(results)
  local count = 0
  for _, result in ipairs(results) do
    if result.error then count = count + 1 end
  end
  return count
end

---Consumes one accepted occurrence, reporting whether the fingerprint is new.
---@param fingerprint string
---@param accepted table<string, integer>
---@return boolean isRegression
local function consumeFingerprint(fingerprint, accepted)
  if (accepted[fingerprint] or 0) == 0 then return true end
  accepted[fingerprint] = accepted[fingerprint] - 1
  return false
end

---Proves owner parsing and multiset baseline comparison remain sensitive.
---@return nil
local function selfCheckFingerprints()
  local parsed = fingerprintOutput("sample", {
    "Found 1 NPCs with invalid questStarts:",
    "- NPC 3061:",
    "  - quest 27021 is missing in questStarts",
    "",
    "- Object 42 (Display Name): areaIds 999",
  })
  assert(#parsed == 2, "validator fingerprint self-check: expected two findings")
  assert(parsed[1] == "sample|Npc:3061|quest 27021 is missing in questStarts",
    "validator fingerprint self-check: nested owner was lost")
  assert(parsed[2] == "sample|Object:42|areaIds 999",
    "validator fingerprint self-check: display name leaked into identity")

  local structured = {
    [3061] = { "quest 27021 is missing", "quest 27022 is missing" },
    [42] = { 999, 1000 },
    [43] = true,
  }
  assert(structuredFindingCount(structured) == 4,
    "validator fingerprint self-check: structured finding count changed")
  assert(fingerprintCountError(true, structured, 3) ~= nil,
    "validator fingerprint self-check: partial parse loss was accepted")
  assert(fingerprintCountError(true, structured, 4) == nil,
    "validator fingerprint self-check: complete parse was rejected")
  assert(countResultErrors({ { error = "partial parse" }, { findings = 1 } }) == 1,
    "validator fingerprint self-check: result errors were not counted")

  local duplicate = parsed[1]
  local accepted = { [duplicate] = 1 }
  assert(not consumeFingerprint(duplicate, accepted),
    "validator fingerprint self-check: accepted occurrence was rejected")
  assert(consumeFingerprint(duplicate, accepted),
    "validator fingerprint self-check: duplicate occurrence was not detected")
end

--------------------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------------------

---@class ValidatorCheck
---@field name string
---@field run fun(db: table): any

--- Every invariant, in the order Questie's `validate-*.lua` drivers run them.
---@type ValidatorCheck[]
local CHECKS = {
  { name = "npcQuestStarts", run = function(db) return Validators.checkNpcQuestStarts(db.npc, db.npcKeys, db.quest, db.questKeys) end },
  { name = "npcQuestEnds", run = function(db) return Validators.checkNpcQuestEnds(db.npc, db.npcKeys, db.quest, db.questKeys) end },
  { name = "objectQuestStarts", run = function(db) return Validators.checkObjectQuestStarts(db.object, db.objectKeys, db.quest, db.questKeys) end },
  { name = "objectQuestEnds", run = function(db) return Validators.checkObjectQuestEnds(db.object, db.objectKeys, db.quest, db.questKeys) end },
  { name = "requiredRaces", run = function(db) return Validators.checkRequiredRaces(db.quest, db.questKeys, db.raceKeys) end },
  { name = "requiredSourceItems", run = function(db) return Validators.checkRequiredSourceItems(db.quest, db.questKeys) end },
  { name = "preQuestExclusiveness", run = function(db) return Validators.checkPreQuestExclusiveness(db.quest, db.questKeys) end },
  { name = "parentChildQuestRelations", run = function(db) return Validators.checkParentChildQuestRelations(db.quest, db.questKeys) end },
  { name = "questStarters", run = function(db) return Validators.checkQuestStarters(db.quest, db.questKeys, db.npc, db.npcKeys, db.object, db.item) end },
  { name = "questFinishers", run = function(db) return Validators.checkQuestFinishers(db.quest, db.questKeys, db.npc, db.object) end },
  { name = "objectives", run = function(db) return Validators.checkObjectives(db.quest, db.questKeys, db.npc, db.object, db.item) end },
  { name = "npcSpawnAreaIds", run = function(db) return Validators.checkNpcSpawnAreaIds(db.npc, db.npcKeys, db.getUiMapIdByAreaId) end },
  { name = "objectSpawnAreaIds", run = function(db) return Validators.checkObjectSpawnAreaIds(db.object, db.objectKeys, db.getUiMapIdByAreaId) end },
  { name = "questExtraObjectiveSpawnAreaIds", run = function(db) return Validators.checkQuestExtraObjectiveSpawnAreaIds(db.quest, db.questKeys, db.getUiMapIdByAreaId) end },
  { name = "questTriggerEndSpawnAreaIds", run = function(db) return Validators.checkQuestTriggerEndSpawnAreaIds(db.quest, db.questKeys, db.getUiMapIdByAreaId) end },
}

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

---@param flavor table
---@return integer regressions
local function validateFlavor(flavor)
  local started = os.clock()
  local loaded = flavorLoader.load(flavor, nil, not opts.raw)
  local constants = dofile("src/corrections/enum/constants.lua")
  local expansionConstants = constants.byExpansion and constants.byExpansion[flavor.expansion]
  if not expansionConstants or not expansionConstants.raceKeys then
    error("validators: missing generated race constants for expansion " ..
      tostring(flavor.expansion), 0)
  end

  -- Checks needing zone lookups resolve them from support data owned here, not from a
  -- consumer's ZoneDB module.
  local lookup = zones.BuildAreaLookup(flavor)

  local db = {
    quest = loaded.Quest.entities, questKeys = loaded.Quest.meta.keys,
    npc = loaded.Npc.entities, npcKeys = loaded.Npc.meta.keys,
    item = loaded.Item.entities, itemKeys = loaded.Item.meta.keys,
    object = loaded.Object.entities, objectKeys = loaded.Object.meta.keys,
    raceKeys = expansionConstants.raceKeys,
    getUiMapIdByAreaId = lookup,
  }

  Validators.SetOutputDir(opts.out .. "/" .. flavor.name)

  local results, failures, lines, fingerprints = {}, 0, {}, {}
  for _, check in ipairs(CHECKS) do
    Validators.failed = false
    beginCapture()
    local ok, result = pcall(check.run, db)
    local output = endCapture()
    local checkFailed = Validators.failed

    for _, line in ipairs(output) do
      lines[#lines + 1] = check.name .. ": " .. strip(line)
    end
    local checkFingerprints = fingerprintOutput(check.name, output)
    local findings = #checkFingerprints
    for _, fingerprint in ipairs(checkFingerprints) do
      fingerprints[#fingerprints + 1] = fingerprint
    end

    if not ok then
      results[#results + 1] = { name = check.name, error = tostring(result) }
      failures = failures + 1
      lines[#lines + 1] = check.name .. ": ERROR " .. tostring(result)
    else
      -- Questie's checks signal failure by exiting; here that became a flag (see
      -- validators/checks.lua). `result == false` covers the one check that returns a boolean.
      local failed = checkFailed or (result == false)
      local countError = fingerprintCountError(failed, result, findings)
      if countError then
        -- A changed print shape must not turn all or part of a failed check into "fixed" rows.
        results[#results + 1] = { name = check.name, error = countError }
      else
        results[#results + 1] = { name = check.name, failed = failed, findings = findings }
      end
      if failed then failures = failures + 1 end
    end
  end

  lib.mkdirp(opts.out .. "/" .. flavor.name)
  lib.writeAll(opts.out .. "/" .. flavor.name .. "/report.txt", table.concat(lines, "\n") .. "\n")

  table.sort(fingerprints)

  local errored = countResultErrors(results)
  local baselinePath = "validators/baseline/" .. flavor.name .. ".txt"
  if opts.updateBaseline then
    if errored > 0 then
      say(("[FAIL] %s: baseline not updated because %d checks produced invalid evidence")
        :format(flavor.name, errored))
      for _, result in ipairs(results) do
        if result.error then say(("    ERROR %-30s %s"):format(result.name, result.error)) end
      end
      return errored
    end
    lib.mkdirp("validators/baseline")
    lib.writeAll(baselinePath, table.concat(fingerprints, "\n") .. "\n")
    say(("[BASELINE] %s: recorded %d accepted findings -> %s")
      :format(flavor.name, #fingerprints, baselinePath))
    return 0
  end

  local baseline = {}
  local baselineCount = 0
  if lib.fileExists(baselinePath) then
    for line in lib.readAll(baselinePath):gmatch("[^\n]+") do
      baseline[line] = (baseline[line] or 0) + 1
      baselineCount = baselineCount + 1
    end
  end

  local regressions = {}
  for _, fingerprint in ipairs(fingerprints) do
    if consumeFingerprint(fingerprint, baseline) then
      regressions[#regressions + 1] = fingerprint
    end
  end

  if opts.selfCheck then
    say(("    self-check: %s fingerprint ownership, counts, and duplicates are live")
      :format(flavor.name))
  end

  local fixed = 0
  for _, remaining in pairs(baseline) do fixed = fixed + remaining end

  local status = (#regressions == 0 and errored == 0) and "PASS" or "FAIL"
  say(("[%s] %s: %d/%d checks clean, %d findings (%d baselined, %d new, %d fixed), %.1fs  (%s)")
    :format(status, flavor.name, #CHECKS - failures, #CHECKS, #fingerprints,
            baselineCount, #regressions, fixed, os.clock() - started,
            opts.out .. "/" .. flavor.name .. "/report.txt"))

  if not opts.quiet then
    for index, fingerprint in ipairs(regressions) do
      if index <= 15 then
        say("    NEW  " .. fingerprint)
      elseif index == 16 then
        say(("    ... and %d more new findings"):format(#regressions - 15))
        break
      end
    end
    for _, result in ipairs(results) do
      if result.error then say(("    ERROR %-30s %s"):format(result.name, result.error)) end
    end
    if fixed > 0 then
      say(("    %d baselined findings no longer occur — run --update-baseline to record that")
        :format(fixed))
    end
  end

  return #regressions + errored
end

if opts.selfCheck then selfCheckFingerprints() end

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

local total = 0
for _, flavor in ipairs(flavors) do
  total = total + validateFlavor(flavor)
end

os.exit(total == 0 and 0 or 1)
