-- Full-table ObjectiveFirst fidelity, independent of entity-data comparisons.
-- Questie's TOCs select cumulative expansion sources. Its Classic TOC also loads SoD
-- unconditionally; our agreed boundary deliberately admits those hints only during SoD.
local lib = dofile("generator/lib.lua")
local config = dofile("src/config.lua")
config.correctionManifest = dofile("src/corrections/manifest.lua")

local fidelity = {}

---@type string[]
fidelity.fields = {
  "killCreditObjectiveFirst", "objectObjectiveFirst", "itemObjectiveFirst",
  "eventObjectiveFirst", "spellObjectiveFirst",
}

---@return table<string, table<number, boolean>> hints
local function emptyHints()
  local hints = {}
  for _, field in ipairs(fidelity.fields) do hints[field] = {} end
  return hints
end

---@param path string
---@return string[] files
function fidelity.tocFiles(path)
  local files = {}
  for line in lib.readAll(path):gmatch("[^\r\n]+") do
    line = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
  end
  return files
end

---@param source string
---@param label string
---@param env table
---@param namespace table?
---@return nil
local function execute(source, label, env, namespace)
  local chunk = assert(loadstring(source, "@" .. label))
  setfenv(chunk, env)
  chunk("QuestieTDB", namespace)
end

---Execute the pinned files themselves, not parsed assignment literals or provider copies.
---Only module-load effects run; the correction function bodies are not invoked.
---@param sources table[] Entries with path and content.
---@return table hints
function fidelity.capture(sources)
  local hints = emptyHints()
  local modules = { QuestieCorrections = hints }
  ---@param _ table
  ---@param name string
  ---@return table module
  local function moduleFor(_, name)
    modules[name] = modules[name] or {}
    return modules[name]
  end
  local env = setmetatable({ QuestieLoader = { ImportModule = moduleFor, CreateModule = moduleFor } }, { __index = _G })
  env._G = env
  for _, source in ipairs(sources) do execute(source.content, source.path, env) end
  return hints
end

---Discover every hint-bearing correction source in the pinned TOC, including new files.
---Season admission is intentional policy, independent of QuestieTDB's manifest and markers.
---@param questiePath string
---@param flavorName string
---@param seasonId number
---@return table hints
---@return table[] sources
function fidelity.loadOracle(questiePath, flavorName, seasonId)
  local tocNames = { Vanilla = "Classic", TBC = "BCC", Wrath = "WOTLKC", Cata = "Cata", Mists = "Mists" }
  local sources = {}
  for _, file in ipairs(fidelity.tocFiles(questiePath .. "/Questie-" .. assert(tocNames[flavorName]) .. ".toc")) do
    if file:match("^Database/Corrections/") and file ~= "Database/Corrections/QuestieCorrections.lua" then
      local content = lib.readAll(questiePath .. "/" .. file)
      local basename = file:match("([^/]+)$")
      local isSod = basename:match("^sod") ~= nil
      local isTitan = basename:match("^titanReforged") ~= nil
      local applies = (not isSod or (flavorName == "Vanilla" and seasonId == 2)) and
        (not isTitan or (flavorName == "Wrath" and seasonId == 109))
      if applies and content:find("ObjectiveFirst", 1, true) then
        sources[#sources + 1] = { path = file, content = content }
      end
    end
  end
  assert(#sources > 0, "pinned ObjectiveFirst source selection is empty")
  return fidelity.capture(sources), sources
end

---Load the actual correction block without unrelated entity payloads or derived passes.
---The isolated environment also makes sequential persona loads independent of process globals.
---@param files string[] Configured or emitted TOC files.
---@param flavorName string
---@param seasonId number
---@param mode string
---@param root string? Alternate staged addon directory.
---@return table hints
---@return table namespace
---@return table environment Isolated client globals, for load-boundary controls.
function fidelity.loadProvider(files, flavorName, seasonId, mode, root)
  local previousLoader = {}
  local env = setmetatable({ QuestieLoader = previousLoader }, { __index = _G })
  env._G = env
  env.C_Seasons = { GetActiveSeason = function() return seasonId end }
  env.Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
  local namespace = { config = config, flavor = assert(config.flavorByName[flavorName]), mode = mode }
  -- The registry normally precedes the correction block in both full addon TOCs.
  execute(lib.readAll((root or ".") .. "/src/corrections/registry.lua"), "registry.lua", env, namespace)
  for _, file in ipairs(files) do
    if file:match("^src/corrections/") and file ~= "src/corrections/registry.lua" then
      execute(lib.readAll((root or ".") .. "/" .. file), file, env, namespace)
    end
  end
  assert(env.QuestieLoader == previousLoader, "correction loader was not restored")
  assert(namespace.ObjectiveFirst, "correction block did not publish ObjectiveFirst")
  return namespace.ObjectiveFirst, namespace, env
end

---Report every mismatched field/ID, including unknown fields and malformed value shapes.
---@param actual table
---@param expected table
---@return string[] differences
function fidelity.differences(actual, expected)
  local differences, fields = {}, {}
  for field in pairs(actual) do fields[field] = true end
  for field in pairs(expected) do fields[field] = true end
  for field in pairs(fields) do
    local a, e = actual[field], expected[field]
    if type(a) ~= "table" or type(e) ~= "table" then
      if not lib.deepEqual(a, e) then differences[#differences + 1] = field .. " table shape differs" end
    else
      local ids = {}
      for id in pairs(a) do ids[id] = true end
      for id in pairs(e) do ids[id] = true end
      for id in pairs(ids) do
        if not lib.deepEqual(a[id], e[id]) then
          differences[#differences + 1] = field .. "[" .. tostring(id) .. "]: expected " ..
            tostring(e[id]) .. ", got " .. tostring(a[id])
        end
      end
    end
  end
  table.sort(differences)
  return differences
end

---@type table[]
fidelity.personas = {
  { name = "Vanilla", flavor = "Vanilla", season = 0 },
  { name = "SoD", flavor = "Vanilla", season = 2 },
  { name = "TBC", flavor = "TBC", season = 0 },
  { name = "Wrath", flavor = "Wrath", season = 0 },
  { name = "Titan", flavor = "Wrath", season = 109 },
  { name = "Cata", flavor = "Cata", season = 0 },
  { name = "Mists", flavor = "Mists", season = 0 },
  { name = "Vanilla unsupported season", flavor = "Vanilla", season = 99 },
  { name = "Vanilla Titan", flavor = "Vanilla", season = 109 },
  { name = "TBC SoD", flavor = "TBC", season = 2 },
  { name = "Wrath SoD", flavor = "Wrath", season = 2 },
  { name = "Cata SoD", flavor = "Cata", season = 2 },
  { name = "Mists SoD", flavor = "Mists", season = 2 },
  { name = "TBC Titan", flavor = "TBC", season = 109 },
  { name = "Cata Titan", flavor = "Cata", season = 109 },
  { name = "Mists Titan", flavor = "Mists", season = 109 },
  { name = "Vanilla after seasons", flavor = "Vanilla", season = 0 },
}

---@param check fun(condition: boolean, message: string)
---@param questiePath string
---@param stagedRoot string? Also check emitted TOCs in a stripped staged addon.
---@return nil
function fidelity.run(check, questiePath, stagedRoot)
  lib.assertQuestiePin(questiePath)
  local sourceFiles = fidelity.tocFiles("QuestieTDB.toc")
  for _, persona in ipairs(fidelity.personas) do
    local flavor = config.flavorByName[persona.flavor]
    local expected, inputs = fidelity.loadOracle(questiePath, persona.flavor, persona.season)
    local bakedFiles = config.bakedFileList(flavor)
    local modes = {
      { name = "Source", files = sourceFiles, mode = "source" },
      { name = "Baked selection", files = bakedFiles, mode = "baked" },
    }
    local bakedToc = config.tocPath(flavor)
    if lib.fileExists(bakedToc) then
      modes[#modes + 1] = { name = "emitted Baked", files = fidelity.tocFiles(bakedToc), mode = "baked" }
    end
    if stagedRoot then
      modes[#modes + 1] = { name = "stripped package", files = fidelity.tocFiles(stagedRoot .. "/" .. bakedToc),
        mode = "baked", root = stagedRoot }
    end
    for _, mode in ipairs(modes) do
      local actual = fidelity.loadProvider(mode.files, persona.flavor, persona.season, mode.mode, mode.root)
      local differences = fidelity.differences(actual, expected)
      check(#differences == 0, persona.name .. " " .. mode.name .. " pinned hints: " .. table.concat(differences, "; "))
    end

    -- A new static-only hint source must not disappear just because Baked ships Dynamic files.
    local shipped = {}
    for _, file in ipairs(bakedFiles) do shipped[file:match("([^/]+)$")] = true end
    for _, input in ipairs(inputs) do
      check(shipped[input.path:match("([^/]+)$")] == true, persona.name .. " Baked retains " .. input.path)
    end
  end
end

return fidelity
