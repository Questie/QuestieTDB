-- src/l10n/overlay.lua
--
-- The optional localization layer wrapping selected Named getters for the active locale.
--
-- Locale-joined values live in the TOC metadata store alongside entity data. Because segments
-- are only extracted on access, a German user never touches the other eight locales' strings
-- and they never cost Lua memory or GC pressure — which is what makes keeping all nine locales
-- in one store the right call rather than splitting l10n into its own addon.
--
-- Changing locale at runtime takes effect without regeneration and without a database rebuild.
-- That is what removes Questie's `dbCompiledLang` recompile trigger, where `l10n:Initialize()`
-- wrote translated strings into `questData` *before* compile and a locale change forced the
-- whole database to be rebuilt.
--
-- With no localization data present — Source mode, or a Baked artifact generated with
-- `--no-l10n` — every getter behaves exactly as if this file were absent.

local _, LibQuestieDB = ...

local overlay = {}

local config = LibQuestieDB.config
local codec = LibQuestieDB.Meta.codec

--------------------------------------------------------------------------------------------
-- Locale
--------------------------------------------------------------------------------------------

overlay.locales = config.locales
overlay.separator = config.localeSeparator

overlay.localeIndex = {}
for index, locale in ipairs(config.locales) do overlay.localeIndex[locale] = index end

--- enUS is the base data's own language and is deliberately not stored, so it is "no overlay".
overlay.currentLocale = "enUS"
overlay.currentIndex = nil

overlay.onLocaleChanged = {}

--------------------------------------------------------------------------------------------
-- Field coverage
--------------------------------------------------------------------------------------------
--
-- Compact l10n field indices, matching what the generator emits. Field coverage matches what
-- Questie translates today, and no more.

overlay.fields = {
  Quest = { { name = "name" }, { name = "objectivesText", list = true } },
  Npc = { { name = "name" }, { name = "subName" } },
  Item = { { name = "name" } },
  Object = { { name = "name" } },
}

--------------------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------------------

local function readStored(key)
  local baked = LibQuestieDB.read and LibQuestieDB.read.baked
  if not baked then return nil end
  return baked.getStored(key)
end

--- Build a provider for one entity type: `(id, entityFieldIndex) -> translated | nil`.
---
--- Returns nil when there is no localization data for the type at all, so the shared getter
--- can skip the check entirely rather than paying for a lookup per read.
function overlay.CreateProvider(meta)
  local typeFields = overlay.fields[meta.entity]
  if not typeFields then return nil end

  local prefix = "X-" .. config.l10nMetaPrefix .. meta.entity .. "-"
  if readStored(prefix .. "IDS-LIST") == nil then return nil end

  -- entity field index -> { l10nFieldIndex, list }
  local byEntityField = {}
  for l10nIndex, fieldCfg in ipairs(typeFields) do
    local entityIndex = meta.keys[fieldCfg.name]
    if entityIndex then
      byEntityField[entityIndex] = { index = l10nIndex, list = fieldCfg.list }
    end
  end

  return function(id, entityFieldIndex)
    local localeIndex = overlay.currentIndex
    if not localeIndex then return nil end

    local mapping = byEntityField[entityFieldIndex]
    if not mapping then return nil end

    local stored = readStored(prefix .. id .. "-" .. mapping.index)
    if stored == nil then return nil end

    local segment = codec.localeSegment(stored, localeIndex, overlay.separator)
    if segment == nil then return nil end

    if mapping.list then
      -- A list-typed field's segment is a Lua table literal, serialized by the generator with
      -- the same serializer entity fields use, so the translated value keeps the field's TYPE
      -- (a table, never a joined string). Element counts follow the upstream lookup's own
      -- shape and may legitimately differ from base — zhCN/zhTW combine multiple objectives
      -- into one string (1,486 Vanilla reads; equivalence counts them as "locale-shaped").
      -- The shared getter wraps the decoded table in a fresh-per-read producer as usual.
      return codec.decodeTable(segment)
    end

    return segment
  end
end

--------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------

--- Attach providers to every Entity global. Called once at load.
function overlay.Initialize()
  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    local meta = LibQuestieDB.Meta[entityType.name]
    if entity and meta and entity.SetL10nProvider then
      entity.SetL10nProvider(overlay.CreateProvider(meta))
    end
  end
  overlay.SetLocale(overlay.DetectLocale())
end

--- The client's UI locale, or enUS when there is no client.
function overlay.DetectLocale()
  local getLocale = rawget(_G, "GetLocale")
  if type(getLocale) == "function" then return getLocale() end
  return "enUS"
end

--- Changing locale takes effect immediately: the cached values that were decided by the old
--- locale are dropped, and the next read decodes a different segment of the same stored value.
--- Nothing is regenerated and nothing is rebuilt.
function overlay.SetLocale(locale)
  overlay.currentLocale = locale or "enUS"
  overlay.currentIndex = overlay.localeIndex[overlay.currentLocale]

  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    if entity then entity.InvalidateCache(nil) end
  end

  for _, callback in ipairs(overlay.onLocaleChanged) do callback(overlay.currentLocale) end
  return overlay.currentLocale
end

--- Whether any localization data is present at all.
function overlay.IsAvailable()
  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    if entity and entity.HasL10nProvider and entity.HasL10nProvider() then return true end
  end
  return false
end

LibQuestieDB.l10n = overlay

return overlay
