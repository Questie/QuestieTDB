-- generator/loader.lua
--
-- Mocked-environment loader for Questie-shaped Lua sources.
--
-- Every generation input is already Lua, so this is a loader, not a parser: it stands up just
-- enough of the WoW addon environment for the file to execute, then reads the tables the file
-- assigned. Derived from Questie's cli/apiMocks.lua and cli/loadTOC.lua, which load the
-- database the same way for `validate-era.lua` today.
--
-- Raw entity data files are self-contained — each one defines both its `*Keys` enum and its
-- `*Data` payload — so schema and data arrive together and the only mock they need is
-- `QuestieLoader:ImportModule`.

local loader = {}

--------------------------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------------------------

local function emptyFunction() end
local function emptyTable() return {} end

--- Install the minimal global environment a Questie source file expects.
--- Returns the QuestieDB module table that loaded files will write into.
---@param opts table? { locale = "enUS", isClassic = boolean, expansion = number }
function loader.installEnvironment(opts)
  opts = opts or {}

  local modules = {}

  QuestieLoader = {
    ImportModule = function(_, name)
      local module = modules[name]
      if not module then
        module = {}
        modules[name] = module
      end
      return module
    end,
    CreateModule = function(_, name)
      local module = modules[name]
      if not module then
        module = {}
        modules[name] = module
      end
      return module
    end,
    _modules = modules,
  }

  Questie = Questie or {}
  Questie.IsClassic = opts.isClassic
  Questie.IsTBC = opts.isTBC
  Questie.IsWotlk = opts.isWotlk
  Questie.IsCata = opts.isCata
  Questie.IsMoP = opts.isMoP
  Questie.IsSoD = opts.isSoD or false
  Questie.db = Questie.db or { profile = {}, global = {}, char = {} }

  -- Locale is stubbed rather than detected. Localization lookup files open with a
  -- `if GetLocale() ~= "deDE" then return end` guard, so one generation run reads every
  -- locale by re-stubbing this between files. See generator/l10n.lua.
  local locale = opts.locale or "enUS"
  GetLocale = function() return locale end
  loader.setLocale = function(newLocale) locale = newLocale end

  -- Small surface used incidentally by schema and correction files.
  tinsert = table.insert
  tremove = table.remove
  wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
  end
  strsplit = function(delimiter, text)
    local result = {}
    for piece in string.gmatch(text, "([^" .. delimiter .. "]+)") do
      result[#result + 1] = piece
    end
    return unpack(result)
  end
  hooksecurefunc = emptyFunction
  CreateFrame = function()
    return {
      Show = emptyFunction, Hide = emptyFunction, SetScript = emptyFunction,
      RegisterEvent = emptyFunction, UnregisterEvent = emptyFunction, SetOwner = emptyFunction,
    }
  end
  C_Timer = { After = function(_, fn) if fn then fn() end end, NewTicker = emptyFunction }
  C_Seasons = { HasActiveSeason = function() return false end, GetActiveSeason = function() return 0 end }
  C_AddOns = C_AddOns or {}
  Enum = Enum or { SeasonID = { SeasonOfMastery = 1, SeasonOfDiscovery = 2, Hardcore = 3 } }
  LibStub = setmetatable(
    { NewLibrary = emptyFunction, GetLibrary = emptyTable },
    { __call = function() return { NewAddon = emptyTable, New = emptyTable } end }
  )

  return QuestieLoader:ImportModule("QuestieDB")
end

--------------------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------------------

--- Execute a Lua source file inside the mocked environment, passing WoW's addon varargs.
---@param path string
---@param addonName string?
---@param addonTable table?
function loader.executeFile(path, addonName, addonTable)
  local chunk, err = loadfile(path)
  if not chunk then
    error("Cannot load " .. path .. ": " .. tostring(err), 0)
  end
  local ok, execErr = pcall(chunk, addonName or "QuestieTDB", addonTable or {})
  if not ok then
    error("Error executing " .. path .. ": " .. tostring(execErr), 0)
  end
end

--- Load one raw entity data file.
---
--- Returns the decoded entity table (id -> field array) and the file's own copy of the
--- Database Key Enum. The keys travelling with the data is the mechanical reason Questie is
--- the schema source of truth.
---@param path string Path to e.g. data/Classic/classicQuestDB.lua
---@param entityType table An entry from config.entityTypes
---@return table entities id -> { [fieldIndex] = value }
---@return table keys fieldName -> fieldIndex
function loader.loadEntityData(path, entityType)
  local QuestieDB = loader.installEnvironment()
  loader.executeFile(path)

  local keys = QuestieDB[entityType.keysField]
  if type(keys) ~= "table" then
    error(path .. " did not define QuestieDB." .. entityType.keysField, 0)
  end

  local payload = QuestieDB[entityType.dataField]
  if type(payload) ~= "string" then
    error(path .. " did not define QuestieDB." .. entityType.dataField .. " as a string", 0)
  end

  local chunk, err = loadstring(payload, path .. ":" .. entityType.dataField)
  if not chunk then
    error("Cannot parse " .. entityType.dataField .. " in " .. path .. ": " .. tostring(err), 0)
  end
  local entities = chunk()
  if type(entities) ~= "table" then
    error(entityType.dataField .. " in " .. path .. " did not return a table", 0)
  end

  return entities, keys
end

--- Load Questie's standalone schema file for one entity type, which is the only source of
--- `*CompilerTypes`. Unlike the data files these reference `Questie.IsClassic` and the
--- `Expansions` module, so the environment must be stood up with a flavor.
---@param path string Path to Questie's Database/<entity>DB.lua
---@param entityType table An entry from config.entityTypes
---@param opts table? Flavor flags forwarded to installEnvironment
---@return table keys
---@return table compilerTypes
function loader.loadSchemaFile(path, entityType, opts)
  local QuestieDB = loader.installEnvironment(opts)
  -- `Expansions` is imported by npcDB.lua for its npcFlags table; give it plausible values so
  -- the comparisons inside that table do not error.
  local Expansions = QuestieLoader:ImportModule("Expansions")
  Expansions.Classic, Expansions.Tbc, Expansions.Wotlk, Expansions.Cata, Expansions.MoP = 1, 2, 3, 4, 5
  Expansions.Current = (opts and opts.expansion) or 1

  loader.executeFile(path)
  return QuestieDB[entityType.keysField], QuestieDB[entityType.typesField]
end

return loader
