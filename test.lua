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

--------------------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------------------

local suites, order = {}, {}
local function suite(name, fn)
  suites[name] = fn
  order[#order + 1] = name
end

local current
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

  equal(normalize.field(meta, 3, nil), nil, "table nil stays nil")
  equal(normalize.field(meta, 3, {}), nil, "empty table reads back as nil, never {}")
  equal(normalize.field(meta, 3, { 1 }), { 1 }, "non-empty table passes through")

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
  equal(normalize.default(meta, 3), nil, "table default is nil")

  -- Encoding must agree: whatever reads back as a default is not written at all.
  equal(encode.field(meta, 1, nil), nil, "numeric nil writes no line")
  equal(encode.field(meta, 1, 0), nil, "numeric zero writes no line")
  equal(encode.field(meta, 1, 7), "7", "numeric value writes a line")
  equal(encode.field(meta, 3, {}), nil, "empty table writes no line")
  equal(encode.field(meta, 4, { 0, 0 }), nil, "zero pair writes no line")
  equal(encode.field(meta, 2, ""), codec.EMPTY_STRING, "empty string writes its marker")
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
    local command = ("lua5.1 verify.lua Vanilla --toc-dir=.out/corrupt --quiet >/dev/null 2>&1")
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

  -- 4. A missing chunk part must raise rather than return a short string.
  local map = emulator.parse(sourceToc)
  local chunkKey
  for key, value in pairs(map) do
    if value:match("^~%d+~$") then chunkKey = key; break end
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

  local registry = Lib.Corrections
  runtime.loadCorrections(Lib, flavor)

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

  -- Precedence: last applied wins across owners.
  registry.RegisterRuntimeCorrection("AddonB", "Quest", "rename",
    function() return { [id] = { [1] = "Renamed by B" } } end, 1)
  registry.ApplyRegisteredCorrections("AddonB")
  equal(Quest.Get(id, "name"), "Renamed by B",
    "last applied wins across owners, regardless of load order within them")
  equal(registry.GetProvenance("Quest", id, "name"), "AddonB", "provenance names the winning owner")

  -- Applying one owner does not disturb another: A's other field survives B's apply.
  registry.RegisterRuntimeCorrection("AddonA", "Quest", "level",
    function() return { [id] = { [4] = 42 } } end, 12)
  registry.ApplyRegisteredCorrections("AddonA")
  equal(Quest.Get(id, "requiredLevel"), 42, "A's correction applies")
  equal(Quest.Get(id, "name"), "Renamed again",
    "A re-applying moves it last, so A's highest-load-order correction wins the contested field")
  registry.ApplyRegisteredCorrections("AddonB")
  equal(Quest.Get(id, "name"), "Renamed by B", "B re-applying takes the contested field back")
  equal(Quest.Get(id, "requiredLevel"), 42, "B's apply did not disturb A's uncontested field")

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

  client.reset()
end)

--------------------------------------------------------------------------------------------
-- Ported correction files match Questie's
--------------------------------------------------------------------------------------------

suite("correction-fidelity", function()
  local questie = "../Questie"
  if not lib.fileExists(questie .. "/Database/Corrections/classicQuestFixes.lua") then
    io.write("  SKIP correction-fidelity: no Questie checkout alongside this repo\n")
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
    if lib.fileExists(ours) and lib.fileExists(theirs) then
      compared = compared + 1
      check(lib.readAll(ours) == lib.readAll(theirs),
        "ported copy diverges from Questie's: " .. spec.file)
    end
  end
  check(compared >= 25, ("compared %d correction files, expected at least 25"):format(compared))
end)

--------------------------------------------------------------------------------------------
-- Frozen values
--------------------------------------------------------------------------------------------

suite("freeze", function()
  local flavor = config.flavorByName.Vanilla
  local tocPath = config.tocPath(flavor)
  if not lib.fileExists(tocPath) then
    io.write("  SKIP freeze: ", tocPath, " not generated\n")
    return
  end

  local freezeLib = dofile("emulator/freeze.lua")

  -- The substitute itself.
  local plain = { 1, 2, { 3 } }
  freezeLib.freeze(plain)
  check(freezeLib.isFrozen(plain), "freeze marks the table")
  check(not pcall(function() plain[4] = 9 end), "writing a new key to a frozen table must raise")
  equal(plain[1], 1, "reads through a frozen table are unaffected")
  check(freezeLib.freeze(plain) == plain, "re-freezing is harmless and returns the same table")

  -- `__newindex` fires only for absent keys in Lua 5.1, so an overwrite or a `= nil` deletion
  -- slips past prevention. The audit is what covers it — and the audit is the half that has to
  -- work, because `GetQuest`'s `creatureObjective[3] = nil` is exactly an existing-key write.
  equal(select(1, freezeLib.audit()), 0, "a untouched frozen table audits clean")
  rawset(plain, 1, 9)
  equal(select(1, freezeLib.audit()), 1, "the audit catches an overwrite __newindex cannot see")
  freezeLib.reset()
  local nilled = { 1, 2, 3 }
  freezeLib.freeze(nilled)
  rawset(nilled, 3, nil)
  equal(select(1, freezeLib.audit()), 1, "the audit catches a `= nil` deletion")
  freezeLib.reset()

  local function loadFrozen(path, clientOpts)
    client.reset()
    client.install(clientOpts or {})
    if path == config.addonName .. ".toc" then
      -- source mode needs no metadata
    else
      emulator.install(config.addonName, emulator.parse(path))
    end
    local Lib = emulator.loadAddon(path, config.addonName)
    freezeLib.install(Lib)
    return Lib
  end

  -- Baked mode: a returned table is frozen, and mutating it raises.
  local baked = loadFrozen(tocPath)
  check(baked.shared.canFreeze, "freeze capability is detected once a substitute is installed")
  local startedBy = baked.Quest.Get(2, "startedBy")
  check(type(startedBy) == "table", "quest 2 startedBy is a table")
  check(baked.shared.IsFrozen(startedBy), "baked mode returns a frozen table")
  check(not pcall(function() startedBy[99] = true end), "mutating a baked table value must raise")
  -- The `creatureObjective[3] = nil` shape: prevention cannot see it offline, the audit can.
  -- Delete a key the table actually has — quest 2's startedBy is sparse.
  local presentKey = next(startedBy)
  rawset(startedBy, presentKey, nil)
  check(select(1, freezeLib.audit()) >= 1, "the audit catches a deletion inside a returned table")

  -- Nested tables are frozen too, which is the case a shallow freeze would miss.
  local spawns = baked.Npc.Get(30, "spawns")
  check(type(spawns) == "table", "npc 30 spawns is a table")
  local zone = next(spawns)
  check(baked.shared.IsFrozen(spawns[zone]), "nested tables are frozen")

  -- Scalars are cached without freezing, because strings and numbers cannot be mutated.
  equal(baked.Quest.Get(2, "name"), "Sharptalon's Claw", "scalar reads still work under freezing")
  equal(baked.Quest.Get(2, "name"), baked.Quest.Get(2, "name"), "scalar reads are stable")

  -- Source mode: base data is frozen after load, so a correction or a consumer cannot corrupt it.
  local source = loadFrozen(config.addonName .. ".toc", { expansion = "Classic" })
  local sourceStartedBy = source.Quest.Get(2, "startedBy")
  check(source.shared.IsFrozen(sourceStartedBy), "source mode returns a frozen table")
  check(not pcall(function() sourceStartedBy[99] = true end), "mutating source base data must raise")
  freezeLib.audit() -- absorb the deliberate mutation above

  local base = source.read.source.entities.Quest
  check(source.shared.IsFrozen(base), "source mode base data itself is frozen")
  check(not pcall(function() base[999999] = {} end), "writing a new entity into base data must raise")

  -- No frozen table may carry a redirecting __newindex. Offline the metatable *is* the
  -- mechanism and its __newindex raises; what must never happen is a metamethod that
  -- swallows the write.
  local meta = getmetatable(startedBy)
  if meta then
    check(type(meta.__newindex) == "function", "a frozen table's __newindex must exist to raise")
    check(not pcall(rawget(meta, "__newindex"), startedBy, 1, 1), "__newindex must raise, not redirect")
  end

  client.reset()
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
    local ok = os.execute("lua5.1 equivalence.lua Vanilla --toc-dir=.out/corrupt --quiet >/dev/null 2>&1")
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
  local runEquivalenceOk = os.execute("lua5.1 equivalence.lua Vanilla --sample=200 --quiet >/dev/null 2>&1")
  local passed
  if type(runEquivalenceOk) == "number" then passed = runEquivalenceOk == 0 else passed = runEquivalenceOk == true end
  check(passed, "equivalence failed on an uncorrupted artifact")

  os.remove(".out/corrupt/" .. sourceToc)
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

  -- A contract version is published and mismatch is detectable at load.
  equal(Lib.contractVersion, config.contractVersion, "contractVersion published")
  equal(Lib.RequireContract(config.contractVersion), true, "matching contract passes")
  local ok, message = Lib.RequireContract(config.contractVersion + 98)
  equal(ok, false, "mismatched contract fails")
  check(type(message) == "string" and message:find("mismatch"), "mismatch carries a specific message")

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

  -- Cache lifecycle is public.
  check(type(Lib.InvalidateCache) == "function", "InvalidateCache is public")
  Lib.InvalidateCache("Quest", 2)
  equal(Lib.Quest.Get(2, "name"), "Third-party name", "invalidation preserves the composed view")
  Lib.InvalidateCache()
  equal(Lib.Quest.Get(2, "name"), "Third-party name", "a full invalidation also recomposes")

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
