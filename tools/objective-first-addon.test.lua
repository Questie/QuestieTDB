-- Full-addon and stripped-package coverage. Run after Generation in an isolated checkout;
-- the focused objective-first suite needs no entity payload generation.
local lib = dofile("generator/lib.lua")
local config = dofile("src/config.lua")
local fidelity = dofile("tools/objective-first.lua")
-- Earlier suites may leave a LibStub mock that cannot register LibDeflate. Load the
-- client's offline dependencies without it, then restore it even if loading fails.
local savedLibStub = rawget(_G, "LibStub")
_G.LibStub = nil
local clientLoaded, client = pcall(dofile, "emulator/client.lua")
_G.LibStub = savedLibStub
assert(clientLoaded, client)
local emulator = dofile("emulator/metadata.lua")

---@param value string
---@return string quoted
local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

---@param command string
---@return boolean succeeded
local function succeeds(command)
  local status = os.execute(command)
  return status == true or status == 0
end

---@param check fun(condition: boolean, message: string)
---@param questiePath string
---@return nil
return function(check, questiePath)
  local generated, available = {}, {}
  for _, flavor in ipairs(config.flavors) do
    if lib.fileExists(config.tocPath(flavor)) then
      generated[#generated + 1] = flavor
      available[flavor.name] = true
    else
      io.write("  SKIP objective-first-addon Baked/stripped ", flavor.name, ": artifact not generated\n")
    end
  end
  if #generated == 0 then return end
  lib.assertQuestiePin(questiePath)

  -- Stage the union of the actual emitted file lists, like the combined release package.
  -- Use a unique directory and remove only this test's copies, including on assertion errors.
  local pipe = assert(io.popen("mktemp -d"))
  local stage = assert(pipe:read("*l"))
  pipe:close()
  local ok, err = pcall(function()
    local copied = {}
    for _, flavor in ipairs(generated) do
      local toc = config.tocPath(flavor)
      lib.copyFile(toc, stage .. "/" .. toc)
      for _, file in ipairs(fidelity.tocFiles(toc)) do
        if not copied[file] then
          lib.mkdirp(stage .. "/" .. assert(file:match("^(.+)/")))
          lib.copyFile(file, stage .. "/" .. file)
          copied[file] = true
        end
      end
    end
    local lua = os.getenv("LUA") or "lua5.1"
    assert(succeeds(quote(lua) .. " tools/strip-static.lua " .. quote(stage) .. " --quiet"),
      "staged package failed Static Correction stripping and per-file behavior parity")
    local stripped = lib.readAll(stage .. "/src/corrections/Era/classicQuestFixes.lua")
    check(stripped:find("Static body stripped at package time", 1, true) ~= nil,
      "the staged addon really contains stripped correction bodies")

    -- The first seven entries are the supported base/season personas. Repeat plain Vanilla
    -- last to make leakage after expansion and seasonal loads observable in one process.
    local personas = {}
    for index = 1, 7 do personas[#personas + 1] = fidelity.personas[index] end
    personas[#personas + 1] = fidelity.personas[1]
    for _, persona in ipairs(personas) do
      local flavor = config.flavorByName[persona.flavor]
      local expected = fidelity.loadOracle(questiePath, persona.flavor, persona.season)
      local modes = { { name = "Source", mode = "source", toc = "QuestieTDB.toc" } }
      if available[flavor.name] then
        modes[#modes + 1] = { name = "Baked", mode = "baked", toc = config.tocPath(flavor) }
        modes[#modes + 1] = { name = "stripped package", mode = "baked",
          toc = stage .. "/" .. config.tocPath(flavor), root = stage }
      end
      local sourceHints
      for _, mode in ipairs(modes) do
        client.reset()
        client.install({ expansion = flavor.expansion })
        _G.C_Seasons.GetActiveSeason = function() return persona.season end
        _G.C_Seasons.HasActiveSeason = function() return persona.season ~= 0 end
        emulator.install(config.addonName, emulator.parse(mode.toc))
        local namespace = emulator.loadAddon(mode.toc, config.addonName, mode.root)
        local label = persona.name .. " full " .. mode.name
        check(namespace.mode == mode.mode, label .. " selects the expected backend")
        local differences = fidelity.differences(namespace.ObjectiveFirst, expected)
        check(#differences == 0, label .. " pinned hints: " .. table.concat(differences, "; "))
        check(namespace.ObjectiveFirst == namespace.CorrectionCompat.objectiveFirst,
          label .. " publishes the original hint table")
        sourceHints = sourceHints or namespace.ObjectiveFirst
        check(lib.deepEqual(namespace.ObjectiveFirst, sourceHints), label .. " matches Source full tables")
        check(rawget(_G, "QuestieLoader") == nil, label .. " restores QuestieLoader")
        -- Retain only the small hint tables, not multi-expansion entity payloads.
        namespace = nil
        client.reset()
        collectgarbage("collect")
      end
    end
  end)
  client.reset()
  local cleaned = succeeds("rm -rf -- " .. quote(stage))
  check(cleaned, "removed only the temporary ObjectiveFirst addon stage")
  assert(ok, err)
end
