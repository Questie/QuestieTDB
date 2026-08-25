-- tools/differential/dump_compiler.lua
--
-- Dump **Questie's compiler** reads for one flavor as canonical TSV — the reference
-- implementation this database replaces.
--
-- DESIGN.md phase 6 called for a compiled/TOC differential and gave it a deadline: the
-- compiler is the reference implementation, so its output must be captured before it is
-- deleted. `golden.py` currently snapshots QuestieTDB's *own* source-mode reads, which can
-- only catch drift from itself. This dumper supplies the missing independent oracle.
--
-- It runs Questie's real compile path — the one `cli/validate-era.lua` already drives
-- offline — and then reads through `QuerySingle(id, key)`, which is the exact surface
-- Questie's ~290 call sites use. Output format matches tools/differential/dump_a.lua line
-- for line, so the two dumps are directly comparable.
--
-- Usage (cwd MUST be the Questie checkout root, because Questie's loadTOC resolves
-- relative paths):
--
--   cd ../Questie && lua5.1 ../QuestieTDB/tools/differential/dump_compiler.lua Vanilla out.tsv
--
-- Options:
--   --season=SoD             compile with Season of Discovery active
--   --season=TitanReforged   compile as a Titan Reforged client (Wrath only)
--   --verbose                let Questie's own load/compile chatter through
--
-- Requires `bit32` on the Lua path: eval "$(luarocks path --bin)"

local flavorName = assert(arg[1], "flavor argument required (Vanilla|TBC|Wrath|Cata|Mists)")
local outPath = assert(arg[2], "output path argument required")

local season, verbose = nil, false
for i = 3, #arg do
  local value = arg[i]
  local key, val = value:match("^%-%-([%w%-]+)=(.*)$")
  if key == "season" then season = val
  elseif value == "--verbose" then verbose = true
  else error("Unknown option: " .. value, 0) end
end

-- canon.lua sits beside this file; cwd is the Questie checkout, so resolve from arg[0].
local selfDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local canon = dofile(selfDir .. "/canon.lua")

--------------------------------------------------------------------------------------------
-- Flavor table
--------------------------------------------------------------------------------------------
--
-- TOC, project id and build info are copied verbatim from Questie's own cli/validate-*.lua
-- so this dumper compiles exactly what Questie's CI compiles. Deviating here would make the
-- oracle disagree with upstream for a reason that has nothing to do with QuestieTDB.

local FLAVORS = {
  Vanilla = { toc = "Questie-Classic.toc", project = 2,
              build = { "1.14.3", "44403", "Jun 27 2022", 11403 }, level = 60 },
  TBC     = { toc = "Questie-BCC.toc", project = 5,
              build = { "2.5.1", "38644", "May 11 2021", 20501 }, level = 70 },
  Wrath   = { toc = "Questie-WOTLKC.toc", project = 11,
              build = { "3.4.0", "44644", "Jun 12 2022", 30400 }, level = 80 },
  Cata    = { toc = "Questie-Cata.toc", project = 14,
              build = { "4.4.0", "53863", "Mar 28 2024", 40400 }, level = 85 },
  Mists   = { toc = "Questie-Mists.toc", project = 19,
              build = { "5.5.0", "60700", "May 6 2025", 50500 }, level = 90 },
}

local flavor = assert(FLAVORS[flavorName], "unknown flavor " .. flavorName)

-- Season of Discovery is a Classic-only variant and compiles at level 25, matching
-- cli/validate-sod.lua.
if season == "SoD" then
  assert(flavorName == "Vanilla", "--season=SoD only applies to Vanilla")
  flavor.build = { "1.15.0", "52409", "Dev 1 2023", 11500 }
  flavor.level = 25
end

--------------------------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------------------------

local realPrint = print
local function log(...) io.stderr:write(...) io.stderr:write("\n") end

WOW_PROJECT_ID = flavor.project

-- Questie's own mocks first, then the deltas. Loading them rather than reimplementing keeps
-- this dumper honest: whatever upstream mocks, we mock.
dofile("cli/apiMocks.lua")

GetBuildInfo = function() return unpack(flavor.build) end
UnitLevel = function() return flavor.level end
GetMaxPlayerLevel = function() return flavor.level end

-- PERSONA ALIGNMENT — the load-bearing part of this file.
--
-- Faction-differentiated corrections branch on the player, so the two sides must be the same
-- player or every faction fix reads as a divergence. QuestieTDB's offline default persona is
-- Alliance / Human / Warrior / 60 / plain realm (emulator/client.lua); Questie's apiMocks
-- default to Horde / Tauren / Druid. These lines make the compiler side match QuestieTDB.
UnitFactionGroup = function() return "Alliance" end
UnitRace = function() return "Human", "Human", 1 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitClassBase = function() return "WARRIOR", 1 end
UnitName = function() return "QuestieTDBTester" end
GetRealmName = function() return "TestRealm" end
GetLocale = function() return "enUS" end

local seasonId = 0
if season == "SoD" then seasonId = 2
elseif season == "TitanReforged" then seasonId = 109 end
Enum = Enum or {}
Enum.SeasonID = Enum.SeasonID or { SeasonOfDiscovery = 2 }
C_Seasons = {
  HasActiveSeason = function() return seasonId ~= 0 end,
  GetActiveSeason = function() return seasonId end,
}

--------------------------------------------------------------------------------------------
-- Load and compile
--------------------------------------------------------------------------------------------

-- Questie's correction loader prints a line per redundant correction — thousands of them.
-- Silenced by default so the dumper's own progress stays readable; --verbose restores it.
if not verbose then print = function() end end

local loadTOC = require("cli.loadTOC")

log(("compiler: loading %s (%s, project %d%s)")
  :format(flavor.toc, flavorName, flavor.project, season and (", season " .. season) or ""))
loadTOC(flavor.toc)

-- Errors must never be swallowed, even with print silenced.
Questie.Debug = function() end
Questie.Error = function(_, text) log("questie error: " .. tostring(text)) end
Questie.Warning = function() end

Questie.db = { char = { showEventQuests = false }, global = {}, profile = {} }
QuestieConfig = {}

local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local QuestieCorrections = QuestieLoader:ImportModule("QuestieCorrections")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

QuestieDB.npcData = loadstring(QuestieDB.npcData)()
QuestieDB.objectData = loadstring(QuestieDB.objectData)()
QuestieDB.questData = loadstring(QuestieDB.questData)()
QuestieDB.itemData = loadstring(QuestieDB.itemData)()

Questie:SetIcons()
ZoneDB:Initialize()

-- This is the step that folds Questie's static corrections into the raw tables — AND runs
-- the derived requiredRaces patch (QuestieCorrections.lua) that infers a quest's faction
-- from its questgivers. Both are baked into the binary the call sites read.
QuestieCorrections:Initialize({
  ["npcData"] = QuestieDB.npcData,
  ["objectData"] = QuestieDB.objectData,
  ["itemData"] = QuestieDB.itemData,
  ["questData"] = QuestieDB.questData,
})

-- The remaining pre-compile passes, in QuestieInit.lua's order (lines 118-134). These run
-- ONLY from the in-game init path — no cli/validate-*.lua script calls them — so an oracle
-- that skips them compares against a database that never ships.
--
-- `l10n:Initialize()` sits between these two upstream and is deliberately omitted: it writes
-- lookup translations into the entity tables, and at enUS every lookup resolves empty
-- (`Localization/lookups/*/lookup*/` has no enUS.lua, and `lookupOverrides.lua` gates every
-- branch on a non-enUS locale with no else). Verified inert; this dumper only ever runs enUS,
-- because QuestieTDB serves other locales from an overlay rather than from baked-in strings.
QuestieDB.private:DeleteGatheringNodes()
QuestieCorrections:PreCompile()

local QuestieDBCompiler = QuestieLoader:ImportModule("DBCompiler")
Questie.db.global.debugEnabled = true

local started = os.clock()
QuestieDBCompiler:Compile(function() end)
QuestieDB:Initialize()
log(("compiler: compiled in %.1fs"):format(os.clock() - started))

if not verbose then print = realPrint end

--------------------------------------------------------------------------------------------
-- Dump
--------------------------------------------------------------------------------------------
--
-- Read through QuerySingle — the surface Questie's call sites actually use, so the overrides
-- layer (Questie's runtime corrections) is included exactly as a player would see it. That
-- corresponds to QuestieTDB's composed view: base data plus the Correction Overlay.

-- `QuestieDB.Query*Single` and `QuestieDB.*Pointers` are what QuestieDB:Initialize leaves
-- behind, and they are the surface Questie's own call sites use. Reading the raw DB handles
-- instead would bypass nothing, but it would also stop being the consumer's view the moment
-- upstream wraps them.
local TYPES = {
  { name = "Quest",  read = QuestieDB.QueryQuestSingle,  ids = QuestieDB.QuestPointers,  keys = QuestieDB.questKeys },
  { name = "Npc",    read = QuestieDB.QueryNPCSingle,    ids = QuestieDB.NPCPointers,    keys = QuestieDB.npcKeys },
  { name = "Item",   read = QuestieDB.QueryItemSingle,   ids = QuestieDB.ItemPointers,   keys = QuestieDB.itemKeys },
  { name = "Object", read = QuestieDB.QueryObjectSingle, ids = QuestieDB.ObjectPointers, keys = QuestieDB.objectKeys },
}

local out = assert(io.open(outPath, "w"))
local lines, reads, failures = 0, 0, 0
local reportedFailures = {}

for _, entityType in ipairs(TYPES) do
  assert(entityType.read, "no query function for " .. entityType.name)
  assert(entityType.ids, "no pointer table for " .. entityType.name)

  -- Field names in schema index order, so the dump matches dump_a.lua's ordering.
  local names = {}
  local maxIndex = 0
  for name, index in pairs(entityType.keys) do
    names[index] = name
    if index > maxIndex then maxIndex = index end
  end

  local ids = {}
  for id in pairs(entityType.ids) do ids[#ids + 1] = id end
  table.sort(ids)

  for _, id in ipairs(ids) do
    for fieldIndex = 1, maxIndex do
      local name = names[fieldIndex]
      if name then
        reads = reads + 1
        -- A key with no compiler type raises inside the handle. Record it once rather than
        -- aborting the dump — an uncompiled field is itself a finding.
        local ok, value = pcall(entityType.read, id, name)
        if not ok then
          failures = failures + 1
          local tag = entityType.name .. "." .. name
          if not reportedFailures[tag] then
            reportedFailures[tag] = true
            log("compiler: QuerySingle failed for " .. tag .. " — " .. tostring(value))
          end
        elseif value ~= nil then
          out:write(entityType.name, "\t", id, "\t", name, "\t", canon(value), "\n")
          lines = lines + 1
        end
      end
    end
  end

  log(("compiler %s %s: %d ids"):format(flavorName, entityType.name, #ids))
end

out:close()
log(("compiler dump complete: %d non-nil lines, %d reads, %d failed reads")
  :format(lines, reads, failures))
