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
-- Failure capture
--------------------------------------------------------------------------------------------
--
-- Questie's checks report by printing and by writing suggested correction files. Both are
-- kept: the printed lines are captured so a run can be summarised and retained as an artifact,
-- and the correction files land in the output directory ready to paste into a fix.

local captured
local realPrint = print

local function beginCapture()
  captured = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    captured[#captured + 1] = table.concat(parts, "\t")
  end
end

local function endCapture()
  _G.print = realPrint
  return captured
end

--- Strip ANSI colour so a finding's fingerprint is stable across terminals.
local function strip(line)
  return (line:gsub("\27%[[%d;]*m", ""))
end

--- A line is a finding rather than a heading if it names an entity. Questie's checks print
--- free-form text, so this is a heuristic — it decides the *summary count*, never whether the
--- run fails, which is driven by the checks' own return values.
local function looksLikeFinding(line)
  return line:find("%d") ~= nil and (line:find("[Qq]uest") or line:find("[Nn]pc") or
         line:find("[Oo]bject") or line:find("[Ii]tem") or line:find("area"))
end

--------------------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------------------

--- Every invariant, in the order Questie's `validate-*.lua` drivers run them.
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

local function validateFlavor(flavor)
  local started = os.clock()
  local loaded = flavorLoader.load(flavor, nil, not opts.raw)
  local constants = dofile("src/corrections/enum/constants.lua")

  -- Checks needing zone lookups resolve them from support data owned here, not from a
  -- consumer's ZoneDB module.
  local lookup = zones.BuildAreaLookup(flavor)

  local db = {
    quest = loaded.Quest.entities, questKeys = loaded.Quest.meta.keys,
    npc = loaded.Npc.entities, npcKeys = loaded.Npc.meta.keys,
    item = loaded.Item.entities, itemKeys = loaded.Item.meta.keys,
    object = loaded.Object.entities, objectKeys = loaded.Object.meta.keys,
    raceKeys = constants.raceKeys,
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

    local findings = 0
    for _, line in ipairs(output) do
      local clean = strip(line)
      lines[#lines + 1] = check.name .. ": " .. clean
      if looksLikeFinding(clean) and clean:find("^%s*%-") then
        findings = findings + 1
        fingerprints[#fingerprints + 1] = check.name .. "|" .. clean:gsub("^%s+", "")
      end
    end

    if not ok then
      results[#results + 1] = { name = check.name, error = tostring(result) }
      failures = failures + 1
      lines[#lines + 1] = check.name .. ": ERROR " .. tostring(result)
    else
      -- Questie's checks signal failure by exiting; here that became a flag (see
      -- validators/checks.lua). `result == false` covers the one check that returns a boolean.
      local failed = checkFailed or (result == false)
      results[#results + 1] = { name = check.name, failed = failed, findings = findings }
      if failed then failures = failures + 1 end
    end
  end

  lib.mkdirp(opts.out .. "/" .. flavor.name)
  lib.writeAll(opts.out .. "/" .. flavor.name .. "/report.txt", table.concat(lines, "\n") .. "\n")

  table.sort(fingerprints)

  local baselinePath = "validators/baseline/" .. flavor.name .. ".txt"
  if opts.updateBaseline then
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
    if (baseline[fingerprint] or 0) > 0 then
      baseline[fingerprint] = baseline[fingerprint] - 1
    else
      regressions[#regressions + 1] = fingerprint
    end
  end

  local fixed = 0
  for _, remaining in pairs(baseline) do fixed = fixed + remaining end

  local errored = 0
  for _, result in ipairs(results) do if result.error then errored = errored + 1 end end

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
