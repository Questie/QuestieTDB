-- src/l10n/overlay.lua
--
-- The optional localization layer for selected composed entity fields in the active locale.
--
-- Baked artifacts store one compressed CBOR column block per locale and entity type. Columns
-- align with the backend's ascending base ID list. A non-enUS client eagerly decodes its
-- available type blocks during addon load and keeps those translations in memory; enUS
-- decodes none.
--
-- Locale changes replace the active blocks and invalidate entity caches. Correction values
-- still outrank translations, and translated tables still pass through shared.lua's copy
-- producer so every caller receives a fresh mutable value.

local _, LibQuestieDB = ...

local overlay = {}

local config = LibQuestieDB.config
local Encoding = C_EncodingUtil

--------------------------------------------------------------------------------------------
-- Locale and field coverage
--------------------------------------------------------------------------------------------

overlay.locales = config.locales
overlay.localeIndex = {}
for index, locale in ipairs(config.locales) do overlay.localeIndex[locale] = index end

overlay.currentLocale = "enUS"
overlay.currentIndex = nil
overlay.onLocaleChanged = {}
overlay.available = false

-- Compact field indices match generator/l10n.lua. They are intentionally separate from entity
-- field indices, which differ by schema.
overlay.fields = {
  Quest = { { name = "name" }, { name = "objectivesText", list = true } },
  Npc = { { name = "name" }, { name = "subName" } },
  Item = { { name = "name" } },
  Object = { { name = "name" } },
}

--------------------------------------------------------------------------------------------
-- Block loading
--------------------------------------------------------------------------------------------

-- Providers close over this variable, not a block snapshot. Locale replacement can therefore
-- release the old blocks after entity-cache invalidation.
local activeBlocks = {}
local availableTypes = {}

---@param key string
---@return string? value
local function readStored(key)
  local baked = LibQuestieDB.read and LibQuestieDB.read.baked
  if not baked then return nil end
  return baked.getStored(key)
end

---@param encoded string Base64 zlib CBOR.
---@return table block
local function decodeBlock(encoded)
  return Encoding.DeserializeCBOR(
    Encoding.DecompressString(Encoding.DecodeBase64(encoded), 1))
end

---Decode every selected entity type for one configured locale.
---The caller does not publish the result until this function completes.
---@param locale string
---@return table<string, table> blocks
local function loadLocaleBlocks(locale)
  local blocks = {}
  if not overlay.available or not overlay.localeIndex[locale] then return blocks end

  -- Decode into a temporary table first. A corrupt or incomplete locale must leave the
  -- currently active blocks and entity caches untouched.
  for _, entityType in ipairs(config.entityTypes) do
    local typeName = entityType.name
    if availableTypes[typeName] then
      local key = config.l10nBlockKey(typeName, locale)
      local encoded = readStored(key)
      if not encoded then error("QuestieTDB: missing localization block " .. key, 0) end
      local block = decodeBlock(encoded)
      if type(block) ~= "table" then
        error("QuestieTDB: localization block " .. key .. " did not decode to a table", 0)
      end
      blocks[typeName] = block
    end
  end
  return blocks
end

--------------------------------------------------------------------------------------------
-- Provider
--------------------------------------------------------------------------------------------

---Build one entity type's provider over the replaceable active block table.
---@param meta table Entity metadata.
---@param entity table Entity global owning the backend ID list.
---@return function? provider `(id, fieldIndex) -> translated | nil`.
---@return table<number, boolean>? scalarFields Translatable scalar field indices.
---@return function? isActive Whether a decoded locale is active.
function overlay.CreateProvider(meta, entity)
  local typeName = meta.entity
  local typeFields = overlay.fields[typeName]
  if not typeFields or not availableTypes[typeName] then return nil end

  local columnByEntityField = {}
  local scalarFields = {}
  for columnIndex, fieldConfig in ipairs(typeFields) do
    local entityFieldIndex = meta.keys[fieldConfig.name]
    if entityFieldIndex then
      columnByEntityField[entityFieldIndex] = columnIndex
      if not fieldConfig.list then scalarFields[entityFieldIndex] = true end
    end
  end

  local baseIds = entity.backend.getAllIds()
  local lastId, lastPosition

  ---Resolve a base entity ID to the column position Generation used.
  ---Name/subname pairs reuse the same ID, and initialization sweeps advance in ID order;
  ---random reads fall back to binary search. Composed-only IDs deliberately have no position.
  ---@param id number
  ---@return integer? position
  local function findPosition(id)
    if id == lastId then return lastPosition end

    local position
    if lastPosition and baseIds[lastPosition + 1] == id then
      position = lastPosition + 1
    else
      local low, high = 1, #baseIds
      while low <= high do
        local middle = math.floor((low + high) / 2)
        local found = baseIds[middle]
        if found == id then
          position = middle
          break
        elseif found < id then
          low = middle + 1
        else
          high = middle - 1
        end
      end
    end

    lastId, lastPosition = id, position
    return position
  end

  ---Read one translation from the current block, or nil for base-data fallback.
  ---@param id number
  ---@param entityFieldIndex integer
  ---@return any value
  local function provider(id, entityFieldIndex)
    local block = activeBlocks[typeName]
    if not block then return nil end
    local column = block[columnByEntityField[entityFieldIndex]]
    if not column then return nil end
    local position = findPosition(id)
    return position and column[position] or nil
  end

  return provider, scalarFields, function() return activeBlocks[typeName] ~= nil end
end

--------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------

---Attach providers and load the client's active locale.
---enUS reads only the format header; non-empty base ID headers identify the types a filtered
---artifact selected, so a missing locale block remains corruption rather than disabling a type.
function overlay.Initialize()
  overlay.available = readStored(config.l10nHeaderKey) == tostring(config.l10nVersion)
  availableTypes = {}

  if overlay.available then
    -- Type-filtered artifacts already publish empty base ID headers for omitted types. Use
    -- those headers as the source of truth so enUS never probes another locale's block data.
    for _, entityType in ipairs(config.entityTypes) do
      local entity = LibQuestieDB[entityType.name]
      local ids = entity and entity.backend.getAllIds()
      availableTypes[entityType.name] = ids ~= nil and #ids > 0
    end
  end

  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    local meta = LibQuestieDB.Meta[entityType.name]
    if entity and meta and entity.SetL10nProvider then
      local provider, scalarFields, isActive = overlay.CreateProvider(meta, entity)
      entity.SetL10nProvider(provider, scalarFields, isActive)
    end
  end

  overlay.SetLocale(overlay.DetectLocale())
end

---The client's UI locale, or enUS when no client function is present.
function overlay.DetectLocale()
  local getLocale = rawget(_G, "GetLocale")
  if type(getLocale) == "function" then return getLocale() end
  return "enUS"
end

---Select a locale atomically; selecting the current locale is a no-op.
---Replacement blocks finish decoding before the old blocks or entity caches are changed.
---@param locale string?
---@return string activeLocale
function overlay.SetLocale(locale)
  locale = locale or "enUS"
  if locale == overlay.currentLocale then return locale end

  local nextBlocks = loadLocaleBlocks(locale)
  activeBlocks = nextBlocks
  overlay.currentLocale = locale
  overlay.currentIndex = overlay.localeIndex[locale]

  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    if entity then entity.InvalidateCache(nil) end
  end

  for _, callback in ipairs(overlay.onLocaleChanged) do callback(locale) end
  return locale
end

---Report whether the artifact declares the supported localization-block format.
---@return boolean available
function overlay.IsAvailable()
  return overlay.available
end

LibQuestieDB.l10n = overlay

return overlay
