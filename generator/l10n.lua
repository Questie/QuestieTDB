-- generator/l10n.lua
--
-- Entity localization: extracts Questie's per-locale lookup tables and emits them as
-- locale-joined metadata alongside entity data.
--
-- This is what removes Questie's recompile-on-locale-change. Today `l10n:Initialize()` writes
-- translated strings into `questData` *before* compile and `dbCompiledLang` forces a full
-- rebuild when the UI locale changes. Storing every locale in one value and extracting the Nth
-- segment on access makes locale a read-time concern.
--
-- ## Reading every locale in one run
--
-- Each of the 180 lookup files opens with a client-locale guard:
--
--     if GetLocale() ~= "deDE" then
--         return
--     end
--
-- byte-identical across all of them. So one generation run reads every locale by re-stubbing
-- `GetLocale()` between files — which is exactly what the mocked-environment loader is for.
--
-- ## Memory
--
-- The lookup tree is 214 MB of Lua across 180 files. Entity types are processed one at a time
-- and their metadata written before the next begins, so peak cost is one type's nine locales
-- rather than all four types at once.

local config = dofile("src/config.lua")
local lib = dofile("generator/lib.lua")
local loader = dofile("generator/loader.lua")

local l10n = {}

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- Which lookup directory and module field each entity type uses, and how a row maps onto the
--- compact l10n field indices. Coverage matches what Questie translates today, and no more.
l10n.types = {
  Quest = {
    dir = "lookupQuests", field = "questLookup",
    -- [questId] = { name, { objectivesText, ... } }
    fields = { { name = "name", from = 1 }, { name = "objectivesText", from = 2, list = true } },
  },
  Npc = {
    dir = "lookupNpcs", field = "npcNameLookup",
    -- [npcId] = { name, subName }
    fields = { { name = "name", from = 1 }, { name = "subName", from = 2 } },
  },
  Item = {
    dir = "lookupItems", field = "itemLookup",
    -- [itemId] = name
    scalar = true, fields = { { name = "name" } },
  },
  Object = {
    dir = "lookupObjects", field = "objectLookup",
    -- [objectId] = name
    scalar = true, fields = { { name = "name" } },
  },
}

--- Separator between locales. U+2021 DOUBLE DAGGER.
l10n.localeSeparator = config.localeSeparator

--- Separator between the elements of a list-valued field — only `objectivesText`.
--- U+2016 DOUBLE VERTICAL LINE. Generation asserts no source string contains either
--- separator, so a collision is a build failure rather than a silent corruption.
l10n.listSeparator = "\226\128\150"

function l10n.lookupPath(questiePath, flavor, typeCfg, locale)
  return ("%s/Localization/lookups/%s/%s/%s.lua")
    :format(questiePath, flavor.expansion, typeCfg.dir, locale)
end

--------------------------------------------------------------------------------------------
-- Extraction
--------------------------------------------------------------------------------------------

--- Load one entity type's nine locale files and return `id -> fieldIndex -> { 9 slots }`.
---
---@param questiePath string
---@param flavor table
---@param typeName string
---@param knownIds table id -> true; entries with no main-DB row are dropped
---@return table values
---@return table stats
function l10n.extract(questiePath, flavor, typeName, knownIds)
  local typeCfg = l10n.types[typeName]
  local values = {}
  local stats = { locales = 0, entries = 0, filtered = 0, missingFiles = {} }

  local module = { questLookup = {}, npcNameLookup = {}, objectLookup = {}, itemLookup = {} }

  for localeIndex, locale in ipairs(config.locales) do
    local path = l10n.lookupPath(questiePath, flavor, typeCfg, locale)
    if not lib.fileExists(path) then
      stats.missingFiles[#stats.missingFiles + 1] = path
    else
      loader.installEnvironment({ locale = locale })
      -- The lookup files assign into the `l10n` module; give them a fresh one each time so a
      -- locale that fails its own guard cannot leave the previous locale's table in place.
      local modules = QuestieLoader._modules
      modules.l10n = module
      module[typeCfg.field] = {}

      loader.executeFile(path)

      local payload = module[typeCfg.field][locale]
      if type(payload) == "function" then payload = payload() end
      if type(payload) == "table" then
        stats.locales = stats.locales + 1
        for id, row in pairs(payload) do
          if knownIds[id] then
            local byField = values[id]
            if not byField then byField = {}; values[id] = byField end
            for fieldIndex, fieldCfg in ipairs(typeCfg.fields) do
              local value
              if typeCfg.scalar then
                value = row
              elseif fieldCfg.list then
                local list = row[fieldCfg.from]
                if type(list) == "table" then
                  value = table.concat(list, l10n.listSeparator)
                elseif type(list) == "string" then
                  value = list
                end
              else
                value = row[fieldCfg.from]
              end
              if type(value) == "string" and value ~= "" then
                local slots = byField[fieldIndex]
                if not slots then slots = {}; byField[fieldIndex] = slots end
                slots[localeIndex] = value
              end
            end
          else
            stats.filtered = stats.filtered + 1
          end
        end
      end
    end
  end

  for _ in pairs(values) do stats.entries = stats.entries + 1 end
  return values, stats
end

--------------------------------------------------------------------------------------------
-- Emission
--------------------------------------------------------------------------------------------

--- Join nine locale slots into one stored value. An empty segment means "no translation for
--- this locale"; the reader falls back to the base entity value.
function l10n.join(slots)
  local parts, last = {}, 0
  for index = 1, #config.locales do
    local value = slots[index]
    if value then
      -- A separator inside a value would make the segments unrecoverable. Fail the build
      -- rather than emit something that decodes wrong.
      if value:find(l10n.localeSeparator, 1, true) then
        error("l10n: a translation contains the locale separator: " .. value:sub(1, 80), 0)
      end
      parts[index] = value
      last = index
    else
      parts[index] = ""
    end
  end
  if last == 0 then return nil end
  -- Trailing empty segments carry no information and cost bytes across ~500k values.
  for index = #parts, last + 1, -1 do parts[index] = nil end
  return table.concat(parts, l10n.localeSeparator)
end

--- Write one entity type's localization metadata.
---@return number entries
---@return number fields
function l10n.writeMetadata(out, typeName, values)
  local prefix = "X-" .. config.l10nMetaPrefix .. typeName .. "-"
  local ids = lib.sortedIds(values)
  local fields = 0

  for _, id in ipairs(ids) do
    local byField = values[id]
    for fieldIndex = 1, #l10n.types[typeName].fields do
      local slots = byField[fieldIndex]
      if slots then
        local joined = l10n.join(slots)
        if joined then
          lib.writeMetadata(out, prefix .. id .. "-" .. fieldIndex, joined, config.maxValueLength)
          fields = fields + 1
        end
      end
    end
  end

  lib.writeMetadata(out, prefix .. "IDS-LIST", table.concat(ids, ","), config.maxValueLength)
  return #ids, fields
end

return l10n
