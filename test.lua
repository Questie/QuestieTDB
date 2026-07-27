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
