#!/usr/bin/env lua
-- test.lua
--
-- Decoder, serializer and equivalence tests, plus the negative controls that prove
-- verification is able to fail.
--
-- Deliberately dependency-free: plain Lua 5.1, no busted, no luarocks. The guard has to be
-- present in CI rather than conditional on a toolchain being installed.
--
-- Usage:
--   lua test.lua            every suite
--   lua test.lua serialize  one suite by name

local lib = dofile("generator/lib.lua")
local serialize = dofile("generator/serialize.lua")
local codec = dofile("src/meta/codec.lua")
local encode = dofile("generator/encode.lua")
local normalize = dofile("src/meta/normalize.lua")
local emulator = dofile("emulator/metadata.lua")
local client = dofile("emulator/client.lua")
local config = dofile("src/config.lua")

local LUA_BIN = os.getenv("LUA") or "lua5.1"
local QUESTIE_PATH = os.getenv("QUESTIE_PATH") or "../Questie"

--------------------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------------------

local suites, order = {}, {}
local function suite(name, fn)
  suites[name] = fn
  order[#order + 1] = name
end

local current

---Quotes one argument for the POSIX shell used by the offline test commands.
---@param value string
---@return string quoted
local function shellQuote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

---Runs one POSIX-shell command and normalizes Lua 5.1/5.2 exit-status shapes.
---@param command string
---@return boolean succeeded
local function commandSucceeded(command)
  local ok = os.execute(command)
  if type(ok) == "number" then return ok == 0 end
  return ok == true
end

local function check(condition, message)
  current.total = current.total + 1
  if not condition then
    current.failed = current.failed + 1
    io.write("  FAIL ", current.name, ": ", message, "\n")
  end
end

local function equal(actual, expected, message)
  check(lib.deepEqual(actual, expected),
    ("%s\n    expected: %s\n    actual:   %s"):format(message, lib.show(expected), lib.show(actual)))
end

local function roundTrip(value, message)
  local encoded = serialize.value(value)
  local decoded = codec.decodeTable(encoded)
  equal(decoded, value, (message or "round trip") .. "  [" .. encoded .. "]")
  return encoded
end

--------------------------------------------------------------------------------------------
-- serialize
--------------------------------------------------------------------------------------------

suite("serialize", function()
  equal(serialize.value({ 1, 2, 3 }), "{1,2,3}", "dense array")
  equal(serialize.value({ [1] = { 12676 }, [3] = { 16305 } }), "{{12676},nil,{16305}}", "sparse array keeps holes")
  equal(serialize.value({}), "{}", "empty table")
  equal(serialize.value({ [1335] = { { 36.43, 55.89 } } }), "{[1335]={{36.43,55.89}}}", "coordinate table")

  -- Hash keys are emitted in sorted order, which is what makes regeneration byte-identical.
  equal(serialize.value({ [1335] = { 1 }, [1] = { 2 } }), "{{2},[1335]={1}}", "hash keys sorted numerically")
  equal(serialize.value({ 1, 2, 3, [1000] = 9 }), "{1,2,3,[1000]=9}", "dense prefix plus a distant key")
  equal(serialize.value({ [6] = "x" }), "{[6]='x'}", "one distant key does not emit five holes")
  equal(serialize.value({ [12] = { 1 }, [1519] = { 2 } }), "{[12]={1},[1519]={2}}", "zone-keyed spawn table")
  equal(serialize.value({ b = 1, a = 2 }), "{['a']=2,['b']=1}", "string keys sorted lexicographically")
  equal(serialize.value({ 1, x = 2 }), "{1,['x']=2}", "array part before hash part")

  -- Determinism: the same input must produce the same bytes, every time.
  local wide = {}
  for i = 1, 200 do wide["key" .. i] = i end
  equal(serialize.value(wide), serialize.value(wide), "repeated serialization is identical")

  -- Numbers must read back as exactly themselves.
  for _, n in ipairs({ 0, 1, -1, 36.43, 55.89, 0.1, 1 / 3, 2 ^ 31, -2 ^ 31, 8388607, 1e-9 }) do
    equal(tonumber(serialize.number(n)), n, "number round trip: " .. tostring(n))
  end

  -- Strings must survive loadstring exactly, including the characters a naive escaper drops.
  for _, s in ipairs({
    "Sharptalon's Claw",
    'He said "hello"',
    "back\\slash",
    "both ' and \" quotes",
    "line\nbreak",
    "carriage\rreturn",
    "tab\there",
    "null\0byte",
    "Ünïcödé ‡ dagger",
    "",
    "nil",
    "~E~",
    "~3~",
  }) do
    local decoded = codec.decodeTable(serialize.quote(s))
    equal(decoded, s, "string quote round trip: " .. s:gsub("%c", "?"))
  end

  -- No serialized string may contain a raw newline; the TOC format is line-oriented.
  check(not serialize.quote("line\nbreak"):find("\n"), "quoted string contains a raw newline")

  roundTrip({ nil, nil, { 16305 }, nil, { { { 7572 }, 7572, "The Tale of Sorrow" } } }, "questgivers shape")
  roundTrip({ "Secret phrase found", { [1336] = { { 79.56, 75.65 } } } }, "trigger shape")
  roundTrip({ { nil, "ICON_TYPE_OBJECT", "Use a Fresh Carcass", 0, { { "object", 1770 } } } }, "extraobjectives shape")
  roundTrip({ [12] = { { 36.43, 55.89 }, { 31.43, 57.03, 2 } } }, "spawnlist with phase")
end)

--------------------------------------------------------------------------------------------
-- codec
--------------------------------------------------------------------------------------------

suite("codec", function()
  equal(codec.chunkCount["~3~"], 3, "chunk header parsed")
  equal(codec.chunkCount["~21~"], 21, "chunk header beyond the warmed range")
  equal(codec.chunkCount["Sharptalon's Claw"], nil, "ordinary value is not a chunk header")
  equal(codec.chunkCount["{1,2}"], nil, "table literal is not a chunk header")
  equal(codec.chunkCount["~E~"], nil, "empty marker is not a chunk header")

  equal(codec.decodeString("Sharptalon's Claw"), "Sharptalon's Claw", "raw string")
  equal(codec.decodeString(codec.EMPTY_STRING), "", "empty-string marker")

  -- Every string must survive encode -> decode, including the ones that need a marker.
  for _, s in ipairs({ "plain", "", "nil", "~E~", "~7~", "~Q~x", "line\nbreak", "Ünïcödé" }) do
    equal(codec.decodeString(encode.string(s)), s, "encode/decode string: " .. s:gsub("%c", "?"))
  end

  equal(codec.decodeIdList("2,5,7"), { 2, 5, 7 }, "id list")
  equal(codec.decodeIdMap("2,5,7"), { [2] = true, [5] = true, [7] = true }, "id map")
  equal(codec.decodeIdList(nil), {}, "absent id list")

  local sep = config.localeSeparator
  local joined = table.concat({ "eins", "", "dos", "un" }, sep)
  equal(codec.localeSegment(joined, 1, sep), "eins", "first locale segment")
  equal(codec.localeSegment(joined, 2, sep), nil, "empty segment means no translation")
  equal(codec.localeSegment(joined, 3, sep), "dos", "middle locale segment")
  equal(codec.localeSegment(joined, 4, sep), "un", "last locale segment")
  equal(codec.localeSegment(joined, 5, sep), nil, "segment past the end")
end)

--------------------------------------------------------------------------------------------
-- Generation inputs
--------------------------------------------------------------------------------------------

suite("generation-inputs", function()
  local l10nGen = dofile("generator/l10n.lua")
  local flavor = config.flavorByName.Vanilla
  local typeFilter = { Quest = true }
  local root = ".out/test-questie-input"
  local paths = {}
  for _, locale in ipairs(config.locales) do
    local path = l10nGen.lookupPath(root, flavor, l10nGen.types.Quest, locale)
    paths[#paths + 1] = path
    os.remove(path)
  end

  local ok, err = pcall(l10nGen.assertInputs, root, { flavor }, typeFilter)
  check(not ok and tostring(err):find("%-%-no%-l10n"),
    "missing localization input fails with the explicit partial-output escape hatch")

  -- A type-filtered Generation needs only that entity type's nine locale files.
  for _, path in ipairs(paths) do
    lib.mkdirp(path:match("^(.*)/[^/]+$"))
    lib.writeAll(path, "-- localization input fixture\n")
  end

  local present, presentErr = pcall(l10nGen.assertInputs, root, { flavor }, typeFilter)
  check(present, "a complete selected lookup set passes preflight: " .. tostring(presentErr))

  -- When a checkout is supplied, local tests enforce the same reviewed commit as automation.
  if lib.gitCommit(QUESTIE_PATH) ~= string.rep("0", 40) then
    local pinned, pinErr = pcall(lib.assertQuestiePin, QUESTIE_PATH)
    check(pinned, "the configured Questie checkout matches QUESTIE_COMMIT: " .. tostring(pinErr))
  end

  for _, path in ipairs(paths) do os.remove(path) end
end)

--------------------------------------------------------------------------------------------
-- Questie input integrity
--------------------------------------------------------------------------------------------

suite("questie-input-integrity", function()
  local root = ".out/test-questie-pin"
  local pinPath = root .. "/PIN"
  lib.mkdirp(root)

  local commit = lib.gitCommit(".")
  check(commit ~= string.rep("0", 40), "test repository commit is available")

  lib.writeAll(pinPath, commit .. "\n")
  local pinned, pinnedErr = pcall(lib.assertQuestiePin, ".", pinPath)
  check(pinned, "a checkout at the pinned commit passes: " .. tostring(pinnedErr))

  lib.writeAll(pinPath, string.rep("0", 40) .. "\n")
  local wrong, wrongErr = pcall(lib.assertQuestiePin, ".", pinPath)
  check(not wrong and tostring(wrongErr):find(commit, 1, true) ~= nil,
    "a checkout at the wrong commit is rejected with its actual commit")

  lib.writeAll(pinPath, "not-a-commit\n")
  local malformed, malformedErr = pcall(lib.assertQuestiePin, ".", pinPath)
  check(not malformed and tostring(malformedErr):find("40%-character"),
    "a malformed pin is rejected")

  os.remove(pinPath)
end)

--------------------------------------------------------------------------------------------
-- Workflow contracts
--------------------------------------------------------------------------------------------

suite("workflow-contracts", function()
  local release = lib.readAll(".github/workflows/release.yml")
  check(release:find("needs: [quality, differential]", 1, true) ~= nil,
    "release publication depends on the quality and compiler differential jobs")
  check(release:find("--questie=../Questie --lua=lua --self-check", 1, true) ~= nil,
    "release compiler differential runs its sensitivity self-check")
  check(release:find(
    "git diff --exit-code src/corrections/ src/derived/RamerDouglasPeucker.lua", 1, true) ~= nil,
    "release drift gate covers Corrections and the copied waypoint library")

  local checkout = lib.readAll(".github/actions/checkout-questie/action.yml")
  check(checkout:find("ref: ${{ steps.pin.outputs.commit }}", 1, true) ~= nil,
    "automation checks out the commit read from QUESTIE_COMMIT")

  local pin = lib.readAll("QUESTIE_COMMIT"):gsub("%s+$", "")
  check(#pin == 40 and pin:match("^[0-9a-f]+$") ~= nil,
    "Questie pin is one lowercase commit SHA")
end)

--------------------------------------------------------------------------------------------
-- Local full-flow ordering
--------------------------------------------------------------------------------------------

suite("check-flow", function()
  local root = ".out/test-check-flow"
  commandSucceeded("rm -rf " .. shellQuote(root))
  lib.mkdirp(root .. "/tools")
  lib.mkdirp(root .. "/fake-bin")
  lib.copyFile("questietdb", root .. "/questietdb")
  lib.copyFile("tools/check.sh", root .. "/tools/check.sh")

  local fakeLua = root .. "/fake-lua"
  lib.writeAll(fakeLua, [[#!/usr/bin/env bash
set -eu
if [ "${1:-}" = "-e" ] && [ "${2:-}" = "io.write(_VERSION)" ]; then
  printf 'Lua 5.1'
  exit 0
fi
printf 'lua\tquestie=%s\t%s\n' "${QUESTIE_PATH:-}" "$*" >> "$CHECK_FLOW_LOG"
if [ "${CHECK_FLOW_FAIL_VERIFY:-0}" = "1" ] && [ "${1:-}" = "verify.lua" ]; then
  exit 7
fi
if [ "${1:-}" = "generate.lua" ]; then
  case "${2:-}" in
    Vanilla|Mists) printf 'artifact\n' > "QuestieTDB_${2}.toc" ;;
  esac
elif [ "${1:-}" = "verify.lua" ]; then
  printf '[PASS] fixture summary %0100d summary-tail\n' 0
fi
]])
  local wrongLua = root .. "/wrong-lua"
  lib.writeAll(wrongLua, [[#!/usr/bin/env bash
if [ "${1:-}" = "-e" ] && [ "${2:-}" = "io.write(_VERSION)" ]; then
  printf 'Lua 5.4'
  exit 0
fi
printf 'wrong-lua-job\t%s\n' "$*" >> "$CHECK_FLOW_LOG"
exit 99
]])
  lib.copyFile(fakeLua, root .. "/fake-bin/lua5.1")
  lib.writeAll(root .. "/fake-bin/python3", [[#!/usr/bin/env bash
set -eu
printf 'python\tquestie=%s\t%s\n' "${QUESTIE_PATH:-}" "$*" >> "$CHECK_FLOW_LOG"
]])
  check(commandSucceeded("chmod +x " .. shellQuote(root .. "/questietdb") .. " " ..
    shellQuote(root .. "/tools/check.sh") .. " " .. shellQuote(fakeLua) .. " " ..
    shellQuote(wrongLua) .. " " .. shellQuote(root .. "/fake-bin/lua5.1") .. " " ..
    shellQuote(root .. "/fake-bin/python3")),
    "full-flow fixture executables prepared")

  local pwdPipe = assert(io.popen("pwd", "r"))
  local repoRoot = (pwdPipe:read("*a") or ""):gsub("%s+$", "")
  pwdPipe:close()
  local rootAbs = repoRoot .. "/" .. root
  local logPath = rootAbs .. "/commands.log"
  local outputPath = rootAbs .. "/output.log"

  ---Removes outputs that would let one CLI fixture affect the next.
  ---@return nil
  local function resetFlowFiles()
    commandSucceeded("rm -f " .. shellQuote(logPath) .. " " ..
      shellQuote(rootAbs .. "/QuestieTDB_Vanilla.toc") .. " " ..
      shellQuote(rootAbs .. "/QuestieTDB_Mists.toc"))
  end

  ---@param arguments string
  ---@param runInParallel boolean? Omit to preserve the fixture's sequential default.
  ---@param failVerify boolean? Make the fake Verification command fail after logging.
  ---@param discoverLua boolean? Clear inherited LUA and exercise automatic discovery.
  ---@param luaPath string? Explicit interpreter override for prerequisite-order tests.
  ---@return boolean succeeded
  local function runFlow(arguments, runInParallel, failVerify, discoverLua, luaPath)
    resetFlowFiles()
    local schedulingOption = runInParallel and "" or " --sequential"
    local failureEnvironment = failVerify and " CHECK_FLOW_FAIL_VERIFY=1" or ""
    local luaEnvironment = discoverLua and " LUA=" or ""
    local luaOption = discoverLua and "" or
      " --lua=" .. shellQuote(luaPath or rootAbs .. "/fake-lua")
    local command = "cd " .. shellQuote(rootAbs) .. " && PATH=" ..
      shellQuote(rootAbs .. "/fake-bin") .. ":\"$PATH\" CHECK_FLOW_LOG=" ..
      shellQuote(logPath) .. failureEnvironment .. luaEnvironment ..
      " bash tools/check.sh " .. arguments .. schedulingOption ..
      " --questie=/tmp/fake-questie" .. luaOption ..
      " > " .. shellQuote(outputPath) .. " 2>&1"
    return commandSucceeded(command)
  end

  ---Runs the public CLI against fake tools, without touching real artifacts or Questie.
  ---@param arguments string
  ---@param luaPath string? Interpreter override for prerequisite failure cases.
  ---@param includeFixtureOptions boolean? Pass false to test a truly argument-free invocation.
  ---@return boolean succeeded
  local function runPublicFlow(arguments, luaPath, includeFixtureOptions)
    resetFlowFiles()
    local fixtureOptions = ""
    if includeFixtureOptions ~= false then
      fixtureOptions = " --sequential --questie=/tmp/fake-questie --lua=" ..
        shellQuote(luaPath or rootAbs .. "/fake-lua")
    end
    local command = "cd " .. shellQuote(rootAbs) .. " && PATH=" ..
      shellQuote(rootAbs .. "/fake-bin") .. ":\"$PATH\" CHECK_FLOW_LOG=" ..
      shellQuote(logPath) .. " ./questietdb " .. arguments .. fixtureOptions ..
      " > " .. shellQuote(outputPath) .. " 2>&1"
    return commandSucceeded(command)
  end

  ---@param log string
  ---@param needle string
  ---@return integer[] positions
  local function positionsOf(log, needle)
    local positions, position = {}, 1
    while true do
      local startAt, endAt = log:find(needle, position, true)
      if not startAt then return positions end
      positions[#positions + 1] = startAt
      position = endAt + 1
    end
  end

  local readerNeedles = {
    "verify.lua ", "equivalence.lua ", "reconstruct.lua ", "validators/run.lua ",
    "compiler_diff.py ", "golden.py check ", "\ttest.lua",
  }

  check(runFlow("all --flavors=Vanilla,Mists"), "fake full flow passes")
  local output = lib.readAll(outputPath)
  check(output:find("generate:toc%s+%d+%.%ds") ~= nil,
    "base TOC Generation reports its duration")
  check(output:find("generate:Vanilla%s+%d+%.%ds") ~= nil,
    "scheduled Generation reports each job duration")
  check(output:find("Generation results %(%d+%.%ds%)") ~= nil,
    "Generation reports its wall-clock duration")
  check(output:find("all stages passed in %d+%.%ds") ~= nil,
    "the full flow reports its wall-clock duration")
  check(output:find("summary%-tail") ~= nil,
    "job summaries longer than 96 characters remain intact")

  local log = lib.readAll(logPath)
  local vanillaGenerations = positionsOf(log, "generate.lua Vanilla")
  local mistsGenerations = positionsOf(log, "generate.lua Mists")
  equal(#vanillaGenerations, 1, "full flow generates Vanilla once")
  equal(#mistsGenerations, 1, "full flow generates Mists once")
  local generationBoundary = math.max(vanillaGenerations[1] or 0, mistsGenerations[1] or 0)
  local readers = 0
  for _, needle in ipairs(readerNeedles) do
    for _, readerAt in ipairs(positionsOf(log, needle)) do
      readers = readers + 1
      check(readerAt > generationBoundary,
        "artifact reader starts after every selected flavor finishes Generation: " .. needle)
    end
  end
  check(readers >= 13, "full-flow fixture observed every reader family")
  check(log:find("questie=/tmp/fake-questie\tgenerate.lua Vanilla", 1, true) ~= nil and
        log:find("questie=/tmp/fake-questie\ttest.lua", 1, true) ~= nil,
    "custom Questie path reaches Generation and unit tests through the environment")
  check(log:find("reconstruct.lua Vanilla --questie=/tmp/fake-questie", 1, true) ~= nil,
    "custom Questie path reaches Reconstruction")
  check(log:find("compiler_diff.py Vanilla --questie=/tmp/fake-questie", 1, true) ~= nil,
    "custom Questie path reaches the compiler differential")

  check(runFlow("test"), "the standalone unit-test gate needs no Questie checkout")
  local testLog = lib.readAll(logPath)
  check(testLog:find("\ttest.lua", 1, true) ~= nil and
        testLog:find("assertQuestiePin", 1, true) == nil,
    "standalone unit tests run without the Questie pin preflight")

  check(runFlow("test verify validators --flavors=Vanilla,Mists --budget-mb=2000", true),
    "parallel scheduler fixture passes")
  local schedulerOutput = lib.readAll(outputPath)
  local testStarted = schedulerOutput:find("  start test", 1, true)
  local vanillaStarted = schedulerOutput:find("  start verify:Vanilla", 1, true)
  local mistsStarted = schedulerOutput:find("  start verify:Mists", 1, true)
  check(testStarted ~= nil and vanillaStarted ~= nil and testStarted < vanillaStarted,
    "the long-running unit tests are dispatched first")
  check(vanillaStarted ~= nil and mistsStarted ~= nil and vanillaStarted < mistsStarted,
    "a smaller fitting job bypasses a blocked heavier job")
  check(schedulerOutput:find("all 5 checks jobs passed", 1, true) ~= nil,
    "every parallel scheduler fixture job completes")

  -- Public CLI parsing stays separate from the scheduler fixture so selection errors prove
  -- they fail before the engine starts any work.
  check(runPublicFlow("", nil, false), "the argument-free public CLI prints help")
  local publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("Usage: ./questietdb", 1, true) ~= nil and
        not lib.fileExists(logPath),
    "public CLI help runs no tools")
  check(runPublicFlow("--help"), "the explicit public CLI help passes")

  check(runPublicFlow("generate"), "a task-only Generation selects every flavor")
  local publicLog = lib.readAll(logPath)
  for _, flavor in ipairs({ "Vanilla", "TBC", "Wrath", "Cata", "Mists" }) do
    equal(#positionsOf(publicLog, "generate.lua " .. flavor), 1,
      "task-only Generation includes " .. flavor)
  end
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("unbound variable", 1, true) == nil,
    "task-only commands do not trip set -u")

  check(runPublicFlow("generate Vanilla"), "a positional Vanilla Generation passes")
  publicLog = lib.readAll(logPath)
  equal(#positionsOf(publicLog, "generate.lua Vanilla"), 1,
    "a positional flavor selects Vanilla once")
  equal(#positionsOf(publicLog, "generate.lua Mists"), 0,
    "a positional flavor excludes unselected flavors")

  check(runPublicFlow("generate Vanilla Mists"), "multiple positional flavors pass")
  publicLog = lib.readAll(logPath)
  equal(#positionsOf(publicLog, "generate.lua Vanilla"), 1,
    "multiple positional flavors include Vanilla")
  equal(#positionsOf(publicLog, "generate.lua Mists"), 1,
    "multiple positional flavors include Mists")

  check(runPublicFlow("check Vanilla"), "the public check bundle passes")
  publicLog = lib.readAll(logPath)
  for _, needle in ipairs({
    "verify.lua Vanilla", "equivalence.lua Vanilla", "reconstruct.lua Vanilla",
    "validators/run.lua Vanilla", "compiler_diff.py Vanilla",
  }) do
    check(publicLog:find(needle, 1, true) ~= nil,
      "the public check bundle includes " .. needle)
  end
  check(publicLog:find("generate.lua Vanilla", 1, true) == nil and
        publicLog:find("golden.py", 1, true) == nil and
        publicLog:find("\ttest.lua", 1, true) == nil,
    "the public check bundle includes only the standard gates")

  check(not runPublicFlow("Vanilla"), "a flavor without a task fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("no task selected", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "a flavor-only command cannot launch the engine's default checks")

  check(not runPublicFlow("--sequential", nil, false), "an option without a task fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("no task selected", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "an option-only command cannot launch the engine's default checks")

  check(not runPublicFlow("generate Unknown"), "an unknown public CLI token fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("unknown task or flavor: Unknown", 1, true) ~= nil,
    "an unknown token reports the bad value")

  check(not runPublicFlow("generate Vanilla --flavors=Mists"),
    "positional and option flavor selection conflict")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("positional flavors cannot be combined", 1, true) ~= nil,
    "the conflicting flavor selectors explain the correction")

  for _, badBudget in ipairs({ "", "0", "abc" }) do
    check(not runPublicFlow("generate --budget-mb=" .. badBudget, nil, false),
      "the public CLI rejects invalid budget " .. lib.show(badBudget))
    publicOutput = lib.readAll(outputPath)
    check(publicOutput:find("positive decimal integer", 1, true) ~= nil and
          publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
      "an invalid public budget fails before tools run: " .. lib.show(badBudget))
  end
  local oversizedBudget = "18446744073709551617"
  check(not runPublicFlow("generate --budget-mb=" .. oversizedBudget, nil, false),
    "the public CLI rejects a budget larger than Bash arithmetic can represent")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("must not exceed 2147483647 MB", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "an oversized public budget fails without wrapping or starting tools")

  check(runPublicFlow("validators Vanilla --budget-mb=02000"),
    "a leading-zero budget is normalized safely")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("budget 2000 MB", 1, true) ~= nil,
    "the normalized budget reaches the scheduler as decimal")

  local missingLua = rootAbs .. "/missing-lua"
  check(not runFlow("test --budget-mb=nope", nil, nil, nil, missingLua),
    "the direct engine rejects an invalid budget")
  output = lib.readAll(outputPath)
  check(output:find("positive decimal integer", 1, true) ~= nil and
        output:find("Lua interpreter not found", 1, true) == nil and
        output:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "direct budget validation runs before interpreter probes and jobs")

  check(not runFlow("test --budget-mb=" .. oversizedBudget, nil, nil, nil, missingLua),
    "the direct engine rejects an oversized budget")
  output = lib.readAll(outputPath)
  check(output:find("must not exceed 2147483647 MB", 1, true) ~= nil and
        output:find("Lua interpreter not found", 1, true) == nil and
        output:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "direct oversized-budget validation runs before interpreter probes and jobs")

  for _, mixedAll in ipairs({ "all verify", "verify all" }) do
    check(not runFlow(mixedAll .. " --flavors=Vanilla"),
      "the direct engine rejects mixed all ordering: " .. mixedAll)
    output = lib.readAll(outputPath)
    check(output:find("all cannot be combined", 1, true) ~= nil and
          not lib.fileExists(logPath),
      "mixed all fails before jobs regardless of order: " .. mixedAll)
  end
  check(not runPublicFlow("all verify Vanilla"), "the public CLI rejects all mixed with a task")

  check(runFlow("freeze"), "default freeze selects its supported flavors")
  log = lib.readAll(logPath)
  equal(#positionsOf(log, "verify.lua Vanilla --freeze"), 1,
    "default freeze includes Vanilla")
  equal(#positionsOf(log, "verify.lua Mists --freeze"), 1,
    "default freeze includes Mists")
  check(not runFlow("freeze --flavors=TBC"), "direct freeze rejects an unsupported flavor")
  output = lib.readAll(outputPath)
  check(output:find("freeze supports only Vanilla and Mists", 1, true) ~= nil and
        not lib.fileExists(logPath),
    "direct unsupported freeze fails before jobs")
  check(not runPublicFlow("freeze TBC"), "public freeze rejects an unsupported flavor")

  check(not runFlow("verify verify --flavors=Vanilla,Vanilla", false, true),
    "a duplicated failing direct job propagates failure")
  log = lib.readAll(logPath)
  output = lib.readAll(outputPath)
  equal(#positionsOf(log, "verify.lua Vanilla"), 1,
    "duplicate direct gates and flavors schedule one job")
  check(output:find("1 of 1 failed", 1, true) ~= nil,
    "the unique failing job cannot be overwritten by a duplicate success")

  check(runFlow("test", false, false, true),
    "an empty inherited LUA falls back to automatic discovery")
  log = lib.readAll(logPath)
  check(log:find("\ttest.lua", 1, true) ~= nil,
    "automatic discovery runs the selected gate")

  check(not runPublicFlow("test --lua=", nil, false),
    "an explicitly empty --lua fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("Lua interpreter not found: <empty>", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "explicit empty Lua fails before jobs")

  check(not runPublicFlow("test", rootAbs .. "/missing-lua"),
    "a missing explicit Lua interpreter fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("Lua interpreter not found", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "missing Lua fails before a job starts")

  check(not runPublicFlow("test", rootAbs .. "/wrong-lua"),
    "a wrong explicit Lua version fails")
  publicOutput = lib.readAll(outputPath)
  check(publicOutput:find("requires Lua 5.1", 1, true) ~= nil and
        publicOutput:find("Lua 5.4", 1, true) ~= nil and
        publicOutput:find("  start ", 1, true) == nil and not lib.fileExists(logPath),
    "wrong-version Lua fails before a job starts")

  commandSucceeded("rm -rf " .. shellQuote(root))
end)

--------------------------------------------------------------------------------------------
-- chunking
--------------------------------------------------------------------------------------------

suite("chunking", function()
  local function emit(value, maxLen)
    local path = ".out/test-chunk.toc"
    lib.mkdirp(".out")
    local out = assert(io.open(path, "wb"))
    out:write("## Interface: 11508\n\n")
    lib.writeMetadata(out, "X-T-1-1", value, maxLen)
    out:close()
    local map = emulator.parse(path)
    return emulator.getValue(map, "X-T-1-1"), map
  end

  equal(emit("short", 1000), "short", "short value is not chunked")

  local long = string.rep("a", 2500)
  local joined, map = emit(long, 1000)
  equal(joined, long, "long value reassembles exactly")
  equal(map["X-T-1-1"], "~3~", "base key holds the part count")
  equal(#map["X-T-1-1-1"], 1000, "first part is full width")

  -- Splits must not land inside a UTF-8 sequence. A wall of 3-byte characters puts a
  -- boundary at every possible offset relative to a 1000-byte limit.
  local multibyte = string.rep("‡", 900) -- U+2021, 3 bytes each => 2700 bytes
  local mbJoined, mbMap = emit(multibyte, 1000)
  equal(mbJoined, multibyte, "multibyte value reassembles exactly")
  for i = 1, tonumber(mbMap["X-T-1-1"]:match("%d+")) do
    local part = mbMap["X-T-1-1-" .. i]
    local firstByte = part:byte(1)
    check(firstByte < 0x80 or firstByte >= 0xC0,
      "chunk " .. i .. " starts on a UTF-8 continuation byte")
  end

  -- Every part except the last must be within the limit, and none may exceed it.
  for i = 1, tonumber(mbMap["X-T-1-1"]:match("%d+")) do
    check(#mbMap["X-T-1-1-" .. i] <= 1000, "chunk " .. i .. " exceeds the limit")
  end

  -- Key length counts against the same line budget as the value. A long key must shrink the
  -- parts, not push the line over the limit — the client truncates silently past it.
  local longKey = "X-l10n-Quest-1234567-2"
  local payload = string.rep("b", 5000)
  do
    local path = ".out/test-chunk.toc"
    local out = assert(io.open(path, "wb"))
    lib.writeMetadata(out, longKey, payload, 1000)
    out:close()
    local map = emulator.parse(path)
    equal(emulator.getValue(map, longKey), payload, "a long-keyed value reassembles exactly")

    local overLimit = 0
    local file = assert(io.open(path, "rb"))
    for line in file:lines() do
      if #line > lib.TOC_LINE_LIMIT then overLimit = overLimit + 1 end
    end
    file:close()
    equal(overLimit, 0, "no emitted line exceeds the client's line limit")
    os.remove(path)
  end

  -- And the same holds for every generated artifact on disk.
  for _, flavor in ipairs(config.flavors) do
    local tocPath = config.tocPath(flavor)
    if lib.fileExists(tocPath) then
      local overLimit, worst = 0, 0
      local file = assert(io.open(tocPath, "rb"))
      for line in file:lines() do
        if line:sub(1, 5) == "## X-" and #line > lib.TOC_LINE_LIMIT then
          overLimit = overLimit + 1
          if #line > worst then worst = #line end
        end
      end
      file:close()
      check(overLimit == 0, ("%s has %d lines over the %d-byte limit (worst %d)")
        :format(tocPath, overLimit, lib.TOC_LINE_LIMIT, worst))
    end
  end

  os.remove(".out/test-chunk.toc")
end)

--------------------------------------------------------------------------------------------
-- nil and empty semantics
--------------------------------------------------------------------------------------------

suite("semantics", function()
  local meta = {
    entity = "Test",
    fieldCount = 6,
    names = { "num", "str", "tbl", "pair", "fac", "idarray" },
    types = { "number", "string", "table", "table", "string", "table" },
    structures = { nil, nil, "questgivers", "pair", nil, "idarray" },
    emptyIsNil = { [3] = true, [4] = true, [6] = true },
    zeroPairIsNil = { [4] = true },
    normalize = { [5] = "faction" },
    keys = { num = 1, str = 2, tbl = 3, pair = 4, fac = 5, idarray = 6 },
  }

  equal(normalize.field(meta, 1, nil), 0, "number nil reads back as 0")
  equal(normalize.field(meta, 1, 0), 0, "number zero stays zero")
  equal(normalize.field(meta, 1, 42), 42, "number passes through")

  equal(normalize.field(meta, 2, nil), nil, "string nil stays nil")
  equal(normalize.field(meta, 2, ""), "", "empty string is distinct from nil")
  equal(normalize.field(meta, 2, "x"), "x", "string passes through")

  -- Field 3 is a `questgivers` structure, whose compiler reader always constructs a table, so
  -- it is one of the never-nil fields (ADR 0004). Field 6 is a plain idarray and keeps the
  -- ordinary rule, so both halves of the contract stay covered.
  equal(normalize.field(meta, 3, nil), {}, "never-nil structure: nil reads back as {}")
  equal(normalize.field(meta, 3, {}), {}, "never-nil structure: {} stays {}")
  equal(normalize.field(meta, 3, { 1 }), { 1 }, "non-empty table passes through")
  check(normalize.field(meta, 3, nil) ~= normalize.field(meta, 3, nil),
        "never-nil default is a fresh table per call, not a shared constant")

  equal(normalize.field(meta, 6, nil), nil, "ordinary table field: nil stays nil")
  equal(normalize.field(meta, 6, {}), nil, "ordinary table field: {} reads back as nil")
  equal(normalize.field(meta, 6, { 3 }), { 3 }, "ordinary table field passes through")

  equal(normalize.field(meta, 4, { 0, 0 }), nil, "pair {0,0} reads back as nil")
  equal(normalize.field(meta, 4, { 0, 5 }), { 0, 5 }, "pair {0,n} survives")
  equal(normalize.field(meta, 4, { 5, 0 }), { 5, 0 }, "pair {n,0} survives")

  equal(normalize.field(meta, 5, nil), nil, "faction nil")
  equal(normalize.field(meta, 5, ""), nil, "faction empty string collapses to nil")
  equal(normalize.field(meta, 5, "A"), "A", "faction A")
  equal(normalize.field(meta, 5, "H"), "H", "faction H")
  equal(normalize.field(meta, 5, "AH"), "AH", "faction AH")
  equal(normalize.field(meta, 5, "HA"), "AH", "faction HA normalizes to AH")

  equal(normalize.default(meta, 1), 0, "numeric default is 0")
  equal(normalize.default(meta, 2), nil, "string default is nil")
  equal(normalize.default(meta, 3), {}, "never-nil structure default is {}")
  equal(normalize.default(meta, 6), nil, "ordinary table default is nil")

  -- Encoding must agree: whatever reads back as a default is not written at all.
  equal(encode.field(meta, 1, nil), nil, "numeric nil writes no line")
  equal(encode.field(meta, 1, 0), nil, "numeric zero writes no line")
  equal(encode.field(meta, 1, 7), "7", "numeric value writes a line")
  equal(encode.field(meta, 3, {}), nil, "empty table writes no line")
  equal(encode.field(meta, 3, nil), nil, "never-nil structure still writes no line when absent")
  equal(encode.field(meta, 6, {}), nil, "ordinary empty table writes no line")
  equal(encode.field(meta, 4, { 0, 0 }), nil, "zero pair writes no line")
  equal(encode.field(meta, 2, ""), codec.EMPTY_STRING, "empty string writes its marker")

  -- Verification starts from an already-normalized value and uses this cheaper presence test
  -- instead of serializing the field again. Cover every omission class it depends on.
  check(not encode.hasStoredValue(meta, 1, 0), "normalized numeric zero needs no stored value")
  check(encode.hasStoredValue(meta, 1, 7), "normalized non-zero number needs a stored value")
  check(not encode.hasStoredValue(meta, 2, nil), "normalized nil string needs no stored value")
  check(encode.hasStoredValue(meta, 2, ""), "normalized empty string needs a stored value")
  check(not encode.hasStoredValue(meta, 3, {}), "normalized empty table needs no stored value")
  check(encode.hasStoredValue(meta, 3, { 1 }), "normalized populated table needs a stored value")
end)

--------------------------------------------------------------------------------------------
-- Deprecated constant fields
--------------------------------------------------------------------------------------------

suite("constant-fields", function()
  local schema = dofile("generator/schema.lua")
  local npcMeta = dofile("src/meta/npcMeta.lua")
  local minHealth = npcMeta.keys.minLevelHealth
  local maxHealth = npcMeta.keys.maxLevelHealth

  equal(minHealth, 2, "minLevelHealth keeps its positional index")
  equal(maxHealth, 3, "maxLevelHealth keeps its positional index")
  equal(npcMeta.constantValues[minHealth], 0, "minLevelHealth materializes placeholder 0")
  equal(npcMeta.constantValues[maxHealth], 1, "maxLevelHealth materializes placeholder 1")

  local compilerTypes = {}
  for fieldIndex = 1, npcMeta.fieldCount do
    compilerTypes[npcMeta.names[fieldIndex]] = npcMeta.compilerTypes[fieldIndex]
  end
  local derived = schema.derive({
    name = "Npc", metaPrefix = "Npc-", keysField = "npcKeys", typesField = "npcCompilerTypes",
  }, npcMeta.keys, compilerTypes)
  equal(derived.constantValues, { [2] = 0, [3] = 1 },
    "schema derivation resolves constant field names to stable indices")
  check(schema.render(derived):find("[2]=0, [3]=1", 1, true) ~= nil,
    "materialized schema renders both constant placeholders")

  schema.constantFields.Npc.unknownHealthField = 0
  local invalidConstant, invalidConstantError = pcall(schema.derive, {
    name = "Npc", metaPrefix = "Npc-", keysField = "npcKeys", typesField = "npcCompilerTypes",
  }, npcMeta.keys, compilerTypes)
  schema.constantFields.Npc.unknownHealthField = nil
  check(not invalidConstant and tostring(invalidConstantError):find("is not in the key enum", 1, true),
    "schema derivation rejects a constant whose canonical field name disappeared")

  equal(normalize.field(npcMeta, minHealth, 12345), 0,
    "minLevelHealth ignores an obsolete source value")
  equal(normalize.field(npcMeta, maxHealth, 67890), 1,
    "maxLevelHealth ignores an obsolete source value")
  equal(normalize.default(npcMeta, minHealth), 0,
    "minLevelHealth reconstructs from missing storage")
  equal(normalize.default(npcMeta, maxHealth), 1,
    "maxLevelHealth reconstructs its non-zero placeholder from missing storage")
  equal(encode.field(npcMeta, minHealth, 12345), nil,
    "minLevelHealth emits no metadata for a non-zero source value")
  equal(encode.field(npcMeta, maxHealth, 67890), nil,
    "maxLevelHealth emits no metadata for a non-zero source value")
  check(not encode.hasStoredValue(npcMeta, maxHealth, 1),
    "Verification shares Generation's constant-field omission rule")

  ---Checks every public read form for the deprecated health placeholders.
  ---@param Lib table Loaded QuestieTDB namespace.
  ---@param label string Read mode shown in assertion failures.
  ---@return nil
  local function checkHealthPlaceholders(Lib, label)
    equal(Lib.Npc.minLevelHealth(30), 0, label .. ": named minimum health is the placeholder")
    equal(Lib.Npc.maxLevelHealth(30), 1, label .. ": named maximum health is the placeholder")
    equal(Lib.Npc.Get(30, "minLevelHealth"), 0, label .. ": Get returns minimum placeholder")
    equal(Lib.Npc.Get(30, "maxLevelHealth"), 1, label .. ": Get returns maximum placeholder")
    equal(Lib.Npc.GetByIndex(30, minHealth), 0,
      label .. ": GetByIndex returns minimum placeholder")
    equal(Lib.Npc.GetByIndex(30, maxHealth), 1,
      label .. ": GetByIndex returns maximum placeholder")
    equal(Lib.Npc.GetRaw(30, "minLevelHealth"), 0,
      label .. ": GetRaw returns minimum placeholder")
    equal(Lib.Npc.GetRaw(30, "maxLevelHealth"), 1,
      label .. ": GetRaw returns maximum placeholder")
    equal(Lib.Npc.GetAll(30, { "minLevelHealth", "maxLevelHealth" }), { 0, 1, n = 2 },
      label .. ": GetAll returns both placeholders")
    equal(Lib.Npc.minLevelHealth(999999999), nil, label .. ": unknown NPC named getter is nil")
    equal(Lib.Npc.Get(999999999, "maxLevelHealth"), nil, label .. ": unknown NPC Get is nil")
    equal(Lib.Npc.GetRaw(999999999, maxHealth), nil, label .. ": unknown NPC GetRaw is nil")
  end

  client.reset()
  client.install({ expansion = "Classic" })
  local source = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
  checkHealthPlaceholders(source, "source")

  source.Corrections.RegisterRuntimeCorrection("ConstantFieldSourceTest", "Npc", "ignored-health",
    function()
      return { [30] = { [minHealth] = 9000, [maxHealth] = {} } }
    end, 10)
  source.Corrections.ApplyRegisteredCorrections("ConstantFieldSourceTest")
  equal(source.Npc.minLevelHealth(30), 0,
    "source: a Dynamic Correction cannot replace the minimum placeholder")
  equal(source.Npc.maxLevelHealth(30), 1,
    "source: a Dynamic Correction cannot delete the maximum placeholder")
  equal(source.GetProvenance("Npc", 30, "minLevelHealth"), source.Corrections.OWNER,
    "source: ignored constant writes do not claim provenance")

  -- A tiny Baked artifact proves conflicting legacy metadata is unreadable and the
  -- constants reconstruct without generating or checking in a flavor-sized TOC.
  local fixturePath = ".out/test-constant-fields.toc"
  lib.mkdirp(".out")
  local previousManifest = config.correctionManifest
  config.correctionManifest = dofile("src/corrections/manifest.lua")
  local lines = {
    "## Interface: 11508",
    "## X-Flavor: Vanilla",
    "## X-Contract-Version: " .. tostring(config.contractVersion),
    "## X-Npc-IDS-LIST: 30",
    "## X-Npc-30-2: 9000",
    "## X-Npc-30-3: 9001",
    "",
  }
  for _, file in ipairs(config.bakedFileList(config.flavorByName.Vanilla)) do
    lines[#lines + 1] = file
  end
  lib.writeAll(fixturePath, table.concat(lines, "\n") .. "\n")

  client.reset()
  client.install({ expansion = "Classic" })
  emulator.install(config.addonName, emulator.parse(fixturePath))
  local baked = emulator.loadAddon(fixturePath, config.addonName)
  checkHealthPlaceholders(baked, "baked")

  local constantOnlyId = 4999998
  local mixedId = 4999997
  baked.Corrections.RegisterRuntimeCorrection("ConstantFieldTest", "Npc", "ignored-health",
    function()
      return {
        [30] = { [minHealth] = 9000, [maxHealth] = {} },
        [constantOnlyId] = { [minHealth] = 9000, [maxHealth] = 9001 },
        [mixedId] = { [1] = "Synthetic NPC", [minHealth] = 9000, [maxHealth] = 9001 },
      }
    end, 10)
  baked.Corrections.ApplyRegisteredCorrections("ConstantFieldTest")
  equal(baked.Npc.minLevelHealth(30), 0,
    "a Dynamic Correction cannot replace the minimum placeholder")
  equal(baked.Npc.maxLevelHealth(30), 1,
    "a Dynamic Correction cannot delete the maximum placeholder")
  equal(baked.GetProvenance("Npc", 30, "minLevelHealth"), baked.Corrections.OWNER,
    "ignored constant writes do not claim provenance")
  equal(baked.Npc.Exists(constantOnlyId), false,
    "a constant-only Dynamic Correction does not invent an NPC")
  equal(baked.Npc.Get(constantOnlyId, "minLevelHealth"), nil,
    "the ignored constant-only NPC still reads nil")
  equal(baked.Npc.Exists(mixedId), true,
    "a legitimate nonconstant field creates a mixed synthetic NPC")
  equal(baked.Npc.name(mixedId), "Synthetic NPC",
    "the mixed synthetic NPC keeps its nonconstant correction")
  equal(baked.Npc.minLevelHealth(mixedId), 0,
    "the mixed synthetic NPC ignores corrected minimum health")
  equal(baked.Npc.maxLevelHealth(mixedId), 1,
    "the mixed synthetic NPC ignores corrected maximum health")
  equal(baked.GetProvenance("Npc", mixedId, "name"), "ConstantFieldTest",
    "only the mixed NPC's legitimate field claims provenance")
  equal(baked.GetProvenance("Npc", mixedId, "maxLevelHealth"), baked.Corrections.OWNER,
    "the mixed NPC's ignored health field keeps database provenance")

  os.remove(fixturePath)
  config.correctionManifest = previousManifest
  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Negative controls
--------------------------------------------------------------------------------------------
--
-- A check that cannot fail is not a check. Each of these mutates a generated artifact and
-- asserts the failure is caught.

suite("negative-controls", function()
  local flavor = config.flavorByName.Vanilla
  local sourceToc = config.tocPath(flavor)
  if not lib.fileExists(sourceToc) then
    io.write("  SKIP negative-controls: ", sourceToc, " not generated\n")
    return
  end

  lib.mkdirp(".out/corrupt")
  local original = lib.readAll(sourceToc)

  local function runVerify(content, label)
    lib.writeAll(".out/corrupt/" .. sourceToc, content)
    local command = shellQuote(LUA_BIN) ..
      " verify.lua Vanilla --toc-dir=.out/corrupt --quiet >/dev/null 2>&1"
    local ok, kind, code = os.execute(command)
    -- Lua 5.1 returns the raw exit status; 5.2+ returns ok, "exit", code.
    local failed
    if type(ok) == "number" then failed = ok ~= 0 else failed = not ok end
    check(failed, "verify.lua accepted a corrupted TOC: " .. label)
  end

  -- 1. A changed value must be caught.
  local changed = original:gsub("## X%-Quest%-2%-1: [^\n]*", "## X-Quest-2-1: Definitely Not Sharptalon", 1)
  check(changed ~= original, "corruption fixture did not apply (changed value)")
  runVerify(changed, "changed quest name")

  -- 2. A deleted line must be caught.
  local deleted = original:gsub("## X%-Quest%-2%-1: [^\n]*\n", "", 1)
  check(deleted ~= original, "corruption fixture did not apply (deleted line)")
  runVerify(deleted, "deleted quest name")

  -- 3. A truncated ID list must be caught.
  local truncated = original:gsub("(## X%-Quest%-IDS%-LIST%-1: %d+),%d+", "%1", 1)
  check(truncated ~= original, "corruption fixture did not apply (truncated id list)")
  runVerify(truncated, "truncated id list")

  -- 4. A missing chunk part must raise rather than return a short string. Pick the first
  -- eligible key deterministically so this control fails the same field on every run.
  local map = emulator.parse(sourceToc)
  local chunkKey
  for key, value in pairs(map) do
    local partCount = tonumber(value:match("^~(%d+)~$"))
    if partCount and partCount >= 2 and map[key .. "-2"] ~= nil and
       (not chunkKey or key < chunkKey) then
      chunkKey = key
    end
  end
  if chunkKey then
    map[chunkKey .. "-2"] = nil
    client.reset()
    client.install({ expansion = "Classic" })
    emulator.install(config.addonName, map)
    local addon = emulator.loadAddon(sourceToc, config.addonName)
    local ok = pcall(addon.read.baked.getStored, chunkKey)
    check(not ok, "a missing chunk part was silently tolerated")
  else
    check(false, "no chunked value found to corrupt")
  end

  -- Later suites share the client emulator, so restore valid metadata after the intentional
  -- corruption instead of relying on their setup order to replace this global accessor.
  client.reset()
  client.install({ expansion = "Classic" })
  emulator.install(config.addonName, emulator.parse(sourceToc))

  os.remove(".out/corrupt/" .. sourceToc)
end)

--------------------------------------------------------------------------------------------
-- Corrections
--------------------------------------------------------------------------------------------

suite("corrections", function()
  local runtime = dofile("generator/runtime.lua")
  local flavor = config.flavorByName.Vanilla

  local Lib = runtime.build()
  check(Lib.CorrectionManifest ~= nil, "the correction manifest loaded")
  if not Lib.CorrectionManifest then return end

  -- Expansion gating mirrors QuestieCorrections:Initialize: the four Era fix files apply
  -- unconditionally on every expansion (upstream runs their Load()s ungated and layers
  -- TBC+ fixes on top by floor); ONLY the reputation fixes sit behind `if Questie.IsClassic`.
  -- Classic-gating the four stripped every Era-inherited static out of the TBC+ artifacts —
  -- caught by the cross-implementation differential, invisible to verify/equivalence.
  local ungatedEraFiles = {
    ["Era/classicQuestFixes.lua"] = true, ["Era/classicNPCFixes.lua"] = true,
    ["Era/classicItemFixes.lua"] = true, ["Era/classicObjectFixes.lua"] = true,
  }
  local wotlkNpcSpec
  for _, entry in ipairs(Lib.CorrectionManifest) do
    if ungatedEraFiles[entry.file] then
      equal(entry.expansions, nil, "Era fix file is not expansion-gated: " .. entry.file)
    elseif entry.file == "Era/classicQuestReputationFixes.lua" then
      check(entry.expansions and entry.expansions.Classic == true,
        "reputation fixes stay Classic-gated, per upstream's explicit IsClassic branch")
    elseif entry.file == "Wotlk/wotlkNPCFixes.lua" then
      wotlkNpcSpec = entry
    end
    if entry.static and not entry.generated then
      check(type(entry.sourceExpansionOrder or entry.minExpansionOrder) == "number",
        "a flavor-owned Static Correction records or implies its source expansion: " .. entry.file)
    end
  end
  check(wotlkNpcSpec ~= nil, "WotLK NPC Correction manifest entry exists")
  if wotlkNpcSpec then
    equal(wotlkNpcSpec.static, { "LoadAutomatics", "Load" },
      "WotLK NPC statics preserve Questie's automatic-then-hand-authored order")
  end

  local registry = Lib.Corrections
  local previousQuestie = rawget(_G, "Questie")
  rawset(_G, "Questie", nil)
  runtime.loadCorrections(Lib, flavor)
  equal(rawget(_G, "Questie"), nil,
    "loading correction files leaves Questie's global unclaimed")

  -- Copied providers borrow a private Questie table and restore the consumer's exact value.
  local consumerQuestie = { marker = "consumer-owned" }
  rawset(_G, "Questie", consumerQuestie)
  local invokedQuestie
  local returned = Lib.CorrectionCompat.Invoke(function()
    invokedQuestie = rawget(_G, "Questie")
    return { icon = Questie.ICON_TYPE_EVENT }
  end)
  equal(returned.icon, 3, "the invocation-scoped shim supplies Questie's icon constants")
  check(invokedQuestie ~= consumerQuestie,
    "a provider sees the private stand-in rather than the consumer's table")
  check(rawget(_G, "Questie") == consumerQuestie,
    "successful invocation restores a pre-existing Questie table by identity")
  equal(consumerQuestie, { marker = "consumer-owned" },
    "the invocation shim does not augment the consumer's Questie table")

  local invokeOk, invokeErr = pcall(Lib.CorrectionCompat.Invoke, function()
    error("correction provider failed", 0)
  end)
  check(not invokeOk and tostring(invokeErr):find("correction provider failed", 1, true) ~= nil,
    "provider errors are rethrown after cleanup")
  check(rawget(_G, "Questie") == consumerQuestie,
    "failed invocation restores a pre-existing Questie table by identity")
  rawset(_G, "Questie", previousQuestie)

  local questieFields = {}
  for _, spec in ipairs(Lib.CorrectionManifest) do
    local content = lib.readAll("src/corrections/" .. spec.file)
    for field in content:gmatch("Questie%.([%a_][%w_]*)") do questieFields[field] = true end
  end
  check(next(questieFields) ~= nil, "copied correction files contain direct Questie references")
  for field in pairs(questieFields) do
    check(Lib.Enum.iconTypes[field] ~= nil,
      "the invocation shim declares directly referenced Questie field " .. field)
  end

  local entries = registry.Select({})
  check(#entries > 0, "corrections registered")

  -- Every registration carries an owner, a datatype, a name and a load order.
  for _, entry in ipairs(entries) do
    check(entry.owner == registry.OWNER, "entry has an owner: " .. tostring(entry.name))
    check(type(entry.datatype) == "string", "entry has a datatype: " .. tostring(entry.name))
    check(type(entry.name) == "string", "entry has a name")
    check(type(entry.loadOrder) == "number", "entry has a load order: " .. tostring(entry.name))
    check(type(entry.func) == "function",
      "correction data is held behind a function, not materialised at load: " .. tostring(entry.name))
  end

  -- Season of Discovery must apply *after* Era's faction fixes. The prototype passed a literal
  -- 70 instead of SoDBaseDynamicOrder, so despite the comment "Sod will always load last" it
  -- applied first. Load-order constants make that unrepresentable; this asserts it.
  local eraDynamic, sodDynamic
  for _, entry in ipairs(entries) do
    if entry.name:find("^Era/") and entry.dynamic then eraDynamic = entry.loadOrder end
    if entry.name:find("^Sod/") and entry.dynamic then sodDynamic = sodDynamic or entry.loadOrder end
  end
  if eraDynamic and sodDynamic then
    check(sodDynamic > eraDynamic,
      ("SoD dynamic corrections must apply after Era's (SoD %s, Era %s)")
        :format(tostring(sodDynamic), tostring(eraDynamic)))
  end

  -- Load-order collisions are reported, not silently overwritten, and both entries survive.
  local before = #registry.Select({ datatype = "Quest", dynamic = false })
  registry.RegisterCorrection("TestOwner", "Quest", "collide-a", function() return {} end, 42)
  registry.RegisterCorrection("TestOwner", "Quest", "collide-b", function() return {} end, 42)
  local after = #registry.Select({ datatype = "Quest", dynamic = false })
  equal(after, before + 2, "a load-order collision keeps both entries")
  local ordered = registry.Select({ owner = "TestOwner", datatype = "Quest", dynamic = false })
  equal(ordered[1].name, "collide-a", "a collision breaks ties on registration order")
  equal(ordered[2].name, "collide-b", "the second registrant applies second")

  -- Withdrawing a correction actually removes it, which the previous merge-only approach
  -- could not do.
  check(registry.UnregisterCorrection("TestOwner", "Quest", "collide-a"), "withdrawal reports success")
  equal(#registry.Select({ owner = "TestOwner", datatype = "Quest", dynamic = false }), 1,
    "a withdrawn correction is gone from the registry")

  -- Deleting a correction and regenerating removes its effect. Applying to a scratch table
  -- with and without one entry is the same observation without a 30-second regeneration.
  local scratch = {}
  registry.RegisterCorrection("TestOwner", "Quest", "scratch", function()
    return { [999001] = { [1] = "Injected Quest" } }
  end, 43)
  registry.ApplyStaticToEntities("Quest", scratch, flavor, "TestOwner")
  equal(scratch[999001] and scratch[999001][1], "Injected Quest", "a Static Correction reaches base data")

  local scratch2 = {}
  registry.UnregisterCorrection("TestOwner", "Quest", "scratch")
  registry.ApplyStaticToEntities("Quest", scratch2, flavor, "TestOwner")
  equal(scratch2[999001], nil, "deleting the correction removes its effect")

  -- Questie prevents an older expansion's Correction from resurrecting an entity removed by
  -- the target expansion. Field 1 is the exception: a named row defines a genuinely missing
  -- entity and may still be created.
  local inheritedField = registry.RegisterCorrection("InheritanceTest", "Quest", "field-only",
    function() return { [999101] = { [5] = 42 } } end, 44)
  inheritedField.sourceExpansionOrder = 1
  local inheritedNamed = registry.RegisterCorrection("InheritanceTest", "Quest", "named",
    function() return { [999102] = { [1] = "Defined Missing Quest", [5] = 42 } } end, 45)
  inheritedNamed.sourceExpansionOrder = 1

  local inheritedTarget = {}
  registry.ApplyStaticToEntities(
    "Quest", inheritedTarget, config.flavorByName.TBC, "InheritanceTest")
  equal(inheritedTarget[999101], nil,
    "an inherited field-only Correction does not create an absent entity")
  equal(inheritedTarget[999102] and inheritedTarget[999102][1], "Defined Missing Quest",
    "an inherited named Correction may create an absent entity")

  local sourceTarget = {}
  registry.ApplyStaticToEntities(
    "Quest", sourceTarget, config.flavorByName.Vanilla, "InheritanceTest")
  equal(sourceTarget[999101] and sourceTarget[999101][5], 42,
    "a same-expansion Correction keeps normal entity creation")

  local explicitNoNew = {}
  registry.MergeInto(explicitNoNew, {
    [999103] = { [5] = 42 },
    [999104] = { [1] = "Named Merge Exception" },
  }, { noNewEntries = true })
  equal(explicitNoNew[999103], nil, "noNewEntries skips an unnamed absent entity")
  equal(explicitNoNew[999104], nil, "noNewEntries also skips a named absent entity")

  -- The delete idiom: an empty table reads back as nil, so writing {} clears a field.
  local meta = Lib.Meta.Quest
  equal(Lib.Meta.normalize.field(meta, meta.keys.preQuestSingle, {}), nil,
    "a correction setting a table field to {} clears it")

  -- Static-only correction files are excluded from the shipped artifact.
  local baked = config.bakedFileList(flavor)
  local bakedSet = {}
  for _, file in ipairs(baked) do bakedSet[file] = true end
  local staticOnly, shipped = 0, 0
  for _, spec in ipairs(Lib.CorrectionManifest) do
    if not (spec.dynamic and #spec.dynamic > 0) then
      staticOnly = staticOnly + 1
      if bakedSet["src/corrections/" .. spec.file] then shipped = shipped + 1 end
    end
  end
  check(staticOnly > 0, "there are static-only correction files to exclude")
  equal(shipped, 0, "no static-only correction file is listed in a baked artifact")

  -- Expansion-varying constants. Upstream evaluates these under the client's expansion flags
  -- (QuestieDB.lua:122-150 raceKeys, :178-191 classKeys; npcDB.lua:63-75 npcFlags), so the
  -- enum carries them per expansion and the compat shim serves the flavor's own set — Era
  -- correction files apply on every expansion, and a frozen Era mask would bake wrong values
  -- into TBC+ artifacts (440 TBC divergences before this, per the differential).
  local enum = Lib.Enum
  check(enum.byExpansion ~= nil, "the enum carries per-expansion constants")
  equal(enum.raceKeys.ALL_ALLIANCE, 77, "flat race mask stays the Era value")
  equal(enum.npcFlags.REPAIR, 16384, "flat REPAIR stays the Era value")
  equal(enum.byExpansion.TBC.raceKeys.ALL_ALLIANCE, 1101, "TBC ALL_ALLIANCE per QuestieDB.lua")
  equal(enum.byExpansion.TBC.raceKeys.ALL_HORDE, 690, "TBC ALL_HORDE per QuestieDB.lua")
  equal(enum.byExpansion.Cata.raceKeys.ALL_ALLIANCE, 2098253, "Cata ALL_ALLIANCE adds Worgen")
  equal(enum.byExpansion.TBC.npcFlags.REPAIR, 4096, "TBC REPAIR per npcDB.lua IsClassic branch")
  equal(enum.byExpansion.Wotlk.npcFlags.BARBER, 33554432, "BARBER exists from Wotlk")
  equal(enum.npcFlags.BARBER, nil, "BARBER absent on Era, as upstream nils it")
  equal(enum.byExpansion.TBC.classKeys.ALL_CLASSES, 1503, "TBC ALL_CLASSES per QuestieDB.lua")
  equal(enum.byExpansion.MoP.classKeys.ALL_CLASSES, 2047, "MoP ALL_CLASSES per QuestieDB.lua")

  -- And the shim actually serves them: a TBC prepare must hand correction files TBC masks,
  -- while the Vanilla prepare above keeps Era masks.
  local corrections = dofile("generator/corrections.lua")
  local tbcContext = corrections.prepare(config.flavorByName.TBC)
  local tbcDB = tbcContext.lib.CorrectionCompat.modules.QuestieDB
  equal(tbcDB.raceKeys.ALL_ALLIANCE, 1101, "compat serves TBC race masks to a TBC flavor")
  equal(tbcDB.npcFlags.REPAIR, 4096, "compat serves TBC npc flags to a TBC flavor")
  local eraContext = corrections.prepare(flavor)
  equal(eraContext.lib.CorrectionCompat.modules.QuestieDB.raceKeys.ALL_ALLIANCE, 77,
    "compat serves Era race masks to the Vanilla flavor")

  -- Pinned Questie applies WotLK's automatic NPC rows first and the hand-authored Load()
  -- second. NPC 30208 exists in both: the automatic set adds a spawn, then Load() deletes it.
  -- This real overlap catches a manifest that lists both valid functions in the wrong order.
  local wrath = config.flavorByName.Wrath
  local wrathContext = corrections.prepare(wrath)
  local wrathNpcs = { [30208] = { [1] = "Stormforged Ambusher" } }
  wrathContext.lib.Corrections.ApplyStaticToEntities(
    "Npc", wrathNpcs, wrath, wrathContext.lib.Corrections.OWNER)
  local finalSpawns = wrathNpcs[30208][7]
  check(type(finalSpawns) == "table" and next(finalSpawns) == nil,
    "WotLK hand-authored NPC spawn deletion wins over LoadAutomatics")

  -- Exercise the shipped source-mode load order, including _begin.lua, _end.lua, and the
  -- initial correction application in api.lua. Questie must be free to claim its own global
  -- immediately afterwards, while deferred providers must still resolve their icon constants.
  client.reset()
  client.install({ expansion = "Classic" })
  local sourceLib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
  local objectives = sourceLib.Quest.Get(28, "objectives")
  equal(objectives and objectives[2] and objectives[2][1] and objectives[2][1][3], 3,
    "source-mode corrections still resolve Questie's event icon")
  equal(rawget(_G, "Questie"), nil,
    "loading the QuestieTDB addon leaves no Questie compatibility global")
  client.reset()

  -- Packaging invokes surviving Dynamic providers to compare staged and original behavior.
  -- Cata's faction provider reads an icon constant, so this catches any packaging path that
  -- bypasses the same invocation scope used by the runtime registry.
  local stripStage = ".out/test-strip-static/QuestieTDB"
  commandSucceeded("rm -rf " .. shellQuote(stripStage))
  lib.mkdirp(stripStage .. "/src/corrections/Cata")
  lib.copyFile("src/corrections/Cata/cataQuestFixes.lua",
    stripStage .. "/src/corrections/Cata/cataQuestFixes.lua")
  check(commandSucceeded(shellQuote(LUA_BIN) .. " tools/strip-static.lua " ..
    shellQuote(stripStage) .. " --quiet"),
    "package stripping invokes copied providers through the scoped Questie shim")
  commandSucceeded("rm -rf " .. shellQuote(stripStage))
end)

--------------------------------------------------------------------------------------------
-- Derived requiredRaces compatibility
--------------------------------------------------------------------------------------------

suite("derived-required-races", function()
  local runtime = dofile("generator/runtime.lua")
  local Lib = runtime.build()
  local inference = Lib.DerivedRequiredRaces
  local questKeys = Lib.Meta.Quest.keys
  local npcKeys = Lib.Meta.Npc.keys

  ---Builds the ordinary Derived Pass context around literal synthetic rows.
  ---@param quests table<integer, table>
  ---@param npcs table<integer, table>
  ---@param flavor table
  ---@return RequiredRacesDerivedContext context
  local function inferenceContext(quests, npcs, flavor)
    ---@param entityType string
    ---@return table? entities
    local function entities(entityType)
      if entityType == "Quest" then return quests end
      if entityType == "Npc" then return npcs end
      return nil
    end

    ---@param entityType string
    ---@return table? meta
    local function meta(entityType)
      return Lib.Meta[entityType]
    end

    return { flavor = flavor, entities = entities, meta = meta }
  end

  check(type(inference.ApplyQuestieCompatibility) == "function",
    "the Questie compatibility function is published")
  check(type(inference.ApplyCorrectedInference) == "function",
    "the corrected conservative function is published")

  local registered
  local correctedRegistered = false
  for _, pass in ipairs(Lib.Derived.Select("Quest")) do
    if pass.name == "requiredRaces:questieCompatibility" then registered = pass end
    if pass.run == inference.ApplyCorrectedInference then correctedRegistered = true end
  end
  check(registered ~= nil, "the requiredRaces compatibility pass is registered")
  if registered then
    equal(registered.reads, { "Quest", "Npc" },
      "the compatibility pass declares its cross-entity inputs")
    equal(registered.order, 50, "requiredRaces has the declared order before waypoint passes")
    check(registered.run == inference.ApplyQuestieCompatibility,
      "registration uses the exact Questie transcription")
  end
  equal(correctedRegistered, false, "the corrected policy remains deliberately unregistered")

  -- These rows make Questie's permissive guesses visible. The opposite-faction object and
  -- item starters prove the loop reads startedBy[1], while sparse creature evidence proves it
  -- retains upstream's `pairs` iteration rather than silently becoming `ipairs`.
  local questieQuests = {
    [1001] = { [questKeys.startedBy] = { { 1 } } },
    [1002] = { [questKeys.startedBy] = { { 1 } }, [questKeys.requiredRaces] = 0 },
    [1003] = { [questKeys.startedBy] = { { 1, 999 } } },
    [1004] = { [questKeys.startedBy] = { { 1 }, { 2 } } },
    [1005] = { [questKeys.startedBy] = { { 1 }, nil, { 2 } } },
    [1006] = { [questKeys.startedBy] = { { 1, 3 } } },
    [1007] = { [questKeys.startedBy] = { { 1, 2 } } },
    [1008] = { [questKeys.startedBy] = { { 1 } }, [questKeys.requiredRaces] = 77 },
    [1009] = { [questKeys.startedBy] = { { 2, 4 } } },
    [1010] = { [questKeys.startedBy] = { { 1, 5 } } },
    [1011] = { [questKeys.startedBy] = { { [2] = 1 } } },
  }
  local npcs = {
    [1] = { [npcKeys.friendlyToFaction] = "H" },
    [2] = { [npcKeys.friendlyToFaction] = "A" },
    [3] = { [npcKeys.friendlyToFaction] = "AH" },
    [4] = { [npcKeys.friendlyToFaction] = "A" },
    [5] = { [npcKeys.friendlyToFaction] = "unknown" },
  }
  inference.ApplyQuestieCompatibility(
    inferenceContext(questieQuests, npcs, config.flavorByName.Vanilla))

  equal(questieQuests[1001][questKeys.requiredRaces], 178,
    "Questie infers Horde from one Horde creature starter")
  equal(questieQuests[1002][questKeys.requiredRaces], 178,
    "Questie overwrites an explicit zero")
  equal(questieQuests[1003][questKeys.requiredRaces], 178,
    "Questie ignores a missing NPC beside Horde evidence")
  equal(questieQuests[1004][questKeys.requiredRaces], 178,
    "Questie ignores an Alliance object starter beside Horde creature evidence")
  equal(questieQuests[1005][questKeys.requiredRaces], 178,
    "Questie ignores an Alliance item starter beside Horde creature evidence")
  equal(questieQuests[1006][questKeys.requiredRaces], nil,
    "an AH starter adds both flags and cancels Horde-only inference")
  equal(questieQuests[1007][questKeys.requiredRaces], nil,
    "mixed Alliance and Horde starters prevent Questie inference")
  equal(questieQuests[1008][questKeys.requiredRaces], 77,
    "Questie preserves every nonzero authored mask")
  equal(questieQuests[1009][questKeys.requiredRaces], 77,
    "unanimous Alliance creature starters infer Alliance")
  equal(questieQuests[1010][questKeys.requiredRaces], 178,
    "Questie ignores an unknown faction value beside Horde evidence")
  equal(questieQuests[1011][questKeys.requiredRaces], 178,
    "Questie reads a sparse creature starter list with pairs")

  local maskCases = {
    { flavor = config.flavorByName.Vanilla, alliance = 77, horde = 178 },
    { flavor = config.flavorByName.TBC, alliance = 1101, horde = 690 },
    { flavor = config.flavorByName.Wrath, alliance = 1101, horde = 690 },
    { flavor = config.flavorByName.Cata, alliance = 2098253, horde = 946 },
    { flavor = config.flavorByName.Mists, alliance = 18875469, horde = 33555378 },
  }
  for _, case in ipairs(maskCases) do
    local quests = {
      [2001] = { [questKeys.startedBy] = { { 1 } } },
      [2002] = { [questKeys.startedBy] = { { 2 } } },
    }
    inference.ApplyQuestieCompatibility(inferenceContext(quests, npcs, case.flavor))
    equal(quests[2001][questKeys.requiredRaces], case.horde,
      case.flavor.name .. " uses its literal ALL_HORDE mask")
    equal(quests[2002][questKeys.requiredRaces], case.alliance,
      case.flavor.name .. " uses its literal ALL_ALLIANCE mask")
  end

  -- The parked policy requires complete, faction-exclusive evidence and preserves explicit
  -- author intent. Side-by-side fixtures make every deliberate divergence reviewable.
  local correctedQuests = {
    [3001] = { [questKeys.startedBy] = { { 1 } } },
    [3002] = { [questKeys.startedBy] = { { 1 } }, [questKeys.requiredRaces] = 0 },
    [3003] = { [questKeys.startedBy] = { { 1, 999 } } },
    [3004] = { [questKeys.startedBy] = { { 1 }, { 2 } } },
    [3005] = { [questKeys.startedBy] = { { 1 }, nil, { 2 } } },
    [3006] = { [questKeys.startedBy] = { { 1, 3 } } },
    [3007] = { [questKeys.startedBy] = { { 1, 2 } } },
    [3008] = { [questKeys.startedBy] = { { 1 } }, [questKeys.requiredRaces] = 77 },
    [3009] = { [questKeys.startedBy] = { { 2, 4 } } },
    [3010] = { [questKeys.startedBy] = { { 1, 5 } } },
  }
  inference.ApplyCorrectedInference(
    inferenceContext(correctedQuests, npcs, config.flavorByName.Vanilla))

  equal(correctedQuests[3001][questKeys.requiredRaces], 178,
    "corrected policy infers from complete Horde evidence")
  equal(correctedQuests[3002][questKeys.requiredRaces], 0,
    "corrected policy preserves an explicit zero")
  equal(correctedQuests[3003][questKeys.requiredRaces], nil,
    "corrected policy refuses unresolved creature starters")
  equal(correctedQuests[3004][questKeys.requiredRaces], nil,
    "corrected policy refuses an object access path")
  equal(correctedQuests[3005][questKeys.requiredRaces], nil,
    "corrected policy refuses an item access path")
  equal(correctedQuests[3006][questKeys.requiredRaces], nil,
    "corrected policy refuses an AH starter")
  equal(correctedQuests[3007][questKeys.requiredRaces], nil,
    "corrected policy refuses mixed factions")
  equal(correctedQuests[3008][questKeys.requiredRaces], 77,
    "corrected policy preserves a nonzero mask")
  equal(correctedQuests[3009][questKeys.requiredRaces], 77,
    "corrected policy accepts unanimous resolved Alliance starters")
  equal(correctedQuests[3010][questKeys.requiredRaces], nil,
    "corrected policy refuses an unknown faction value")

  -- Dependency expansion is generic rather than coupled to requiredRaces. The synthetic chain
  -- proves transitive closure and flavor gating without modifying the runtime registry above.
  local dependencyRegistry = dofile("src/derived/registry.lua")
  ---@return nil
  local function noOpPass() end
  -- Reverse dependency order forces expansion to revisit earlier passes. A single scan can
  -- discover Npc from Quest, but cannot reach Item or Object.
  dependencyRegistry.Register({
    name = "test:item-needs-object-in-mop", writes = "Item", reads = { "Item", "Object" },
    expansions = { MoP = true }, run = noOpPass,
  })
  dependencyRegistry.Register({
    name = "test:npc-needs-item", writes = "Npc", reads = { "Npc", "Item" },
    run = noOpPass,
  })
  dependencyRegistry.Register({
    name = "test:quest-needs-npc", writes = "Quest", reads = { "Quest", "Npc" },
    run = noOpPass,
  })

  local requested = { Quest = true }
  equal(dependencyRegistry.ExpandReadDependencies(requested, config.flavorByName.Vanilla),
    { Quest = true, Npc = true, Item = true },
    "dependency expansion reaches a fixed point and honors a closed flavor gate")
  equal(dependencyRegistry.ExpandReadDependencies(requested, config.flavorByName.Mists),
    { Quest = true, Npc = true, Item = true, Object = true },
    "dependency expansion includes a transitive pass active for the flavor")
  equal(requested, { Quest = true }, "dependency expansion does not mutate the output filter")

  local flavorLoader = dofile("generator/flavor.lua")
  local loaded = flavorLoader.load(config.flavorByName.Vanilla, { Quest = true })
  check(loaded.Quest ~= nil, "Quest-only Generation returns the requested Quest output")
  equal(loaded.Npc, nil, "Quest-only Generation does not return its Npc input")
  equal(loaded.Item, nil, "Quest-only Generation does not return unrelated Item data")
  equal(loaded.Object, nil, "Quest-only Generation does not return unrelated Object data")
  equal(loaded.Quest.entities[7162][questKeys.requiredRaces], 77,
    "Quest-only Generation infers quest 7162 from its corrected Npc input")

  -- Raw loading does not run Corrections or Derived Passes, so it needs no dependency inputs.
  local rawRequested = { Quest = true }
  local rawLoaded, rawStats = flavorLoader.load(
    config.flavorByName.Vanilla, rawRequested, false)
  check(rawLoaded.Quest ~= nil, "raw Quest-only loading returns the requested Quest output")
  equal(rawLoaded.Npc, nil, "raw Quest-only loading does not load or return Npc data")
  equal(rawLoaded.Item, nil, "raw Quest-only loading does not return Item data")
  equal(rawLoaded.Object, nil, "raw Quest-only loading does not return Object data")
  equal(rawStats.applied, 0, "raw Quest-only loading applies no Static Corrections")
  equal(rawStats.derived, nil, "raw Quest-only loading runs no Derived Passes")
  equal(rawLoaded.Quest.entities[7162][questKeys.requiredRaces], 0,
    "raw Quest-only loading preserves quest 7162's zero requiredRaces value")
  equal(rawRequested, { Quest = true }, "raw loading does not mutate the output filter")

  client.reset()
  client.install({ expansion = "Classic" })
  local sourceLib = emulator.loadAddon(config.addonName .. ".toc", config.addonName)
  equal(sourceLib.Quest.Get(7162, "requiredRaces"), 77,
    "Source mode infers quest 7162 through the registered pass")
  check(sourceLib.read.source.entities.Npc ~= nil,
    "Source mode materializes the declared Npc dependency before inference")
  client.reset()

  local shipsRequiredRaces = false
  for _, path in ipairs(config.bakedFileList(config.flavorByName.Vanilla)) do
    if path == "src/derived/requiredRaces.lua" then shipsRequiredRaces = true end
  end
  equal(shipsRequiredRaces, false, "baked clients do not rerun the materialized pass")
end)

--------------------------------------------------------------------------------------------
-- Correction Overlay
--------------------------------------------------------------------------------------------

suite("overlay", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP overlay: ", tocPath, " not generated\n")
    return
  end

  client.reset()
  client.install({ expansion = "Classic" })
  emulator.install(config.antiCollision or config.addonName, emulator.parse(tocPath))
  local Lib = emulator.loadAddon(tocPath, config.addonName)
  local registry = Lib.Corrections
  local Quest = Lib.Quest

  local id = Quest.GetAllIds()[1]
  local baseName = Quest.GetRaw(id, "name")
  check(type(baseName) == "string", "picked a quest with a name")

  -- Reads resolve through the overlay first and fall back to base data.
  registry.RegisterRuntimeCorrection("AddonA", "Quest", "rename",
    function() return { [id] = { [1] = "Renamed by A" } } end, 10)
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "name"), "Renamed by A", "a Dynamic Correction wins over base data")
  equal(Quest.GetRaw(id, "name"), baseName, "GetRaw bypasses the overlay")
  equal(Quest.name(id), "Renamed by A", "the named getter resolves through the overlay too")

  -- Cached values are invalidated when the composed view changes: the read above populated
  -- the cache, and this one must not serve it.
  registry.RegisterRuntimeCorrection("AddonA", "Quest", "rename2",
    function() return { [id] = { [1] = "Renamed again" } } end, 11)
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "name"), "Renamed again", "re-applying invalidates the cached value")

  -- Idempotent by construction: recomposition rebuilds from the registry rather than
  -- accumulating into it.
  registry.ApplyRegisteredCorrections("AddonA")
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "name"), "Renamed again", "re-applying repeatedly is idempotent")

  -- Precedence across owners: the later-RANKED owner wins, and rank is first-apply order.
  registry.RegisterRuntimeCorrection("AddonB", "Quest", "rename",
    function() return { [id] = { [1] = "Renamed by B" } } end, 1)
  registry.ApplyRegisteredCorrections("AddonB")
  equal(Quest.Get(id, "name"), "Renamed by B",
    "the later-ranked owner wins, regardless of load order within owners")
  equal(registry.GetProvenance("Quest", id, "name"), "AddonB", "provenance names the winning owner")

  -- Applying one owner does not disturb another, and re-applying never changes rank: owner
  -- precedence is fixed at first apply, so a refresh (this is ApplyParameterized's shape)
  -- cannot hoist an early layer above corrections registered later.
  registry.RegisterRuntimeCorrection("AddonA", "Quest", "level",
    function() return { [id] = { [4] = 42 } } end, 12)
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "requiredLevel"), 42, "A's correction applies")
  equal(Quest.Get(id, "name"), "Renamed by B",
    "A re-applying refreshes in place — B keeps the contested field")
  equal(registry.GetProvenance("Quest", id, "name"), "AddonB",
    "provenance still names B after A's refresh")
  registry.ApplyRegisteredCorrections("AddonB")
  equal(Quest.Get(id, "name"), "Renamed by B", "B re-applying changes nothing")
  equal(Quest.Get(id, "requiredLevel"), 42, "B's apply did not disturb A's uncontested field")

  -- The blast path the adversarial review confirmed: a QuestieTDB-side refresh (what
  -- ApplyParameterized runs) must leave every consumer layer's precedence intact.
  local ownersBefore = table.concat(registry.GetOwners(), "<")
  registry.ApplyRegisteredCorrections(registry.OWNER)
  equal(table.concat(registry.GetOwners(), "<"), ownersBefore,
    "a QuestieTDB refresh does not reorder owners")
  equal(Quest.Get(id, "name"), "Renamed by B",
    "a QuestieTDB refresh does not reclaim consumer-corrected fields")

  -- Base data is never written to at runtime, in either read mode.
  equal(Quest.GetRaw(id, "name"), baseName, "base data is untouched by the overlay")
  equal(Quest.GetRaw(id, "requiredLevel"), Quest.GetRaw(id, "requiredLevel"),
    "GetRaw is stable")

  -- A withdrawn correction disappears on the next recomposition.
  registry.UnregisterCorrection("AddonB", "Quest", "rename")
  registry.ApplyRegisteredCorrections("AddonB")
  equal(Quest.Get(id, "name"), "Renamed again", "withdrawing B's correction hands the field back to A")
  registry.UnregisterCorrection("AddonA", "Quest", "rename")
  registry.UnregisterCorrection("AddonA", "Quest", "rename2")
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "name"), baseName, "withdrawing every correction falls back to base data")

  -- Within one owner, a later correction overrides an earlier one on the same field.
  registry.RegisterRuntimeCorrection("AddonA", "Quest", "clear",
    function() return { [id] = { [4] = 0 } } end, 13)
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "requiredLevel"), 0,
    "a later correction within an owner overrides an earlier one")

  -- Debug mode reports one owner overriding another.
  local logged = {}
  local realPrint = print
  _G.print = function(message) logged[#logged + 1] = tostring(message) end
  registry.debug = true
  registry.RegisterRuntimeCorrection("AddonB", "Quest", "clash",
    function() return { [id] = { [4] = 7 } } end, 1)
  registry.ApplyRegisteredCorrections("AddonB")
  registry.debug = false
  _G.print = realPrint
  local found = false
  for _, message in ipairs(logged) do
    if message:find('overrode') and message:find("AddonA") then found = true end
  end
  check(found, "debug mode reports when one owner overrides another on the same field")

  -- Order within an owner: higher loadOrder applies later and wins.
  registry.RegisterRuntimeCorrection("AddonC", "Quest", "low",
    function() return { [id] = { [5] = 1 } } end, 1)
  registry.RegisterRuntimeCorrection("AddonC", "Quest", "high",
    function() return { [id] = { [5] = 2 } } end, 100)
  registry.ApplyRegisteredCorrections("AddonC")
  equal(Quest.Get(id, "questLevel"), 2, "within an owner, the higher load order wins")

  -- `[key] = {}` is the delete idiom for EVERY field type, matching MergeInto's doc. A
  -- deleted string reads nil; a deleted number falls to the existence-gated default 0; a
  -- deleted table reads nil.
  local otIndex = Lib.Meta.Quest.keys.objectivesText
  registry.RegisterRuntimeCorrection("AddonD", "Quest", "deletes",
    function() return { [id] = { [1] = {}, [4] = {}, [otIndex] = {} } } end, 10)
  registry.ApplyRegisteredCorrections("AddonD")
  equal(Quest.Get(id, "name"), nil, "{} deletes a string field through the overlay")
  equal(Quest.Get(id, "requiredLevel"), 0, "{} deletes a number field - reads the 0 default")
  equal(Quest.Get(id, "objectivesText"), nil, "{} deletes a table field")
  equal(type(Quest.questLevel(id)), "number", "scalar named getters never leak tables")

  -- A NON-empty table on a scalar-typed field is a correction-author error: reported and
  -- dropped, never stored, never raised out of recomposition.
  local reported = {}
  local savedPrint = print
  _G.print = function(message) reported[#reported + 1] = tostring(message) end
  registry.RegisterRuntimeCorrection("AddonD", "Quest", "bad-scalar",
    function() return { [id] = { [5] = { 60 } } } end, 11)
  registry.ApplyRegisteredCorrections("AddonD")
  _G.print = savedPrint
  equal(Quest.Get(id, "questLevel"), 2, "a table written to a number field is dropped, not stored")
  local badReported = false
  for _, message in ipairs(reported) do
    if message:find("wrote a table") and message:find("AddonD") then badReported = true end
  end
  check(badReported, "the dropped scalar-table write is reported to the author")
  registry.UnregisterCorrection("AddonD", "Quest", "deletes")
  registry.UnregisterCorrection("AddonD", "Quest", "bad-scalar")
  registry.ApplyRegisteredCorrections("AddonD")

  -- Entry-level expansion filters compose in Baked mode too (recompose now resolves the
  -- flavor from LibQuestieDB.flavor, which both modes publish; it used to read only the
  -- Source backend and passed everything in Baked mode).
  local gated = registry.RegisterRuntimeCorrection("AddonE", "Quest", "tbc-only",
    function() return { [id] = { [5] = 90 } } end, 10)
  gated.expansions = { TBC = true }
  local passing = registry.RegisterRuntimeCorrection("AddonE", "Quest", "era-only",
    function() return { [id] = { [4] = 91 } } end, 11)
  passing.expansions = { Classic = true }
  registry.ApplyRegisteredCorrections("AddonE")
  check(Quest.Get(id, "questLevel") ~= 90, "a TBC-gated entry is filtered on baked Vanilla")
  equal(Quest.Get(id, "requiredLevel"), 91, "a Classic-gated entry applies on baked Vanilla")
  registry.UnregisterCorrection("AddonE", "Quest", "tbc-only")
  registry.UnregisterCorrection("AddonE", "Quest", "era-only")
  registry.ApplyRegisteredCorrections("AddonE")

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Ported correction files match Questie's
--------------------------------------------------------------------------------------------

suite("correction-fidelity", function()
  local questie = QUESTIE_PATH
  if not lib.fileExists(questie .. "/Database/Corrections/classicQuestFixes.lua") then
    io.write("  SKIP correction-fidelity: no Questie checkout at ", questie, "\n")
    return
  end

  -- The correction files here are byte-identical copies of Questie's. That is the whole
  -- argument for the compat shim: no transcription step means no transcription error, and
  -- re-syncing is a file copy. Asserting it mechanically is what keeps that true.
  local manifest = dofile("src/corrections/manifest.lua")
  local sourceFor = {
    ["Era/classicQuestReputationFixes.lua"] = "Automatic/classicQuestReputationFixes.lua",
    ["Shared/itemStartFixes.lua"] = "Automatic/itemStartFixes.lua",
    ["Sod/sodBaseQuests.lua"] = "Automatic/sodBaseQuests.lua",
    ["Sod/sodBaseNPCs.lua"] = "Automatic/sodBaseNPCs.lua",
    ["Sod/sodBaseItems.lua"] = "Automatic/sodBaseItems.lua",
    ["Sod/sodBaseObjects.lua"] = "Automatic/sodBaseObjects.lua",
  }

  local compared = 0
  for _, spec in ipairs(manifest) do
    local ours = "src/corrections/" .. spec.file
    local theirs = questie .. "/Database/Corrections/" ..
      (sourceFor[spec.file] or spec.file:match("[^/]+$"))
    local oursExists, theirsExists = lib.fileExists(ours), lib.fileExists(theirs)
    check(oursExists, "manifest copy exists: " .. spec.file)
    check(theirsExists, "declared Questie source exists: " .. spec.file)
    if oursExists and theirsExists then
      compared = compared + 1
      check(lib.readAll(ours) == lib.readAll(theirs),
        "ported copy diverges from Questie's: " .. spec.file)
    end
  end
  equal(compared, #manifest, "every manifest Correction was compared byte-for-byte")

  equal(lib.readAll("src/derived/RamerDouglasPeucker.lua"),
    lib.readAll(questie .. "/Modules/Libs/RamerDouglasPeucker.lua"),
    "copied waypoint library remains byte-identical to Questie's")
end)

--------------------------------------------------------------------------------------------
-- Frozen values
--------------------------------------------------------------------------------------------

suite("value-ownership", function()
  -- ADR 0003 Decision 10, revised: table reads return a FRESH MUTABLE COPY on every read —
  -- the caller owns it outright, exactly matching the compiler semantics Questie's ~290 call
  -- sites were written against. Freezing now guards internal shared structures only
  -- (Source-mode base data), where it still degrades rather than fails.
  local flavor = config.flavorByName.Vanilla
  local tocPath = config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP value-ownership: ", tocPath, " not generated\n")
    return
  end

  local freezeLib = dofile("emulator/freeze.lua")

  -- The offline freeze substitute itself, still needed for the internal-structure guard.
  local plain = { 1, 2, { 3 } }
  freezeLib.freeze(plain)
  check(freezeLib.isFrozen(plain), "freeze marks the table")
  check(not pcall(function() plain[4] = 9 end), "writing a new key to a frozen table must raise")
  equal(plain[1], 1, "reads through a frozen table are unaffected")
  check(freezeLib.freeze(plain) == plain, "re-freezing is harmless and returns the same table")
  freezeLib.reset()

  local function loadMode(path, clientOpts)
    client.reset()
    client.install(clientOpts or {})
    if path ~= config.addonName .. ".toc" then
      emulator.install(config.addonName, emulator.parse(path))
    end
    local Lib = emulator.loadAddon(path, config.addonName)
    freezeLib.install(Lib)
    return Lib
  end

  --- The fresh-per-read contract, checked identically in both modes.
  local function checkFreshPerRead(Lib, label)
    local first = Lib.Quest.Get(2, "startedBy")
    local second = Lib.Quest.Get(2, "startedBy")
    check(type(first) == "table", label .. ": quest 2 startedBy is a table")
    check(first ~= second, label .. ": two reads return distinct tables")
    equal(first, second, label .. ": distinct tables carry equal content")

    -- Mutating what a read handed out never reaches the database or a later read. This is
    -- the exact `creatureObjective[3] = nil` shape that used to require a mutation audit.
    local key = next(first)
    first[key] = nil
    first[999] = "consumer scribble"
    local third = Lib.Quest.Get(2, "startedBy")
    equal(third, second, label .. ": mutation of a returned table never reaches the next read")
    check(third[999] == nil, label .. ": the scribbled key is absent from a fresh read")

    -- Nested independence: inner tables are fresh too.
    local spawnsA = Lib.Npc.Get(30, "spawns")
    local spawnsB = Lib.Npc.Get(30, "spawns")
    check(type(spawnsA) == "table", label .. ": npc 30 spawns is a table")
    local zone = next(spawnsA)
    check(spawnsA[zone] ~= spawnsB[zone], label .. ": nested tables are independent copies")
    spawnsA[zone][1] = "corrupted"
    equal(Lib.Npc.Get(30, "spawns"), spawnsB, label .. ": nested mutation never propagates")

    -- Scalars are immutable, so they stay plainly cached and stable.
    equal(Lib.Quest.Get(2, "name"), "Sharptalon's Claw", label .. ": scalar reads work")
    equal(Lib.Quest.Get(2, "name"), Lib.Quest.Get(2, "name"), label .. ": scalar reads are stable")

    -- GetRaw values are caller-owned copies too.
    local rawA = Lib.Quest.GetRaw(2, "startedBy")
    local rawB = Lib.Quest.GetRaw(2, "startedBy")
    check(rawA ~= rawB, label .. ": GetRaw returns a fresh copy per call")
    equal(rawA, rawB, label .. ": GetRaw copies carry equal content")
  end

  local baked = loadMode(tocPath)
  checkFreshPerRead(baked, "baked")

  local source = loadMode(config.addonName .. ".toc", { expansion = "Classic" })
  checkFreshPerRead(source, "source")

  -- Overlay-supplied tables are fresh per read as well, and the composed row is unreachable.
  local objectivesIndex = baked.Meta.QuestMeta.questKeys.objectivesText
  baked.Corrections.RegisterRuntimeCorrection("OwnershipTest", "Quest", "objectives",
    function() return { [2] = { [objectivesIndex] = { "corrected objective" } } } end, 10)
  baked.Corrections.ApplyRegisteredCorrections("OwnershipTest")
  local correctedA = baked.Quest.Get(2, "objectivesText")
  local correctedB = baked.Quest.Get(2, "objectivesText")
  check(correctedA ~= correctedB, "overlay table values are fresh per read")
  equal(correctedA, { "corrected objective" }, "the corrected value reads through")
  correctedA[1] = "scribbled"
  equal(baked.Quest.Get(2, "objectivesText"), { "corrected objective" },
    "mutating an overlay-supplied value never reaches the overlay")
  baked.Corrections.UnregisterCorrection("OwnershipTest", "Quest", "objectives")
  baked.Corrections.ApplyRegisteredCorrections("OwnershipTest")

  -- Source mode still freezes its base data: internal shared structure, not a returned value.
  local base = source.read.source.entities.Quest
  check(source.shared.IsFrozen(base), "source mode base data itself is frozen")
  check(not pcall(function() base[999999] = {} end), "writing a new entity into base data must raise")

  -- And the internal freeze still degrades rather than fails when the VM refuses.
  source.shared.SetFreezeImplementation(function()
    error("attempted to freeze a table not owned by the calling function " ..
          "(expected 'QuestieTDB', got '*** ForceTaint_Strong ***')", 0)
  end)
  source.shared.freezeRefused = 0
  local refused = source.shared.Freeze({ 1, { 2 } })
  check(type(refused) == "table", "a refused freeze still returns the value")
  check(source.shared.freezeRefused > 0, "the refusal is counted rather than raised")
  check(source.shared.lastFreezeError ~= nil, "the refusal reason is recorded for diagnosis")

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Read contract: existence, composed enumeration, precedence, season gating
--------------------------------------------------------------------------------------------

suite("read-contract", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP read-contract: ", tocPath, " not generated\n")
    return
  end

  local function loadMode(path, clientOpts)
    client.reset()
    client.install(clientOpts or {})
    if path ~= config.addonName .. ".toc" then
      emulator.install(config.addonName, emulator.parse(path))
    end
    return emulator.loadAddon(path, config.addonName)
  end

  --- ADR D6: an unknown id reads nil for EVERY field — including numerics, whose default-0
  --- rule is gated on existence — and invalid ids never reach cache internals.
  local function checkUnknownIds(Lib, label)
    equal(Lib.Quest.Get(999999999, "requiredLevel"), nil, label .. ": unknown id numeric field is nil")
    equal(Lib.Quest.Get(999999999, "name"), nil, label .. ": unknown id string field is nil")
    equal(Lib.Quest.Exists(999999999), false, label .. ": unknown id does not exist")
    equal(Lib.Quest.GetAll(999999999, { "name" }), nil, label .. ": unknown id GetAll is nil")
    equal(Lib.Quest.GetRaw(999999999, "requiredLevel"), nil, label .. ": unknown id GetRaw is nil")

    check(pcall(Lib.Quest.Get, nil, "name"), label .. ": Get(nil) must not raise")
    equal(Lib.Quest.Get(nil, "name"), nil, label .. ": Get(nil) is nil")
    equal(Lib.Quest.name(nil), nil, label .. ": named getter with nil id is nil")
    equal(Lib.Quest.Get("2", "name"), nil, label .. ": a string id is invalid, not coerced")
    equal(Lib.Quest.GetRaw(nil, "name"), nil, label .. ": GetRaw(nil) is nil")
    equal(Lib.Quest.GetAll(nil, { "name" }), nil, label .. ": GetAll(nil) is nil")

    -- GetByIndex validates like Get (was: source raised where baked returned nil).
    equal(Lib.Quest.GetByIndex(2, 999), nil, label .. ": GetByIndex out-of-range index is nil")
    equal(Lib.Quest.GetByIndex(2, 0), nil, label .. ": GetByIndex zero index is nil")
    equal(Lib.Quest.GetByIndex(nil, 1), nil, label .. ": GetByIndex nil id is nil")

    -- GetRaw bounds parity (was: source raised where baked returned nil).
    equal(Lib.Quest.GetRaw(2, 999), nil, label .. ": GetRaw out-of-range index is nil")
    equal(Lib.Quest.GetRaw(2, -5), nil, label .. ": GetRaw negative index is nil")
    equal(Lib.Quest.GetRaw(2, "nonexistentField"), nil, label .. ": GetRaw unknown key is nil")
    equal(Lib.Quest.Get(2, 999), nil, label .. ": Get out-of-range index is nil")

    -- An existing entity still defaults absent numerics to 0 — the ~290-call-site contract.
    check(type(Lib.Quest.Get(2, "requiredSourceItems")) ~= "nil" or
          Lib.Quest.Get(2, "requiredSourceItems") == nil, label .. ": probe read")
    equal(type(Lib.Quest.Get(2, "requiredLevel")), "number",
      label .. ": existing entity numeric field is a number")
  end

  local baked = loadMode(tocPath)
  checkUnknownIds(baked, "baked")

  --- ADR D7: an entity a Dynamic Correction adds is readable, enumerable, and exists — all
  --- three or none — and withdrawal removes all three on the next recomposition.
  local addedId = 4999999
  check(baked.Quest.Exists(addedId) == false, "the added id does not exist beforehand")
  local baseCount = #baked.Quest.GetAllIds()
  baked.Corrections.RegisterRuntimeCorrection("AddingAddon", "Quest", "add-entity",
    function() return { [addedId] = { [1] = "Dynamically Added Quest" } } end, 10)
  baked.Corrections.ApplyRegisteredCorrections("AddingAddon")

  equal(baked.Quest.Get(addedId, "name"), "Dynamically Added Quest", "the added entity is readable")
  equal(baked.Quest.Exists(addedId), true, "the added entity exists")
  equal(baked.Quest.GetAllIds(true)[addedId], true, "the added entity is in the hashmap")
  equal(#baked.Quest.GetAllIds(), baseCount + 1, "the added entity is in the list")
  local sorted = true
  local list = baked.Quest.GetAllIds()
  for i = 2, #list do if list[i - 1] > list[i] then sorted = false break end end
  check(sorted, "the composed id list stays ascending")
  equal(baked.Quest.Get(addedId, "requiredLevel"), 0,
    "an added entity's absent numeric field defaults to 0 like any existing entity")
  local packed = baked.Quest.GetAll(addedId, { "name", "requiredLevel" })
  check(packed ~= nil and packed[1] == "Dynamically Added Quest",
    "GetAll works for an added entity")

  baked.Corrections.UnregisterCorrection("AddingAddon", "Quest", "add-entity")
  baked.Corrections.ApplyRegisteredCorrections("AddingAddon")
  equal(baked.Quest.Exists(addedId), false, "withdrawal removes existence")
  equal(baked.Quest.Get(addedId, "name"), nil, "withdrawal removes readability")
  equal(#baked.Quest.GetAllIds(), baseCount, "withdrawal removes the id from enumeration")

  --- ADR D8: Corrections win over localization, and provenance is honest.
  if baked.l10n.IsAvailable() then
    baked.l10n.SetLocale("deDE")
    equal(baked.Quest.Get(2, "name"), "Klaue von Scharfkralle", "the translation reads through")
    baked.Corrections.RegisterRuntimeCorrection("FixingAddon", "Quest", "fix-name",
      function() return { [2] = { [1] = "Corrected Name" } } end, 10)
    baked.Corrections.ApplyRegisteredCorrections("FixingAddon")
    equal(baked.Quest.Get(2, "name"), "Corrected Name",
      "a corrected field is NOT replaced by a stale lookup translation")
    equal(baked.GetProvenance("Quest", 2, "name"), "FixingAddon",
      "provenance names the owner whose value is actually returned")
    equal(baked.Quest.Get(2, "objectivesText") ~= nil, true,
      "an uncorrected localizable field still translates")
    baked.Corrections.UnregisterCorrection("FixingAddon", "Quest", "fix-name")
    baked.Corrections.ApplyRegisteredCorrections("FixingAddon")
    equal(baked.Quest.Get(2, "name"), "Klaue von Scharfkralle",
      "withdrawing the correction restores the translation")
    baked.l10n.SetLocale("enUS")
  end

  -- The same contract holds in source mode.
  local source = loadMode(config.addonName .. ".toc", { expansion = "Classic" })
  checkUnknownIds(source, "source")

  client.reset()

  --- ADR D9: SoD manifest entries register only when the season is actually active, and
  --- parameterized sets are recorded for explicit application, never applied automatically.
  local runtime = dofile("generator/runtime.lua")
  local savedSeasons, savedEnum = rawget(_G, "C_Seasons"), rawget(_G, "Enum")

  local syntheticManifest = {
    { file = "Era/fake.lua", module = "FakeEra", datatype = "Quest",
      dynamic = { "LoadDynamic" }, expansions = { Classic = true },
      parameterized = { "LoadParameterized" } },
    { file = "Sod/fake.lua", module = "FakeSod", datatype = "Quest",
      dynamic = { "LoadSod" }, expansions = { Classic = true } },
  }
  local fakeModules = {
    FakeEra = {
      LoadDynamic = function() return { [2] = { [4] = 42 } } end,
      LoadParameterized = function(_, location)
        return { [2] = { [1] = "Faire at " .. tostring(location) } }
      end,
    },
    FakeSod = { LoadSod = function() return { [2] = { [4] = 60 } } end },
  }
  local function registerSynthetic()
    local Lib = runtime.build()
    Lib.CorrectionManifest = syntheticManifest
    local registered = Lib.CorrectionRegister.FromManifest(
      Lib.config.flavorByName.Vanilla, function(name) return fakeModules[name] end)
    local sodEntries, eraEntries = 0, 0
    for _, entry in ipairs(Lib.Corrections.Select({ dynamic = true })) do
      if entry.name:find("^Sod/") then sodEntries = sodEntries + 1 end
      if entry.name:find("^Era/") then eraEntries = eraEntries + 1 end
    end
    return Lib, registered, sodEntries, eraEntries
  end

  _G.C_Seasons = { GetActiveSeason = function() return 0 end }
  _G.Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
  local _, _, sodInactive, eraInactive = registerSynthetic()
  equal(sodInactive, 0, "no season active: SoD sets do not register")
  equal(eraInactive, 1, "no season active: Era sets register normally")

  _G.C_Seasons = { GetActiveSeason = function() return 2 end }
  local activeLib, _, sodActive = registerSynthetic()
  equal(sodActive, 1, "SoD active: SoD sets register")

  _G.C_Seasons = nil
  local _, _, sodAbsent = registerSynthetic()
  equal(sodAbsent, 0, "no C_Seasons API at all: SoD sets do not register")

  -- Parameterized sets: recorded but never auto-registered; explicit application carries the
  -- consumer's argument; re-application with a new argument replaces, never accumulates.
  local function countByName(Lib, pattern)
    local n = 0
    for _, entry in ipairs(Lib.Corrections.Select({ dynamic = true })) do
      if entry.name:find(pattern, 1, true) then n = n + 1 end
    end
    return n
  end
  equal(countByName(activeLib, "LoadParameterized"), 0,
    "a parameterized set is never registered automatically")
  check(activeLib.CorrectionRegister.parameterized.LoadParameterized ~= nil,
    "the parameterized set is recorded for explicit application")

  local applied = activeLib.Corrections.ApplyParameterized("LoadParameterized", "Elwynn")
  equal(applied, 1, "ApplyParameterized registers the recorded set")
  equal(countByName(activeLib, "LoadParameterized"), 1, "exactly one entry after application")
  local entries = activeLib.Corrections.Select({ dynamic = true })
  local materialized
  for _, entry in ipairs(entries) do
    if entry.name:find("LoadParameterized", 1, true) then materialized = entry.func() end
  end
  equal(materialized[2][1], "Faire at Elwynn", "the consumer's argument reaches the correction")

  activeLib.Corrections.ApplyParameterized("LoadParameterized", "Mulgore")
  equal(countByName(activeLib, "LoadParameterized"), 1,
    "re-application with a new argument replaces rather than accumulates")
  for _, entry in ipairs(activeLib.Corrections.Select({ dynamic = true })) do
    if entry.name:find("LoadParameterized", 1, true) then materialized = entry.func() end
  end
  equal(materialized[2][1], "Faire at Mulgore", "the new argument wins")

  equal(activeLib.Corrections.ApplyParameterized("NoSuchFunction", 1), 0,
    "an unknown parameterized name applies nothing")

  _G.C_Seasons = savedSeasons
  _G.Enum = savedEnum
end)

--------------------------------------------------------------------------------------------
-- Equivalence negative control
--------------------------------------------------------------------------------------------

suite("equivalence-control", function()
  local flavor = config.flavorByName.Vanilla
  local sourceToc = config.tocPath(flavor)
  if not lib.fileExists(sourceToc) then
    io.write("  SKIP equivalence-control: ", sourceToc, " not generated\n")
    return
  end

  lib.mkdirp(".out/corrupt")
  local original = lib.readAll(sourceToc)

  local function runEquivalence(content, label)
    lib.writeAll(".out/corrupt/" .. sourceToc, content)
    local ok = os.execute(shellQuote(LUA_BIN) ..
      " equivalence.lua Vanilla --toc-dir=.out/corrupt --quiet >/dev/null 2>&1")
    local failed
    if type(ok) == "number" then failed = ok ~= 0 else failed = not ok end
    check(failed, "equivalence accepted a divergence: " .. label)
  end

  -- A changed baked value must diverge from source.
  local changed = original:gsub("## X%-Npc%-30%-1: [^\n]*", "## X-Npc-30-1: Not A Forest Spider", 1)
  check(changed ~= original, "corruption fixture did not apply (changed npc name)")
  runEquivalence(changed, "changed npc name")

  -- The predicted failure mode: a table field that reads nil on one side and {} on the other.
  local emptied = original:gsub("## X%-Quest%-2%-2: [^\n]*", "## X-Quest-2-2: {}", 1)
  check(emptied ~= original, "corruption fixture did not apply (empty table)")
  runEquivalence(emptied, "nil versus empty table")

  -- And the healthy case still passes, so the control is not just always-fails.
  local runEquivalenceOk = os.execute(shellQuote(LUA_BIN) ..
    " equivalence.lua Vanilla --sample=200 --quiet >/dev/null 2>&1")
  local passed
  if type(runEquivalenceOk) == "number" then passed = runEquivalenceOk == 0 else passed = runEquivalenceOk == true end
  check(passed, "equivalence failed on an uncorrupted artifact")

  os.remove(".out/corrupt/" .. sourceToc)
end)

--------------------------------------------------------------------------------------------
-- Distributable LuaLS declarations
--------------------------------------------------------------------------------------------

suite("lua-types", function()
  local commonMethods = {
    GetByIndex = true,
    Get = true,
    GetAll = true,
    GetRaw = true,
    GetAllIds = true,
    Exists = true,
    InvalidateCache = true,
  }
  local typeFiles = {}
  local typeFilePipe = assert(io.popen(
    "find src/types -maxdepth 1 -type f -name '*.t.lua' -print | sort", "r"))
  for path in typeFilePipe:lines() do typeFiles[#typeFiles + 1] = path end
  typeFilePipe:close()

  check(#typeFiles > 0, "packaging has at least one LuaLS declaration to ship")
  for _, path in ipairs(typeFiles) do
    local content = lib.readAll(path)
    check(content:find("---@meta _", 1, true) ~= nil,
      path .. " is marked as analysis-only LuaLS metadata")
  end

  local generalTypes = lib.readAll("src/types/General.t.lua")
  for alias in generalTypes:gmatch("%-%-%-@alias%s+([%a_][%w_]*)") do
    check(alias:find("^QuestieTDB") ~= nil,
      "analysis-only helper alias is namespaced for consumer compatibility: " .. alias)
  end

  local entities = {
    { name = "Quest", meta = dofile("src/meta/questMeta.lua") },
    { name = "Npc", meta = dofile("src/meta/npcMeta.lua") },
    { name = "Item", meta = dofile("src/meta/itemMeta.lua") },
    { name = "Object", meta = dofile("src/meta/objectMeta.lua") },
  }

  for _, entity in ipairs(entities) do
    local path = "src/types/" .. entity.name .. ".t.lua"
    local content = lib.readAll(path)
    local declared, duplicateFields = {}, {}
    for field in content:gmatch("%-%-%-@field%s+([%a_][%w_]*)%s+fun") do
      if declared[field] then duplicateFields[#duplicateFields + 1] = field end
      declared[field] = true
    end
    if content:find("function " .. entity.name .. "DB.GetAllIds", 1, true) then
      declared.GetAllIds = true
    end

    equal(#duplicateFields, 0, entity.name .. " type has no duplicate getter declarations")
    for _, method in ipairs({
      "GetByIndex", "Get", "GetAll", "GetRaw", "GetAllIds", "Exists", "InvalidateCache",
    }) do
      check(declared[method] == true,
        entity.name .. " type declares the common method " .. method)
    end

    local schemaFields = {}
    for fieldIndex = 1, entity.meta.fieldCount do
      local field = entity.meta.names[fieldIndex]
      schemaFields[field] = true
      check(declared[field] == true,
        entity.name .. " type declares schema getter " .. field)
    end
    for field in pairs(declared) do
      if not commonMethods[field] then
        check(schemaFields[field] == true,
          entity.name .. " type has no getter outside the schema: " .. field)
      end
    end

    local aliasBody = generalTypes:match(
      "%-%-%-@alias%s+QuestieTDB" .. entity.name .. "Field%s+([^\r\n]+)")
    check(aliasBody ~= nil, entity.name .. " field-name alias exists")
    local aliasedFields = {}
    for field in (aliasBody or ""):gmatch('"([^"]+)"') do aliasedFields[field] = true end
    equal(aliasedFields, schemaFields, entity.name .. " field-name alias matches the schema")
  end

  local tocPaths = { "QuestieTDB.toc" }
  for _, flavor in ipairs(config.flavors) do
    local path = config.tocPath(flavor)
    if lib.fileExists(path) then tocPaths[#tocPaths + 1] = path end
  end
  for _, path in ipairs(tocPaths) do
    local typeEntries = {}
    for line in lib.readAll(path):gmatch("[^\r\n]+") do
      if line:sub(1, 1) ~= "#" then
        local lower = line:lower()
        if lower:find("types/", 1, true) or lower:find("types\\", 1, true) then
          typeEntries[#typeEntries + 1] = line
        end
      end
    end
    equal(typeEntries, {}, path .. " does not runtime-load LuaLS declarations")
  end
end)

--------------------------------------------------------------------------------------------
-- TOC file lists
--------------------------------------------------------------------------------------------

suite("toc", function()
  -- The correction manifest drives which correction files a TOC lists, and `config` cannot
  -- load it itself — in a client it arrives as an addon file, so the generator assigns it
  -- explicitly. The same has to happen here, and it is asserted rather than assumed: without
  -- it `correctionFiles` returns an empty list and every check below would pass over a file
  -- list missing twenty-odd entries.
  config.correctionManifest = dofile("src/corrections/manifest.lua")
  check(config.correctionManifest ~= nil and #config.correctionManifest > 0,
    "the correction manifest loaded")

  -- The client rejects a file listed twice with `Duplicate File Load Detected`, and it is
  -- right to: the file re-executes, rebuilding whatever it defines while earlier files still
  -- hold references to the first copy. Blocks declare their own prerequisites — the support
  -- block and the correction block both need `enum/constants.lua` — so the composer has to
  -- deduplicate, and this is what proves it does.
  local lists = { { name = "base (source mode)", files = config.sourceFileList() } }
  for _, flavor in ipairs(config.flavors) do
    lists[#lists + 1] = { name = flavor.name, files = config.bakedFileList(flavor) }
  end

  -- Guard against the lists silently shrinking: a composer that returns early would make every
  -- check below vacuous.
  for _, list in ipairs(lists) do
    local blocks = { support = false, corrections = false, meta = false, api = false }
    for _, file in ipairs(list.files) do
      if file:find("^support/") then blocks.support = true end
      if file:find("^src/corrections/%a+/") then blocks.corrections = true end
      if file:find("^src/meta/") then blocks.meta = true end
      if file == "src/api.lua" then blocks.api = true end
    end
    for name, present in pairs(blocks) do
      check(present, ("%s is missing its %s block entirely"):format(list.name, name))
    end
    check(#list.files > 30, ("%s lists only %d files"):format(list.name, #list.files))
  end

  for _, list in ipairs(lists) do
    local seen, duplicates = {}, {}
    for _, file in ipairs(list.files) do
      if seen[file] then duplicates[#duplicates + 1] = file end
      seen[file] = true
    end
    for _, file in ipairs(duplicates) do
      check(false, ("%s lists %s more than once"):format(list.name, file))
    end
    equal(#duplicates, 0, list.name .. " has no duplicate file entries")

    -- Every listed file must exist, or the client silently skips it and the failure surfaces
    -- much later as a nil index.
    local missing = 0
    for _, file in ipairs(list.files) do
      if not lib.fileExists(file) then
        missing = missing + 1
        check(false, ("%s lists a file that does not exist: %s"):format(list.name, file))
      end
    end
    equal(missing, 0, list.name .. " lists only files that exist")
  end

  -- Load order: a block's prerequisites must precede it.
  local function positions(files)
    local at = {}
    for index, file in ipairs(files) do at[file] = at[file] or index end
    return at
  end

  for _, list in ipairs(lists) do
    local at = positions(list.files)
    local function before(a, b, why)
      if at[a] and at[b] then
        check(at[a] < at[b], ("%s: %s must load before %s (%s)"):format(list.name, a, b, why))
      end
    end
    before("src/config.lua", "src/meta/normalize.lua", "everything reads config")
    before("src/corrections/enum/constants.lua", "src/support/_begin.lua",
      "the support shim seeds DropDB.correctionKeys from the constants")
    before("src/corrections/enum/constants.lua", "src/corrections/compat.lua",
      "compat captures LibQuestieDB.Enum at file scope")
    before("src/corrections/registry.lua", "src/corrections/_end.lua",
      "registration needs the registry")
    before("src/read/shared.lua", "src/api.lua", "api builds entities with shared.CreateEntity")
    before("src/corrections/_end.lua", "src/api.lua",
      "api applies QuestieTDB's own corrections, so they must be registered first")
    before("src/support/_begin.lua", "src/support/_end.lua", "brackets are ordered")
    before("src/corrections/_begin.lua", "src/corrections/_end.lua", "brackets are ordered")
  end

  -- Source mode only: the reader installs the loader shim, so it has to precede the data it
  -- captures, and the data block has to close before anything else touches QuestieLoader.
  local baseAt = positions(config.sourceFileList())
  check(baseAt["src/read/source.lua"] < baseAt["data/Classic/_flavor.lua"],
    "the source reader installs its shim before the data block opens")
  check(baseAt["data/MoP/_flavor.lua"] < baseAt["data/_end.lua"],
    "every expansion marker falls inside the data block")
  check(baseAt["data/_end.lua"] < baseAt["src/support/_begin.lua"],
    "the data block closes before the support block opens")
end)

--------------------------------------------------------------------------------------------
-- Independence from the prototypes
--------------------------------------------------------------------------------------------

suite("no-prototype-inputs", function()
  -- `Getters` and `toc-database` are reference material, never a build input. Nothing here may
  -- open a path inside them, and in particular nothing may consume `Getters/data/*.lua-table`:
  -- corrections are already applied there by the pipeline QuestieTDB replaces, so building on
  -- it would double-apply corrections from the wrong system.
  --
  -- Provenance comments naming a prototype are fine and wanted — they say where a design came
  -- from. What is forbidden is a *path* that resolves into one.

  local function scan(dir, found)
    local pipe = io.popen('find "' .. dir .. '" -name "*.lua" -o -name "*.toc" -o -name "*.sh" -o -name "*.yml" 2>/dev/null')
    if not pipe then return found end
    for path in pipe:lines() do
      local file = io.open(path, "rb")
      if file then
        local content = file:read("*a")
        file:close()
        -- A path *literal*, not a mention. The character classes exclude newlines so a match
        -- cannot span from one quote on line 10 to another on line 400.
        for _, pattern in ipairs({
          '"[^"\n]*Getters/[^"\n]*"', "'[^'\n]*Getters/[^'\n]*'",
          '"[^"\n]*toc%-database/[^"\n]*"', "'[^'\n]*toc%-database/[^'\n]*'",
          '"[^"\n]*%.lua%-table[^"\n]*"', "'[^'\n]*%.lua%-table[^'\n]*'",
        }) do
          for match in content:gmatch(pattern) do
            found[#found + 1] = path .. ": " .. match
          end
        end
      end
    end
    pipe:close()
    return found
  end

  local found = {}
  for _, dir in ipairs({ "src", "generator", "emulator", "validators", "tools", ".github" }) do
    scan(dir, found)
  end
  -- The top-level entry points, named rather than globbed: this file is a *test* and carries
  -- the search patterns as string literals, so scanning `.` would find itself.
  for _, file in ipairs({ "generate.lua", "verify.lua", "equivalence.lua", "QuestieTDB.toc" }) do
    local handle = io.open(file, "rb")
    if handle then
      local content = handle:read("*a")
      handle:close()
      for _, pattern in ipairs({ "Getters/", "toc%-database/", "%.lua%-table" }) do
        if content:find(pattern) then found[#found + 1] = file .. ": " .. pattern end
      end
    end
  end

  for _, offender in ipairs(found) do
    check(false, "a build input references a prototype path: " .. offender)
  end
  check(#found == 0, ("%d build inputs reference a prototype path"):format(#found))

  -- Every generation input is enumerated in config, and all of them live in this repo.
  local flavor = config.flavorByName.Vanilla
  for _, entityType in ipairs(config.entityTypes) do
    local path = config.dataPath(flavor, entityType)
    check(path:sub(1, 5) == "data/", "entity data comes from this repo: " .. path)
    check(lib.fileExists(path), "entity data file exists: " .. path)
  end
  for _, file in ipairs(config.supportFiles(flavor)) do
    check(lib.fileExists(file), "support file exists: " .. file)
  end
end)

--------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------

suite("api", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP api: ", tocPath, " not generated\n")
    return
  end

  client.reset()
  client.install({ expansion = "Classic" })
  emulator.install(config.addonName, emulator.parse(tocPath))
  local Lib = emulator.loadAddon(tocPath, config.addonName)

  -- Field access, bulk field access and ID enumeration, per entity type.
  for _, entityType in ipairs(config.entityTypes) do
    local entity = Lib[entityType.name]
    check(entity ~= nil, "entity global exposed: " .. entityType.name)
    check(type(entity.Get) == "function", entityType.name .. ".Get")
    check(type(entity.GetAll) == "function", entityType.name .. ".GetAll")
    check(type(entity.GetAllIds) == "function", entityType.name .. ".GetAllIds")
    check(type(entity.GetRaw) == "function", entityType.name .. ".GetRaw")
    check(_G[entityType.name .. "DB"] == entity, entityType.name .. "DB global alias")
  end

  equal(Lib.Quest.Get(2, "name"), "Sharptalon's Claw", "Get by name")
  equal(Lib.Quest.Get(2, 1), "Sharptalon's Claw", "Get by index")
  local bulk = Lib.Quest.GetAll(2, { "name", "requiredLevel" })
  equal(bulk[1], "Sharptalon's Claw", "GetAll returns values in the requested order")
  equal(bulk[2], 20, "GetAll second value")
  equal(bulk.n, 2, "GetAll is packed: n carries the requested count")

  -- Nullable fields leave holes, which made a bare `unpack` silently drop trailing values.
  -- The packed shape makes the documented pattern `unpack(values, 1, values.n)` lossless.
  local holey = Lib.Quest.GetAll(2, { "name", "triggerEnd", "requiredLevel" })
  equal(holey.n, 3, "a nil middle field still counts in n")
  local a, b, c = unpack(holey, 1, holey.n)
  equal(a, "Sharptalon's Claw", "unpack with n: first")
  equal(b, nil, "unpack with n: the nil hole survives")
  equal(c, 20, "unpack with n: the value after the hole is not dropped")
  equal(Lib.Quest.GetAll(999999999, { "name" }), nil, "GetAll of an unknown entity is nil")

  check(#Lib.Quest.GetAllIds() > 4000, "GetAllIds returns the list")
  equal(Lib.Quest.GetAllIds(true)[2], true, "GetAllIds(true) returns a hashmap")
  equal(Lib.Quest.Exists(2), true, "Exists")

  -- The schema is exposed so consumers can name fields rather than index them, in both the
  -- internal spelling and the one DESIGN.md documents.
  equal(Lib.Meta.QuestMeta.questKeys.name, 1, "Meta.QuestMeta.questKeys")
  equal(Lib.Meta.NpcMeta.npcKeys.subName, 14, "Meta.NpcMeta.npcKeys")
  equal(Lib.Meta.ItemMeta.itemKeys.name, 1, "Meta.ItemMeta.itemKeys")
  equal(Lib.Meta.ObjectMeta.objectKeys.name, 1, "Meta.ObjectMeta.objectKeys")
  equal(Lib.Meta.Quest.names[1], "name", "Meta.Quest.names")
  equal(Lib.Meta.Quest.types[1], "string", "Meta.Quest.types")
  equal(Lib.Meta.Quest.fieldCount, 36, "Meta.Quest.fieldCount")

  -- A contract version is published, and the check is a range, not an equality (ADR D12):
  -- additive releases must not break consumers built against an older contract.
  equal(Lib.contractVersion, config.contractVersion, "contractVersion published")
  equal(Lib.RequireContract(config.contractVersion), true, "matching contract passes")
  local ok, message = Lib.RequireContract(config.contractVersion + 98)
  equal(ok, false, "a newer-than-provided contract fails")
  check(type(message) == "string" and message:find("mismatch"), "mismatch carries a specific message")
  equal(Lib.RequireContract(config.minSupportedContract - 1), false,
    "a contract below the supported floor fails")
  equal(Lib.RequireContract(nil), false, "a non-numeric required contract fails cleanly")

  -- A third-party addon registers Corrections with no special treatment.
  local registrar = Lib.GetRegistrar("ThirdPartyAddon")
  check(type(registrar.RegisterRuntimeCorrection) == "function", "GetRegistrar returns a registrar")
  registrar.RegisterRuntimeCorrection("Quest", "demo",
    function() return { [2] = { [1] = "Third-party name" } } end, 10)
  registrar.Apply()
  equal(Lib.Quest.Get(2, "name"), "Third-party name", "a third-party correction applies")
  equal(Lib.Quest.GetRaw(2, "name"), "Sharptalon's Claw", "GetRaw bypasses it")
  equal(Lib.GetProvenance("Quest", 2, "name"), "ThirdPartyAddon",
    "the winning correction's owner is discoverable")
  local owners = Lib.GetOwners()
  check(#owners >= 2, "GetOwners exposes applied order")
  equal(owners[#owners], "ThirdPartyAddon", "the last applied owner is last")

  -- Cache lifecycle is public, and the datatype argument is case-insensitive like the
  -- corrections API — `InvalidateCache("quest", 2)` silently no-oping was a live-probed bug.
  check(type(Lib.InvalidateCache) == "function", "InvalidateCache is public")
  Lib.InvalidateCache("Quest", 2)
  equal(Lib.Quest.Get(2, "name"), "Third-party name", "invalidation preserves the composed view")
  Lib.InvalidateCache()
  equal(Lib.Quest.Get(2, "name"), "Third-party name", "a full invalidation also recomposes")
  local invalidatedWith
  local originalInvalidate = Lib.Quest.InvalidateCache
  Lib.Quest.InvalidateCache = function(id) invalidatedWith = id; return originalInvalidate(id) end
  Lib.InvalidateCache("quest", 2)
  equal(invalidatedWith, 2, "a lowercase datatype reaches the entity")
  Lib.Quest.InvalidateCache = originalInvalidate

  -- Read mode is public and unmistakable.
  equal(Lib.readMode, "baked", "readMode is published")
  equal(Lib.ModeIndicator.GetText(), nil, "baked mode shows no source-mode indicator")

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------------------------------

suite("l10n", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP l10n: ", tocPath, " not generated\n")
    return
  end

  client.reset()
  client.install({ expansion = "Classic", locale = "enUS" })
  emulator.install(config.addonName, emulator.parse(tocPath))
  local Lib = emulator.loadAddon(tocPath, config.addonName)
  local l10n = Lib.l10n

  if not l10n.IsAvailable() then
    io.write("  SKIP l10n: artifact generated with --no-l10n\n")
    client.reset()
    return
  end

  equal(#config.locales, 9, "all nine non-English locales are declared")
  for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    check(l10n.localeIndex[locale] ~= nil, "locale declared: " .. locale)
  end
  equal(l10n.localeIndex.enUS, nil, "enUS is not stored — base data is already English")

  -- Only the requested locale is decoded on access, and switching takes effect immediately
  -- with no regeneration and no rebuild.
  local base = Lib.Quest.name(2)
  equal(base, "Sharptalon's Claw", "enUS reads the base value")

  l10n.SetLocale("deDE")
  equal(Lib.Quest.name(2), "Klaue von Scharfkralle", "deDE quest name")
  equal(Lib.Quest.objectivesText(2),
    { "Bringt die Klaue von Scharfkralle zu Senani Thunderheart im Splintertreeposten in Ashenvale." },
    "deDE objectivesText comes back as a list, matching the base field's shape")
  equal(Lib.Npc.name(54), "Corina Steele", "deDE npc name")
  equal(Lib.Npc.subName(54), "Waffenschmiedin", "deDE npc subName")
  equal(Lib.Item.name(25), "Abgenutztes Kurzschwert", "deDE item name")
  equal(Lib.Object.name(31), "Alte Löwenstatue", "deDE object name")

  l10n.SetLocale("ruRU")
  equal(Lib.Quest.name(2), "Коготь гиппогрифа Острокогтя", "ruRU quest name, after a switch")
  l10n.SetLocale("zhCN")
  equal(Lib.Quest.name(2), "沙普塔隆的爪子", "zhCN quest name, after another switch")

  l10n.SetLocale("enUS")
  equal(Lib.Quest.name(2), base, "switching back to enUS restores the base value")

  -- A field with no translation falls back to the base English value.
  local ids = Lib.Quest.GetAllIds()
  l10n.SetLocale("deDE")
  local fallbacks, translated = 0, 0
  for i = 1, math.min(#ids, 400) do
    local localized = Lib.Quest.name(ids[i])
    l10n.SetLocale("enUS")
    local english = Lib.Quest.name(ids[i])
    l10n.SetLocale("deDE")
    if localized == english then fallbacks = fallbacks + 1 else translated = translated + 1 end
  end
  check(translated > 0, "translations resolve (" .. translated .. " of 400)")
  check(fallbacks + translated == math.min(#ids, 400), "every id resolves to something")

  -- Field coverage matches what Questie translates today, and no more.
  local covered = {}
  for typeName, fields in pairs(l10n.fields) do
    local names = {}
    for _, field in ipairs(fields) do names[#names + 1] = field.name end
    table.sort(names)
    covered[typeName] = table.concat(names, ",")
  end
  equal(covered.Quest, "name,objectivesText", "quest translates name and objectivesText")
  equal(covered.Npc, "name,subName", "npc translates name and subName")
  equal(covered.Item, "name", "item translates name only")
  equal(covered.Object, "name", "object translates name only")

  l10n.SetLocale("enUS")
  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Support data
--------------------------------------------------------------------------------------------

suite("support", function()
  local flavor = config.flavorByName.Vanilla
  local tocPath = config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP support: ", tocPath, " not generated\n")
    return
  end

  client.reset()
  client.install({ expansion = "Classic" })
  emulator.install(config.addonName, emulator.parse(tocPath))
  local Lib = emulator.loadAddon(tocPath, config.addonName)
  local Support = Lib.Support

  -- Each area is exposed for consumption as a whole table.
  check(Support.Get("ZoneDB") ~= nil, "zone data ships from this addon")
  check(Support.Get("QuestXP") ~= nil, "quest XP data ships from this addon")
  check(Support.Get("DropDB") ~= nil, "drop table data ships from this addon")
  check(Support.Get("QuestieDB") ~= nil, "faction template data ships from this addon")

  local zoneIds = Support.Get("ZoneDB").zoneIDs
  check(type(zoneIds) == "table" and zoneIds.DUN_MOROGH ~= nil, "zone IDs are populated")

  local xp = Support.Get("QuestXP").db
  local xpCount = 0
  for _ in pairs(xp or {}) do xpCount = xpCount + 1 end
  check(xpCount > 1000, "quest XP table is populated (" .. xpCount .. " entries)")

  check(Support.Get("QuestieDB").factionTemplate ~= nil, "faction templates are populated")

  -- The drop-table corrections file is reconciled rather than left stray: it reads
  -- `DropDB.correctionKeys`, which the support shim seeds from the extracted constants.
  local dropKeys = Support.Get("DropDB").correctionKeys
  check(type(dropKeys) == "table" and next(dropKeys) ~= nil,
    "DropDB.correctionKeys is seeded so itemDropCorrections can load")
  check(Support.Get("QuestieItemDropCorrections") ~= nil, "drop-table corrections loaded")

  -- Per-flavor data is selected by which file the TOC lists, never at runtime.
  local vanillaFiles, mistsFiles = config.supportFiles(flavor), config.supportFiles(config.flavorByName.Mists)
  local function has(list, name)
    for _, file in ipairs(list) do if file:find(name, 1, true) then return true end end
    return false
  end
  check(has(vanillaFiles, "xpDB-classic.lua"), "Vanilla lists its own quest XP table")
  check(has(mistsFiles, "xpDB-mop.lua"), "Mists lists its own quest XP table")
  check(not has(vanillaFiles, "xpDB-mop.lua"), "Vanilla does not list MoP's quest XP table")
  check(has(mistsFiles, "MoP/areaIdToUiMapId.lua"), "Mists lists its own zone maps")
  check(has(mistsFiles, "cataItemDrops.lua"),
    "Mists loads Cata's drop table alongside its own, as Questie-Mists.toc does")

  check(rawget(_G, "QuestieLoader") == nil, "the support shim handed QuestieLoader back")

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Emulator
--------------------------------------------------------------------------------------------

suite("emulator", function()
  lib.mkdirp(".out")
  local path = ".out/test-emulator.toc"
  lib.writeAll(path, table.concat({
    "# comment",
    "## Interface: 11508",
    "## X-Flavor: Vanilla",
    "## X-T-1-1: hello",
    "## X-T-1-2: ",
    "",
  }, "\n"))

  local map, header = emulator.parse(path)
  equal(header["Interface"], "11508", "ordinary directive parsed")
  equal(header["X-Flavor"], "Vanilla", "X- directive appears in the header view too")
  equal(map["Interface"], nil, "ordinary directive is not stored data")
  equal(map["X-T-1-1"], "hello", "stored value parsed")
  equal(map["X-T-1-2"], "", "empty stored value parsed rather than dropped")

  local handle = emulator.install("QuestieTDB", map)
  equal(handle.get("QuestieTDB", "X-T-1-1"), "hello", "installed accessor reads")
  equal(handle.get("SomeOtherAddon", "X-T-1-1"), nil, "accessor is scoped to its addon")
  equal(C_AddOns.GetAddOnMetadata("QuestieTDB", "X-T-1-1"), "hello", "C_AddOns global installed")

  local ok = pcall(emulator.parse, ".out/does-not-exist.toc")
  check(not ok, "parsing a missing file must raise")

  os.remove(path)
end)

--------------------------------------------------------------------------------------------
-- Wire safety: trim-safe splitting, case-folded keys (ADR 0003 D4, D5)
--------------------------------------------------------------------------------------------

suite("wire-safety", function()
  lib.mkdirp(".out")
  local path = ".out/test-wire.toc"

  local function emit(key, value, maxLen)
    local out = assert(io.open(path, "wb"))
    out:write("## Interface: 11508\n\n")
    lib.writeMetadata(out, key, value, maxLen)
    out:close()
    return emulator.parse(path)
  end

  -- The client trims each stored value's edges (measured, docs/client-metadata-probes.md §1).
  -- Simulate exactly that per part and require lossless reassembly.
  local function clientTrim(s) return s:match("^[ \t\r\n]*(.-)[ \t\r\n]*$") end
  local function clientJoin(map, key)
    local header = map[key]
    if not header:match("^~%d+~$") then return clientTrim(header) end
    local joined = {}
    for i = 1, tonumber(header:match("%d+")) do
      joined[#joined + 1] = clientTrim(map[key .. "-" .. i])
    end
    return table.concat(joined)
  end

  -- A space sitting exactly at the split point must move the split, not straddle it.
  local spaceAtBoundary = string.rep("x", 999) .. " " .. string.rep("y", 500)
  local map = emit("X-T-1-1", spaceAtBoundary, 1000)
  equal(clientJoin(map, "X-T-1-1"), spaceAtBoundary, "client-trimmed reassembly is lossless")
  for i = 1, tonumber(map["X-T-1-1"]:match("%d+")) do
    local part = map["X-T-1-1-" .. i]
    check(not part:match("^[ \t\r\n]") and not part:match("[ \t\r\n]$"),
      "part " .. i .. " has no trimmable edge")
  end

  -- A run of spaces near the boundary backs the split up past the whole run.
  local runNearBoundary = string.rep("a", 995) .. "     " .. string.rep("b", 995)
  map = emit("X-T-1-2", runNearBoundary, 1000)
  equal(clientJoin(map, "X-T-1-2"), runNearBoundary, "space-run value reassembles losslessly")
  for i = 1, tonumber(map["X-T-1-2"]:match("%d+")) do
    local part = map["X-T-1-2-" .. i]
    check(not part:match("^[ \t\r\n]") and not part:match("[ \t\r\n]$"),
      "run part " .. i .. " has no trimmable edge")
  end

  -- Multibyte text with spaces — both split constraints at once.
  local mixed = string.rep("Bringt die Klaue von Scharfkralle ‡u Senani ", 60)
  mixed = mixed:sub(1, #mixed - 1) -- no trailing space: whole-value edges are the encoder's job
  map = emit("X-T-1-3", mixed, 1000)
  equal(clientJoin(map, "X-T-1-3"), mixed, "utf-8 + spaces reassemble losslessly under client trim")

  -- A whitespace run longer than a part cannot split trim-safely: build failure, not corruption.
  do
    local out = assert(io.open(path, "wb"))
    local ok, err = pcall(lib.writeMetadata, out, "X-T-1-4",
      "x" .. string.rep(" ", 2000) .. "y", 1000)
    out:close()
    check(not ok and tostring(err):find("whitespace run"),
      "unsplittable whitespace run fails the build: " .. tostring(err))
  end

  -- Whole-value edges are refused at the chokepoint — the encoders must never produce them.
  do
    local out = assert(io.open(path, "wb"))
    local okLead = pcall(lib.writeMetadata, out, "X-T-1-5", " leading", 1000)
    local okTrail = pcall(lib.writeMetadata, out, "X-T-1-6", "trailing ", 1000)
    out:close()
    check(not okLead, "leading-whitespace value is refused at write time")
    check(not okTrail, "trailing-whitespace value is refused at write time")
  end

  -- And the string encoder routes edge-whitespace strings through the quoted form instead.
  do
    local encoded = encode.string(" padded ")
    check(encoded:sub(1, 3) == codec.QUOTED_PREFIX, "edge-whitespace string encodes quoted")
    equal(codec.decodeString(encoded), " padded ", "quoted edge-whitespace string round-trips")
    equal(encode.string("interior spaces fine"), "interior spaces fine",
      "interior whitespace still stores raw")
  end

  -- GetAddOnMetadata folds key case (measured §2): a case-only key collision is one key to
  -- the client, so generation must refuse it.
  do
    local out = assert(io.open(path, "wb"))
    lib.writeMetadata(out, "X-Abc-1", "one", 1000)
    local ok, err = pcall(lib.writeMetadata, out, "X-ABC-1", "two", 1000)
    out:close()
    check(not ok and tostring(err):find("case%-insensitively"),
      "case-folded key collision is refused: " .. tostring(err))
  end

  -- Cross-family prefixes must differ by more than case, since the per-handle registry
  -- cannot see across the entity pass and the l10n append pass.
  do
    local prefixes = {}
    for _, entityType in ipairs(config.entityTypes) do
      prefixes[#prefixes + 1] = ("x-" .. entityType.metaPrefix):lower()
      prefixes[#prefixes + 1] = ("x-" .. config.l10nMetaPrefix .. entityType.metaPrefix):lower()
    end
    for i = 1, #prefixes do
      for j = 1, #prefixes do
        if i ~= j then
          check(prefixes[i]:sub(1, #prefixes[j]) ~= prefixes[j],
            ("key families %q and %q overlap case-insensitively"):format(prefixes[i], prefixes[j]))
        end
      end
    end
  end

  -- Every artifact on disk honors the edge-whitespace invariant, exactly as verify.lua checks.
  for _, flavor in ipairs(config.flavors) do
    local tocPath = config.tocPath(flavor)
    if lib.fileExists(tocPath) then
      local offending = 0
      local file = assert(io.open(tocPath, "rb"))
      for line in file:lines() do
        line = line:gsub("\r$", "")
        if line:sub(1, 5) == "## X-" then
          local value = line:match("^## [^:]+: (.*)$")
          if value and #value > 0 and
             (lib.TRIMMABLE[value:byte(1)] or lib.TRIMMABLE[value:byte(#value)]) then
            offending = offending + 1
          end
        end
      end
      file:close()
      check(offending == 0,
        ("%s has %d values with client-trimmable edges"):format(tocPath, offending))
    end
  end

  os.remove(path)
end)

--------------------------------------------------------------------------------------------
-- Coordinate quantization (ADR 0003 D1)
--------------------------------------------------------------------------------------------

suite("quantization", function()
  local floor = math.floor
  local function grid(c) return floor(c * 40.90) / 40.90 end

  local meta = {
    entity = "Test",
    fieldCount = 4,
    names = { "spawns", "waypoints", "triggerEnd", "extraObjectives" },
    types = { "table", "table", "table", "table" },
    structures = { "spawnlist", "waypointlist", "trigger", "extraobjectives" },
    emptyIsNil = { [1] = true, [2] = true, [3] = true, [4] = true },
    zeroPairIsNil = {},
    normalize = {},
    keys = { spawns = 1, waypoints = 2, triggerEnd = 3, extraObjectives = 4 },
  }

  -- Spawnlist: the compiler grid, the {-1,-1} sentinel, and phase survival rules — all from
  -- Database/compiler.lua's readers/writers verbatim.
  equal(normalize.field(meta, 1, { [1440] = { { 36.43, 55.89 } } }),
    { [1440] = { { grid(36.43), grid(55.89) } } }, "spawn coordinates land on the 40.90 grid")
  equal(normalize.field(meta, 1, { [1440] = { { -1, -1 } } }),
    { [1440] = { { -1, -1 } } }, "instance sentinel survives")
  equal(normalize.field(meta, 1, { [1440] = { { 0.001, 0.002 } } }),
    { [1440] = { { -1, -1 } } }, "sub-quantum coordinates collapse to the sentinel")
  equal(normalize.field(meta, 1, { [1440] = { { 10, 20, 3 } } }),
    { [1440] = { { grid(10), grid(20), 3 } } }, "non-zero phase survives beside a non-zero pair")
  equal(normalize.field(meta, 1, { [1440] = { { 10, 20, 0 } } }),
    { [1440] = { { grid(10), grid(20) } } }, "phase 0 is dropped — the compiler's reader emits 2 elements")
  equal(normalize.field(meta, 1, { [1440] = { { 0.001, 0.002, 7 } } }),
    { [1440] = { { -1, -1 } } }, "a sentinel-collapsed spawn loses its phase")

  -- Waypointlist nests one level deeper and never carries a third element.
  equal(normalize.field(meta, 2, { [85] = { { { 52.5, 47.25 }, { -1, -1 } } } }),
    { [85] = { { { grid(52.5), grid(47.25) }, { -1, -1 } } } },
    "waypoints quantize through the extra nesting level")
  equal(normalize.field(meta, 2, { [85] = { { { 52.5, 47.25, 9 } } } }),
    { [85] = { { { grid(52.5), grid(47.25) } } } },
    "waypoint third element is dropped — the compiler's reader never returns one")

  -- Trigger: only the nested spawnlist quantizes; the text is untouched.
  equal(normalize.field(meta, 3, { "Scout the tower", { [85] = { { 52.5, 47.25 } } } }),
    { "Scout the tower", { [85] = { { grid(52.5), grid(47.25) } } } },
    "trigger text is verbatim, trigger coordinates quantize")

  -- extraObjectives: row[1] is a spawnlist; the rest of the row is verbatim.
  equal(normalize.field(meta, 4, { { { [85] = { { 52.5, 47.25 } } }, 42, "Use the thing", 1, { { "monster", 5 } } } }),
    { { { [85] = { { grid(52.5), grid(47.25) } } }, 42, "Use the thing", 1, { { "monster", 5 } } } },
    "extraObjectives quantizes only the nested spawnlist")

  -- Quantized values must round-trip the wire exactly: shortest-round-trip spelling is
  -- spelling, never precision loss.
  for _, c in ipairs({ 36.43, 55.89, 52.5, 0.03, 99.97, 47.25, 63.7 }) do
    local q = grid(c)
    local spelled = serialize.number(q)
    equal(tonumber(spelled), q, "spelling round-trips " .. tostring(c))
    check(#spelled <= #string.format("%.17g", q),
      "spelling of " .. tostring(c) .. " is never longer than %.17g")
  end

  -- Quantization is deliberately NOT idempotent — `floor(q * 40.90)` on a grid value can
  -- land one step lower through double rounding (measured: 738 of 10,000 2dp coordinates),
  -- exactly as Questie's own compiler behaves. Every pipeline path quantizes raw source
  -- values exactly once: generation before serializing, source mode before caching, the
  -- overlay on authored correction values. What must never happen is re-normalizing a value
  -- that was read back from the store; this check documents that both consumers agree when
  -- each applies the grid once to the same raw input.
  local viaGeneration = codec.decodeTable(encode.field(meta, 1, { [1440] = { { 8.2, 8.4 } } }))
  local viaSourceRead = normalize.field(meta, 1, { [1440] = { { 8.2, 8.4 } } })
  equal(viaGeneration, viaSourceRead,
    "generation and a source-mode read quantize the same raw value identically")

  -- And the encoder stores exactly the normalized form.
  local encoded = encode.field(meta, 1, { [1440] = { { 36.43, 55.89 } } })
  equal(codec.decodeTable(encoded), { [1440] = { { grid(36.43), grid(55.89) } } },
    "encoded spawnlist decodes to the quantized value")
end)

--------------------------------------------------------------------------------------------
-- Personas: branches the default Alliance-Human persona can never execute
--------------------------------------------------------------------------------------------

suite("personas", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP personas: ", tocPath, " not generated\n")
    return
  end

  local function loadMode(path, clientOpts)
    client.reset()
    client.install(clientOpts)
    if path ~= config.addonName .. ".toc" then
      emulator.install(config.addonName, emulator.parse(path))
    end
    return emulator.loadAddon(path, config.addonName)
  end

  -- Faction oracle: Soothing Spices (item 3713). `LoadFactionFixes` points its relatedQuests
  -- at the Alliance quest 555 or the Horde quest 7321 — src/corrections/Era/
  -- classicItemFixes.lua:1612 (Alliance) and :1632 (Horde). Literal expected values, so a
  -- persona plumbing regression cannot pass by comparing one wrong answer against itself.
  local sourceAlliance = loadMode(config.addonName .. ".toc", { expansion = "Classic" })
  equal(sourceAlliance.Item.Get(3713, "relatedQuests"), { 555, 1218 },
    "source Alliance: Soothing Spices relates to quest 555")

  local sourceHorde = loadMode(config.addonName .. ".toc", { expansion = "Classic", faction = "Horde" })
  equal(sourceHorde.Item.Get(3713, "relatedQuests"), { 7321, 1218 },
    "source Horde: Soothing Spices relates to quest 7321 — the Horde branch actually ran")

  local bakedHorde = loadMode(tocPath, { faction = "Horde" })
  equal(bakedHorde.Item.Get(3713, "relatedQuests"), { 7321, 1218 },
    "baked Horde: the faction branch composes identically over the artifact")

  -- Season persona: with Season of Discovery active the gated Sod/ sets register and the SoD
  -- base quests join the composed view. Counts are compared, not hardcoded — the data moves.
  local plain = loadMode(config.addonName .. ".toc", { expansion = "Classic" })
  local plainIds = plain.Quest.GetAllIds(true)
  local plainCount = #plain.Quest.GetAllIds()

  local sod = loadMode(config.addonName .. ".toc", { expansion = "Classic", season = "SoD" })
  local sodList = sod.Quest.GetAllIds()
  check(#sodList > plainCount, "SoD persona: the composed quest list grows")

  local addedId
  for _, id in ipairs(sodList) do
    if not plainIds[id] then addedId = id break end
  end
  check(addedId ~= nil, "SoD persona: an added quest id is enumerable")
  if addedId then
    equal(sod.Quest.Exists(addedId), true, "SoD persona: an added quest exists")
    check(select("#", sod.Quest.Get(addedId, 1)) >= 0, "SoD persona: an added quest reads without raising")
    equal(plain.Quest.Exists(addedId), false, "plain Era: the same quest does not exist")
  end

  local sodSets = 0
  for _, entry in ipairs(sod.Corrections.Select({ dynamic = true })) do
    if entry.name:find("^Sod/") then sodSets = sodSets + 1 end
  end
  check(sodSets > 0, "SoD persona: Sod/ correction sets registered")

  -- Titan Reforged gate. Upstream applies `LoadTitanReforgedFixes` only under
  -- `Questie.IsTitanReforged` (QuestieCorrections:Initialize), detected as a Wrath client
  -- with active season 109 (Modules/VersionCheck.lua:89). The gate is per-function: the same
  -- manifest entries carry `LoadFactionFixes`, which must apply either way. Probe: quest 6823
  -- "Agent of Hydraxis" — the Titan set raises questLevel/requiredLevel to 80
  -- (src/corrections/Wotlk/wotlkQuestFixes.lua:8816-8819).
  local function titanSets(loaded)
    local count = 0
    for _, entry in ipairs(loaded.Corrections.Select({ dynamic = true })) do
      if entry.name:find("LoadTitanReforgedFixes", 1, true) then count = count + 1 end
    end
    return count
  end

  local plainWrath = loadMode(config.addonName .. ".toc", { expansion = "Wotlk", faction = "Horde" })
  equal(titanSets(plainWrath), 0, "plain Wrath: no Titan set registers")
  equal(plainWrath.Quest.Get(6823, "questLevel"), plainWrath.Quest.GetRaw(6823, "questLevel"),
    "plain Wrath: quest 6823 keeps its base questLevel")
  check(plainWrath.Quest.Get(6823, "questLevel") ~= 80, "plain Wrath: the Titan 80 never applies")

  local titanWrath = loadMode(config.addonName .. ".toc",
    { expansion = "Wotlk", faction = "Horde", season = "TitanReforged" })
  equal(titanSets(titanWrath), 3, "Titan persona: all three gated sets register")
  equal(titanWrath.Quest.Get(6823, "questLevel"), 80, "Titan persona: quest 6823 questLevel 80")
  equal(titanWrath.Quest.Get(6823, "requiredLevel"), 80, "Titan persona: quest 6823 requiredLevel 80")

  -- The ungated sibling function still applies with the gate closed AND open: Horde elder
  -- quest 13012 gains reputationReward {{HORDE, 75}} from LoadFactionFixes
  -- (src/corrections/Wotlk/wotlkQuestFixes.lua, questFixesHorde).
  local plainRep = plainWrath.Quest.Get(13012, "reputationReward")
  check(type(plainRep) == "table" and plainRep[1] and plainRep[1][2] == 75,
    "plain Wrath: faction fixes still apply alongside the closed gate")
  local titanRep = titanWrath.Quest.Get(13012, "reputationReward")
  check(type(titanRep) == "table" and titanRep[1] and titanRep[1][2] == 75,
    "Titan persona: faction fixes unaffected by the open gate")

  -- Season 109 is not Season of Discovery: the Sod/ sets must not mistake it.
  local titanSod = 0
  for _, entry in ipairs(titanWrath.Corrections.Select({ dynamic = true })) do
    if entry.name:find("^Sod/") then titanSod = titanSod + 1 end
  end
  equal(titanSod, 0, "Titan persona: Sod/ sets do not register on season 109")

  -- Baked mode composes the same gate: the Wrath artifact plus a Titan persona reads 80.
  local wrathToc = config.tocPath(config.flavorByName.Wrath)
  if lib.fileExists(wrathToc) then
    local bakedTitan = loadMode(wrathToc, { expansion = "Wotlk", faction = "Horde", season = "TitanReforged" })
    equal(bakedTitan.Quest.Get(6823, "questLevel"), 80, "baked Titan: gate composes over the artifact")
    local bakedPlain = loadMode(wrathToc, { expansion = "Wotlk", faction = "Horde" })
    check(bakedPlain.Quest.Get(6823, "questLevel") ~= 80, "baked plain Wrath: gate stays closed")
  end

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Perf guard: the cached hot path must not allocate beyond the fresh value itself
--------------------------------------------------------------------------------------------

suite("perf-guard", function()
  local tocPath = config.tocPath(config.flavorByName.Vanilla)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP perf-guard: ", tocPath, " not generated\n")
    return
  end

  client.reset()
  client.install({})
  local map = emulator.parse(tocPath)
  emulator.install(config.addonName, map)
  local Lib = emulator.loadAddon(tocPath, config.addonName)

  local N = 5000

  --- Bytes allocated by `fn` run N times, with the collector stopped so every allocation is
  --- visible and none is reclaimed mid-measurement.
  local function allocatedBytes(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, N do fn() end
    local grown = (collectgarbage("count") - before) * 1024
    collectgarbage("restart")
    collectgarbage("collect")
    return grown
  end

  -- Warm both paths so the measured loops see only cache hits.
  Lib.Quest.Get(2, "name")
  Lib.Quest.Get(2, "startedBy")

  -- A cached scalar read allocates nothing at all. The tightest possible guard against the
  -- reviewed sibling's defect class (an eager assert-message concat on every read): a single
  -- per-read string is ≥ 24 bytes, i.e. ≥ 120,000 bytes over this loop, against a bound of 512.
  local scalarBytes = allocatedBytes(function() return Lib.Quest.Get(2, "name") end)
  check(scalarBytes <= 512,
    ("cached scalar reads allocated %d bytes over %d reads — the hot path is allocating"):format(scalarBytes, N))

  -- A cached table read allocates exactly what the producer itself allocates — the fresh
  -- copy — and nothing on top. Tolerance: 16 bytes per read, smaller than any real string.
  local stored = map["X-Quest-2-" .. tostring(Lib.Meta.QuestMeta.questKeys.startedBy)]
  check(stored ~= nil, "quest 2 startedBy stored literal found for calibration")
  local producer = codec.compileTable(stored)
  local baseline = allocatedBytes(function() return producer() end)
  local viaGet = allocatedBytes(function() return Lib.Quest.Get(2, "startedBy") end)
  check(viaGet - baseline <= N * 16,
    ("cached table reads allocated %d bytes beyond the %d-byte producer baseline over %d reads")
      :format(viaGet - baseline, baseline, N))

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Reconstruction negative control: the byte gate must detect a single corrupted byte
--------------------------------------------------------------------------------------------

suite("reconstruct-control", function()
  local flavor = config.flavorByName.Vanilla
  local sourceToc = config.tocPath(flavor)
  if not lib.fileExists(sourceToc) then
    io.write("  SKIP reconstruct-control: ", sourceToc, " not generated\n")
    return
  end
  if not pcall(lib.assertQuestiePin, QUESTIE_PATH) then
    io.write("  SKIP reconstruct-control: no pinned Questie checkout at ", QUESTIE_PATH, "\n")
    return
  end

  lib.mkdirp(".out/corrupt")
  local original = lib.readAll(sourceToc)
  local corrupted = original:gsub("## X%-Npc%-30%-1: [^\n]*", "## X-Npc-30-1: Not A Forest Spider", 1)
  check(corrupted ~= original, "corruption fixture did not apply")
  lib.writeAll(".out/corrupt/" .. sourceToc, corrupted)

  local countFile = ".out/reconstruct-count.txt"
  local ok = os.execute("QUESTIE_PATH=" .. shellQuote(QUESTIE_PATH) .. " " .. shellQuote(LUA_BIN) ..
    " reconstruct.lua Vanilla --toc-dir=.out/corrupt --count-only > " ..
    shellQuote(countFile) .. " 2>/dev/null")
  local failed
  if type(ok) == "number" then failed = ok ~= 0 else failed = not ok end
  check(failed, "reconstruct accepted a corrupted artifact")
  local counted = tonumber((lib.readAll(countFile):match("(%d+)")))
  equal(counted, 1, "one corrupted byte is exactly one localized mismatch")

  os.remove(".out/corrupt/" .. sourceToc)
  os.remove(countFile)
end)

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local requested = arg and arg[1]
local totalFailed, totalChecks = 0, 0

for _, name in ipairs(order) do
  if not requested or requested == name then
    current = { name = name, total = 0, failed = 0 }
    local ok, err = pcall(suites[name])
    if not ok then
      current.failed = current.failed + 1
      io.write("  ERROR ", name, ": ", tostring(err), "\n")
    end
    print(("[%s] %-18s %d checks, %d failed")
      :format(current.failed == 0 and "PASS" or "FAIL", name, current.total, current.failed))
    totalFailed = totalFailed + current.failed
    totalChecks = totalChecks + current.total
  end
end

print(("%d checks, %d failed"):format(totalChecks, totalFailed))
os.exit(totalFailed == 0 and 0 or 1)
