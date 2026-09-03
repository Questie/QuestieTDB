-- generator/l10n.lua
--
-- Entity localization: extracts Questie's per-locale lookup tables and emits one compressed
-- CBOR column block per locale and entity type.
--
-- This removes Questie's recompile-on-locale-change. A non-enUS client decodes its available
-- entity-type blocks and keeps those translations in memory; enUS uses base data and decodes
-- no localization blocks.
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
local encode = dofile("generator/encode.lua")

local l10n = {}

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

---Which lookup directory and module field each entity type uses, and how source values map to
---compact Localization-block columns. Coverage matches what Questie translates today.
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

---Resolve one Questie localization lookup file.
---@param questiePath string
---@param flavor table
---@param typeCfg table
---@param locale string
---@return string path
function l10n.lookupPath(questiePath, flavor, typeCfg, locale)
  return ("%s/Localization/lookups/%s/%s/%s.lua")
    :format(questiePath, flavor.expansion, typeCfg.dir, locale)
end

---Fails before Generation opens an artifact when any required lookup file is absent.
---A missing tree is allowed only through the caller's explicit `--no-l10n` choice.
---@param questiePath string Questie checkout used as the localization source.
---@param flavors table[] Flavors selected for Generation.
---@param typeFilter table<string, boolean>? Entity types selected for Generation.
---@return nil
function l10n.assertInputs(questiePath, flavors, typeFilter)
  local missing = {}

  for _, flavor in ipairs(flavors) do
    for typeName, typeCfg in pairs(l10n.types) do
      if not typeFilter or typeFilter[typeName] then
        for _, locale in ipairs(config.locales) do
          local path = l10n.lookupPath(questiePath, flavor, typeCfg, locale)
          if not lib.fileExists(path) then missing[#missing + 1] = path end
        end
      end
    end
  end

  if #missing == 0 then return end

  table.sort(missing)
  local shown = {}
  for index = 1, math.min(#missing, 5) do shown[#shown + 1] = "  " .. missing[index] end
  if #missing > #shown then
    shown[#shown + 1] = ("  ... and %d more"):format(#missing - #shown)
  end

  error(("l10n: %d required Questie lookup files are missing. Pass the correct Questie " ..
    "checkout with --questie=<path>, or explicitly generate without localization with " ..
    "--no-l10n:\n%s"):format(#missing, table.concat(shown, "\n")), 0)
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
                -- List-valued fields keep their table shape; a bare string becomes a
                -- one-element list so the field's type is stable across locales.
                local list = row[fieldCfg.from]
                if type(list) == "table" and next(list) ~= nil then
                  value = list
                elseif type(list) == "string" and list ~= "" then
                  value = { list }
                end
              else
                value = row[fieldCfg.from]
              end
              if type(value) == "string" then
                -- Preserve the established display-text cleanup even though CBOR can carry
                -- these bytes. Edge whitespace varied by the old segment position, and a
                -- leading DEL was observed on TBC NPC 24996's zhTW name.
                value = value:gsub("[%z\1-\31\127]", "")
                value = value:match("^[ \t\r\n]*(.-)[ \t\r\n]*$")
                if value == "" then value = nil end
              end
              if value ~= nil then
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
-- Column blocks
--------------------------------------------------------------------------------------------

---Build one locale's field columns aligned with the entity backend's ascending ID list.
---A missing translation leaves a nil hole, so the runtime falls back to the base field.
---@param typeName string
---@param values table<number, table> Output from l10n.extract.
---@param ids number[] Exact ascending base entity IDs stored in the artifact.
---@param localeIndex number Index in config.locales.
---@return table block Compact field index -> values by base ID position.
---@return integer translatedEntities
---@return integer translatedValues
function l10n.buildBlock(typeName, values, ids, localeIndex)
  local fieldCount = #l10n.types[typeName].fields
  local block = {}
  for fieldIndex = 1, fieldCount do block[fieldIndex] = {} end

  local translatedEntities, translatedValues = 0, 0
  for position, id in ipairs(ids) do
    local byField = values[id]
    local entityHasTranslation = false
    if byField then
      for fieldIndex = 1, fieldCount do
        local slots = byField[fieldIndex]
        local value = slots and slots[localeIndex]
        if value ~= nil then
          block[fieldIndex][position] = value
          translatedValues = translatedValues + 1
          entityHasTranslation = true
        end
      end
    end
    if entityHasTranslation then translatedEntities = translatedEntities + 1 end
  end

  return block, translatedEntities, translatedValues
end

---Write the localization format marker once before any blocks.
---@param out file*
---@return integer lines
function l10n.writeHeader(out)
  return lib.writeMetadata(out, config.l10nHeaderKey, tostring(config.l10nVersion),
    config.maxValueLength)
end

---Write all locale blocks for one entity type.
---@param out file*
---@param typeName string
---@param values table<number, table> Output from l10n.extract.
---@param ids number[] Exact ascending base entity IDs stored in the artifact.
---@return table stats Block count, translated counts, encoded bytes, and emitted lines.
function l10n.writeMetadata(out, typeName, values, ids)
  local stats = { blocks = 0, translatedEntities = 0, translatedValues = 0, bytes = 0, lines = 0 }

  for localeIndex, locale in ipairs(config.locales) do
    local block, entityCount, valueCount = l10n.buildBlock(typeName, values, ids, localeIndex)
    local encoded = encode.compressedCbor(block)
    stats.lines = stats.lines + lib.writeMetadata(out,
      config.l10nBlockKey(typeName, locale), encoded, config.maxValueLength)
    stats.blocks = stats.blocks + 1
    stats.translatedEntities = stats.translatedEntities + entityCount
    stats.translatedValues = stats.translatedValues + valueCount
    stats.bytes = stats.bytes + #encoded
  end

  return stats
end

return l10n
