-- Check the explicit data against independent, pinned audit evidence. The strict compiler
-- differential remains the all-quest drift check; this fixture is not a baseline allowance.
---@param check fun(condition: boolean, message: string)
---@param equal fun(actual: any, expected: any, message: string)
---@return nil
return function(check, equal)
  local lib = dofile("generator/lib.lua")
  local config = dofile("src/config.lua")
  config.correctionManifest = dofile("src/corrections/manifest.lua")
  local emulator = dofile("emulator/metadata.lua")
  -- Other suites can leave a LibStub mock; it cannot register the client's LibDeflate.
  local savedLibStub = rawget(_G, "LibStub")
  _G.LibStub = nil
  local loaded, client = pcall(dofile, "emulator/client.lua")
  _G.LibStub = savedLibStub
  assert(loaded, client)

  local path = "src/corrections/Sod/sodRequiredRaces.lua"
  local name = "Sod:sodRequiredRaces"
  local expected, count = {}, 0
  for line in io.lines("tools/differential/evidence/sod-required-races-before.tsv") do
    local fields = {}
    for field in line:gmatch("[^\t]+") do fields[#fields + 1] = field end
    local id = tonumber(fields[1])
    if id then
      expected[id] = assert(tonumber(fields[6]), "audit lacks oracle mask")
      count = count + 1
    end
  end
  equal(count, 25, "the pinned audit covers 25 distinct corrections")

  for _, flavor in ipairs(config.flavors) do
    local files = table.concat(config.bakedFileList(flavor), "\n")
    equal(files:find(path, 1, true) ~= nil, flavor.name == "Vanilla",
      flavor.name .. " ships only applicable authored SoD data")
  end

  local modes = { { name = "Source", toc = "QuestieTDB.toc" } }
  if lib.fileExists("QuestieTDB_Vanilla.toc") then
    local toc = lib.readAll("QuestieTDB_Vanilla.toc"):gsub("\\", "/")
    local current = toc:find(path, 1, true) ~= nil
    check(current, "Baked Vanilla TOC includes authored SoD data; regenerate stale artifacts in isolation")
    if current then modes[#modes + 1] = { name = "Baked", toc = "QuestieTDB_Vanilla.toc" } end
  else
    io.write("  SKIP sod-required-races Baked: Vanilla artifact not generated\n")
  end

  for _, mode in ipairs(modes) do
    for _, faction in ipairs({ "Alliance", "Horde" }) do
      client.reset()
      client.install({ expansion = "Classic", season = "SoD", faction = faction })
      emulator.install("QuestieTDB", emulator.parse(mode.toc))
      local db = emulator.loadAddon(mode.toc, "QuestieTDB")
      local label = mode.name .. " " .. faction
      if mode.name == "Source" then
        check(db.read.source.entities.Quest == nil and db.read.source.entities.Npc == nil,
          label .. " keeps Quest/Npc lazy at startup")
      end
      local observed = {}
      for id in pairs(expected) do observed[id] = db.Quest.Get(id, "requiredRaces") end
      equal(observed, expected, label .. " returns every audited mask")

      local registry = db.Corrections
      local entries = registry.Select({ owner = registry.OWNER, datatype = "Quest", dynamic = true })
      local positions, correction = {}, nil
      for index, entry in ipairs(entries) do
        positions[entry.name] = index
        if entry.name == name then correction = entry end
      end
      check(correction ~= nil and positions[name] > positions["Sod/sodQuestFixes.lua:LoadFactionQuestFixes"],
        label .. " authored values follow copied SoD providers")
      local rows = assert(correction).func()
      local masks = {}
      for id, row in pairs(rows) do masks[id] = row[db.Meta.Quest.keys.requiredRaces] end
      equal(masks, expected, label .. " owns exactly the audited rows")

      registry.Set("TestConsumer", "Quest", "race", { [78612] = { [db.Meta.Quest.keys.requiredRaces] = 1 } })
      registry.ApplyRegisteredCorrections(registry.OWNER)
      equal(db.Quest.Get(78612, "requiredRaces"), 1, label .. " consumer wins after owner refresh")
      registry.Set("TestConsumer", "Quest", "race", nil)
      equal(db.Quest.Get(78612, "requiredRaces"), 77, label .. " consumer withdrawal reveals owned data")
      registry.UnregisterCorrection(registry.OWNER, "Quest", name)
      registry.ApplyRegisteredCorrections(registry.OWNER)
      equal(db.Quest.Get(78612, "requiredRaces"), 0, label .. " override withdrawal clears cached mask")
    end
  end

  -- Source lists every flavor's files. Admission must still reject wrong expansions/seasons.
  for _, persona in ipairs({
    { expansion = "Classic", season = 0 },
    { expansion = "Classic", season = 99 },
    { expansion = "TBC", season = 2 },
    { expansion = "Wotlk", season = 2 },
    { expansion = "Cata", season = 2 },
    { expansion = "MoP", season = 2 },
  }) do
    client.reset()
    client.install({ expansion = persona.expansion })
    _G.C_Seasons.GetActiveSeason = function() return persona.season end
    local db = emulator.loadAddon("QuestieTDB.toc", "QuestieTDB")
    local found = false
    for _, entry in ipairs(db.Corrections.Select({ dynamic = true })) do
      if entry.name == name then found = true end
    end
    check(not found, persona.expansion .. " season " .. persona.season .. " rejects the SoD override")
    check(not db.Quest.Exists(78612), persona.expansion .. " inactive persona gains no shipment")
  end
  client.reset()
end
