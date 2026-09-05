-- Semantic support-data oracle. Runs through test.lua's support-fidelity suite, so both
-- the normal quality job and tools/check.sh all enforce it without generated entity data.
local lib = dofile("generator/lib.lua")
local config = dofile("src/config.lua")
local inventory = dofile("tools/support-inventory.lua")

local fidelity = {}

local luaFields = {}
for _, input in ipairs(inventory) do
  for _, field in ipairs(input.luaFields or {}) do luaFields[field] = true end
end

---Normalize declared Lua fields for comparison without erasing their public value types.
---Only inventory paths are decoded; ordinary strings remain literal, even if they look like Lua.
---@param value any
---@param path string? Published module field path, omitted for the module root.
---@return any value
function fidelity.materialize(value, path)
  if luaFields[path] then
    local decoded = value
    if type(value) == "string" then
      local chunk = assert(loadstring(value))
      setfenv(chunk, {})
      decoded = chunk()
      assert(type(decoded) == "table", path .. " must return a table")
    end
    return { sourceType = type(value), value = decoded }
  end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, entry in pairs(value) do
    local field = path and (path .. "." .. tostring(key)) or tostring(key)
    result[key] = fidelity.materialize(entry, field)
  end
  return result
end

---Return one localized mismatch rather than dumping entire XP or drop datasets.
---@param actual any
---@param expected any
---@param path string?
---@return string? difference
function fidelity.difference(actual, expected, path)
  path = path or "Support"
  if lib.deepEqual(actual, expected) then return nil end
  if type(actual) ~= "table" or type(expected) ~= "table" then
    local expectedText = type(expected) == "table" and "<table>" or lib.show(expected)
    local actualText = type(actual) == "table" and "<table>" or lib.show(actual)
    return path .. ": expected " .. expectedText .. ", got " .. actualText
  end
  local keys, seen = {}, {}
  for key in pairs(actual) do keys[#keys + 1], seen[key] = key, true end
  for key in pairs(expected) do
    if not seen[key] then keys[#keys + 1] = key end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    local difference = fidelity.difference(actual[key], expected[key], path .. "[" .. tostring(key) .. "]")
    if difference then return difference end
  end
end

---Validate the nested list contract separately from upstream equality.
---@param dungeons table
---@return string? error
function fidelity.dungeonShape(dungeons)
  for id, dungeon in pairs(dungeons) do
    local alternatives = dungeon[2]
    if alternatives ~= nil then
      if type(alternatives) ~= "table" then return "dungeon " .. id .. " alternatives must be a list" end
      local count = 0
      for key, areaId in pairs(alternatives) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or
            type(areaId) ~= "number" or areaId % 1 ~= 0 then
          return "dungeon " .. id .. " alternatives must contain integer area IDs at positive integer keys"
        end
        count = count + 1
      end
      for index = 1, count do
        if alternatives[index] == nil then return "dungeon " .. id .. " alternatives must be dense" end
      end
    end
  end
end

---Keep the loader and faction fact local even when a source fails during execution.
---@param faction string
---@return table environment
local function environment(faction)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.UnitFactionGroup = function() return faction end
  return env
end

---@param path string
---@param env table
---@param namespace table?
---@return nil
local function execute(path, env, namespace)
  local chunk = assert(loadfile(path))
  setfenv(chunk, env)
  chunk("QuestieTDB", namespace)
end

---Load the real support block without loading unrelated entity data or requiring artifacts.
---@param files string[] Full configured or emitted TOC file list.
---@param flavor table
---@param faction string
---@return table modules Raw public module values, not materialized copies.
function fidelity.loadProvider(files, flavor, faction)
  local env = environment(faction)
  local previousLoader = {}
  env.QuestieLoader = previousLoader
  local namespace = { config = config, flavor = flavor }
  for _, file in ipairs(files) do
    if file == "src/corrections/enum/constants.lua" or file:match("^src/support/") or
        file:match("^support/") then
      execute(file, env, namespace)
    end
  end
  assert(env.QuestieLoader == previousLoader, "support loader was not restored")
  return namespace.Support.GetAll()
end

---Independent Questie loader: no provider shim, config selection, or copied constants.
---@param files string[] Absolute or working-directory-relative paths.
---@param flavor table
---@param faction string
---@param dropKeys table
---@return table modules
function fidelity.loadInputs(files, flavor, faction, dropKeys)
  local order = { Vanilla = 1, TBC = 2, Wrath = 3, Cata = 4, Mists = 5 }
  local modules = {
    Expansions = { private = {}, Era = 1, Classic = 1, Tbc = 2, Wotlk = 3, Cata = 4,
      MoP = 5, Current = assert(order[flavor.name]) },
    DropDB = { private = {}, correctionKeys = dropKeys },
  }
  local env = environment(faction)
  ---@param _ table
  ---@param name string
  ---@return table module
  local function moduleFor(_, name)
    modules[name] = modules[name] or { private = {} }
    return modules[name]
  end
  env.QuestieLoader = { ImportModule = moduleFor, CreateModule = moduleFor }
  for _, file in ipairs(files) do execute(file, env) end
  return modules
end

---@param path string
---@return string[] paths
local function tocFiles(path)
  local files = {}
  for line in lib.readAll(path):gmatch("[^\r\n]+") do
    line = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
  end
  return files
end

---@param check fun(condition: boolean, message: string)
---@param questiePath string
---@return nil
function fidelity.run(check, questiePath)
  lib.assertQuestiePin(questiePath)
  local byLocal, byQuestie = {}, {}
  for _, input in ipairs(inventory) do
    assert(not byLocal[input.file] and not byQuestie[input.questie], "duplicate support inventory entry")
    byLocal[input.file], byQuestie[input.questie] = input, input
  end

  -- This small dependency belongs to DropDB's wrapper, not a support dataset. Read its
  -- literal from pinned Questie so drift in the provider's extracted constants is visible.
  local dropSource = lib.readAll(questiePath .. "/Database/DropTables/dropDB.lua")
  local dropLiteral = assert(dropSource:match("DropDB%.correctionKeys%s*=%s*(%b{})"))
  local dropKeys = assert(loadstring("return " .. dropLiteral))()
  local oracleTocs = { Vanilla = "Classic", TBC = "BCC", Wrath = "WOTLKC", Cata = "Cata", Mists = "Mists" }
  local visited = {}
  local sourceFiles = config.sourceFileList()
  local committedFiles = tocFiles("QuestieTDB.toc")

  for _, flavor in ipairs(config.flavors) do
    local configured, expectedPaths, expectedSet = {}, {}, {}
    for _, file in ipairs(config.supportData.shared) do configured[file] = true end
    for _, file in ipairs(config.supportData.perFlavor[flavor.name]) do configured[file] = true end

    -- Questie's actual TOC owns applicability and cumulative ordering, including Mists'
    -- MoP-then-Cata drop data. Fail closed when a newly published dataset has no inventory row.
    for _, file in ipairs(tocFiles(questiePath .. "/Questie-" .. oracleTocs[flavor.name] .. ".toc")) do
      local supportFile = file:match("^Database/Zones/data/") or file:match("^Database/QuestXP/DB/") or
        file:match("^Database/FactionTemplates/factionTemplate") or file:match("^Database/DropTables/data/")
      if supportFile then
        local input = assert(byQuestie[file], "unmapped pinned support input: " .. file)
        expectedPaths[#expectedPaths + 1] = questiePath .. "/" .. file
        expectedSet[input.file] = true
      end
    end
    local selectionDifference = fidelity.difference(configured, expectedSet, flavor.name .. " file selection")
    check(selectionDifference == nil, selectionDifference or (flavor.name .. " selects every pinned support input"))
    for file in pairs(configured) do
      assert(byLocal[file], "unmapped configured support input: " .. file)
      visited[file] = true
    end

    for _, faction in ipairs({ "Alliance", "Horde" }) do
      local label = flavor.name .. " " .. faction
      local expected = fidelity.materialize(fidelity.loadInputs(expectedPaths, flavor, faction, dropKeys))
      local source = fidelity.loadProvider(sourceFiles, flavor, faction)
      local baked = fidelity.loadProvider(config.bakedFileList(flavor), flavor, faction)
      local committed = fidelity.loadProvider(committedFiles, flavor, faction)
      local modes = { { "Source", source }, { "Baked", baked }, { "committed Source TOC", committed } }
      -- The configured blocks above always run. When Generation has emitted an artifact,
      -- also check its actual support list; the full gate generates all five before testing.
      local bakedToc = config.tocPath(flavor)
      if lib.fileExists(bakedToc) then
        modes[#modes + 1] = { "emitted Baked TOC", fidelity.loadProvider(tocFiles(bakedToc), flavor, faction) }
      end
      for _, mode in ipairs(modes) do
        local difference = fidelity.difference(fidelity.materialize(mode[2]), expected, label .. " " .. mode[1])
        check(difference == nil, difference or (label .. " " .. mode[1] .. " matches pinned support modules"))
        local shapeError = fidelity.dungeonShape(mode[2].ZoneDB.private.dungeons)
        check(shapeError == nil, label .. " " .. mode[1] .. " dungeon shape: " .. tostring(shapeError))
      end
      check(lib.deepEqual(source, baked), label .. " Source/Baked preserve identical public raw value shapes")
      check(source.ZoneDB.zoneIDs.THE_RING_OF_TRIALS == 9999, label .. " includes THE_RING_OF_TRIALS")
      check(source.ZoneDB.private.dungeons[2257][1] == "Deeprun Tram", label .. " names Deeprun Tram correctly")

      -- Compare each copied source independently too. Final module equality alone could hide
      -- a stale value that a subsequent file overwrites. Seed instance-map dependencies once.
      for file in pairs(configured) do
        local input = byLocal[file]
        local seed = questiePath .. "/Database/Zones/data/zoneIds.lua"
        local actual = fidelity.materialize(fidelity.loadInputs({ seed, file }, flavor, faction, dropKeys))
        local upstream = fidelity.materialize(fidelity.loadInputs({ seed, questiePath .. "/" .. input.questie }, flavor, faction, dropKeys))
        local difference = fidelity.difference(actual, upstream, label .. " " .. file)
        check(difference == nil, difference or (label .. " " .. file .. " matches pinned values"))
        for _, field in ipairs(input.fields) do
          local value = actual
          for key in field:gmatch("[^.]+") do value = type(value) == "table" and value[key] or nil end
          check(value ~= nil, file .. " publishes " .. field)
        end
      end
    end
  end
  for file in pairs(byLocal) do check(visited[file] == true, "inventory input is configured: " .. file) end
end

return fidelity
