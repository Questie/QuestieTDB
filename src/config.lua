-- src/config.lua
--
-- Shared configuration for the QuestieTDB addon and its offline generator.
--
-- This file is dual-mode: the WoW client loads it as an addon file (where `...` is
-- `addonName, addonTable`), and the offline tooling loads it with `dofile` (where `...` is
-- empty and the return value is used). Every file under src/ that the generator also needs
-- follows this pattern.

local _, LibQuestieDB = ...

local config = {}

config.addonName = "QuestieTDB"

--- Bumped when the shape of the public API or the storage format changes in a way a consumer
--- can observe. Questie checks this at init and fails with a specific message on mismatch.
config.contractVersion = 1

--- Values longer than this many bytes are stored as a Chunked metadata value.
--- See docs/storage-format.md.
config.maxValueLength = 1000

--------------------------------------------------------------------------------------------
-- Client flavors
--------------------------------------------------------------------------------------------
--
-- `suffix` is the modern underscore TOC suffix. The client searches for flavour-suffixed TOCs
-- first and falls back to the base `QuestieTDB.toc` only if none are found, which is what
-- selects Baked mode over Source mode at no cost.
--
-- `expansion` is the directory under data/ holding this flavor's raw entity data.
-- `dataPrefix` is the filename prefix inside that directory.
-- `interface` is the `## Interface:` value, taken from Questie's own per-flavor TOCs.

config.flavors = {
  { name = "Vanilla", suffix = "_Vanilla", expansion = "Classic", dataPrefix = "classic", interface = "11508, 11509" },
  { name = "TBC",     suffix = "_TBC",     expansion = "TBC",     dataPrefix = "tbc",     interface = "20506" },
  { name = "Wrath",   suffix = "_Wrath",   expansion = "Wotlk",   dataPrefix = "wotlk",   interface = "38000, 38001" },
  { name = "Cata",    suffix = "_Cata",    expansion = "Cata",    dataPrefix = "cata",    interface = "40402" },
  { name = "Mists",   suffix = "_Mists",   expansion = "MoP",     dataPrefix = "mop",     interface = "50503, 50504" },
}

config.flavorByName = {}
for _, flavor in ipairs(config.flavors) do
  config.flavorByName[flavor.name] = flavor
end

--------------------------------------------------------------------------------------------
-- Entity types
--------------------------------------------------------------------------------------------
--
-- `name` is the Entity global's base name — `Quest` becomes `LibQuestieDB.Quest` and the
-- `QuestDB` global alias.
-- `keysField` / `dataField` / `typesField` are the names Questie's data and schema files use.
-- `metaPrefix` is the per-type key prefix inside the combined TOC metadata store; see
-- docs/storage-format.md, "Combined-addon prefix".

config.entityTypes = {
  { name = "Quest",  keysField = "questKeys",  dataField = "questData",  typesField = "questCompilerTypes",  metaPrefix = "Quest-",  fileSuffix = "QuestDB" },
  { name = "Npc",    keysField = "npcKeys",    dataField = "npcData",    typesField = "npcCompilerTypes",    metaPrefix = "Npc-",    fileSuffix = "NpcDB" },
  { name = "Item",   keysField = "itemKeys",   dataField = "itemData",   typesField = "itemCompilerTypes",   metaPrefix = "Item-",   fileSuffix = "ItemDB" },
  { name = "Object", keysField = "objectKeys", dataField = "objectData", typesField = "objectCompilerTypes", metaPrefix = "Object-", fileSuffix = "ObjectDB" },
}

config.entityTypeByName = {}
for _, entityType in ipairs(config.entityTypes) do
  config.entityTypeByName[entityType.name] = entityType
end

--------------------------------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------------------------------
--
-- enUS is deliberately absent: base entity data is already English, so the l10n store carries
-- only translations. Order is fixed and load-bearing — the decoder captures the Nth segment.

config.locales = { "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

config.localeSeparator = "\226\128\161" -- U+2021 DOUBLE DAGGER

--- l10n metadata keys are prefixed to keep them out of the entity key space. Without this,
--- `X-Quest-2-1` would be ambiguous between quest 2's name and Quest l10n id 2 field 1.
config.l10nMetaPrefix = "l10n-"

--------------------------------------------------------------------------------------------
-- Addon file lists
--------------------------------------------------------------------------------------------
--
-- `src/read/` is the only place the two modes diverge, so the two lists differ by one file
-- plus, for Source mode, the raw entity data.

config.runtimeFiles = {
  shared = {
    "src/config.lua",
    "src/meta/normalize.lua",
    "src/meta/codec.lua",
    "src/meta/questMeta.lua",
    "src/meta/npcMeta.lua",
    "src/meta/itemMeta.lua",
    "src/meta/objectMeta.lua",
  },
  bakedReader = "src/read/baked.lua",
  sourceReader = "src/read/source.lua",
  tail = {
    "src/read/shared.lua",
    "src/corrections/registry.lua",
    "src/l10n/overlay.lua",
    "src/api.lua",
  },
}

--------------------------------------------------------------------------------------------
-- Paths (offline generation only)
--------------------------------------------------------------------------------------------

config.paths = {
  data = "data",
  support = "support",
  meta = "src/meta",
  l10n = "l10n",
}

--- Raw entity data file for one flavor and entity type, relative to the repo root.
function config.dataPath(flavor, entityType)
  return config.paths.data .. "/" .. flavor.expansion .. "/" .. flavor.dataPrefix .. entityType.fileSuffix .. ".lua"
end

--- Generated TOC filename for one flavor.
function config.tocPath(flavor)
  return config.addonName .. flavor.suffix .. ".toc"
end

if LibQuestieDB then
  LibQuestieDB.config = config
end

return config
