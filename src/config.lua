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
config.contractVersion = 3

--- The oldest consumer contract this release still honors. `RequireContract` passes any
--- required version in [minSupportedContract, contractVersion]; raise this floor only when a
--- breaking change genuinely abandons older consumers (ADR 0003 D12).
config.minSupportedContract = 1

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
-- only translations. Keep this order stable so generated blocks remain byte-identical.

config.locales = { "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

config.l10nVersion = 1
config.l10nHeaderKey = "X-l10n-Version"
config.l10nMetaPrefix = "l10n-"

---Storage key for one locale and entity type's compressed localization columns.
---@param typeName string
---@param locale string
---@return string key
function config.l10nBlockKey(typeName, locale)
  -- A key ending in `-deDE` is interpreted as a localized TOC directive and disappears on an
  -- enUS client. Keep the entity type last so every locale's block remains directly addressable.
  return "X-" .. config.l10nMetaPrefix .. locale .. "-" .. typeName
end

--------------------------------------------------------------------------------------------
-- Addon file lists
--------------------------------------------------------------------------------------------
--
-- `src/read/` is the only place the two modes diverge, so the two lists differ by one file
-- plus, for Source mode, the raw entity data.

config.runtimeFiles = {
  head = {
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
    "src/l10n/overlay.lua",
    "src/ui/modeIndicator.lua",
    "src/api.lua",
  },
}

--- The raw entity data block, only present in the base TOC. Each expansion's files are
--- preceded by a marker naming it, so the loader shim in src/read/source.lua can discard the
--- four expansions the running client does not need; `_end.lua` closes the block.
function config.sourceDataFiles()
  local files = {}
  for _, flavor in ipairs(config.flavors) do
    files[#files + 1] = config.paths.data .. "/" .. flavor.expansion .. "/_flavor.lua"
    for _, entityType in ipairs(config.entityTypes) do
      files[#files + 1] = config.dataPath(flavor, entityType)
    end
  end
  files[#files + 1] = config.paths.data .. "/_end.lua"
  return files
end

--- The correction block, bracketed by the files that install and remove the compat shim.
---
--- `mode` selects what ships. Baked artifacts carry only files that provide a **Dynamic**
--- function, because Static Corrections are already folded into the metadata store and their
--- files are build-time input that never reaches a user. A file providing both — Questie's
--- `classicQuestFixes.lua` has `Load` (static) beside `LoadFactionFixes` (dynamic) — ships,
--- because the two live in one upstream file and splitting them would fork it.
---@param flavor table? Restrict to one flavor's expansions
---@param mode string "source" | "baked"
function config.correctionFiles(flavor, mode)
  local manifest = config.correctionManifest
  if not manifest then return {} end

  local expansionOrder = { Classic = 1, TBC = 2, Wotlk = 3, Cata = 4, MoP = 5 }
  local files = { "src/corrections/enum/constants.lua", "src/corrections/compat.lua",
                  "src/corrections/_begin.lua" }
  local body = {}

  for _, spec in ipairs(manifest) do
    local include = true
    if flavor then
      if spec.expansions and not spec.expansions[flavor.expansion] then include = false end
      if spec.minExpansionOrder and (expansionOrder[flavor.expansion] or 0) < spec.minExpansionOrder then
        include = false
      end
    end
    if mode == "baked" and not (spec.dynamic and #spec.dynamic > 0) then include = false end
    if include then body[#body + 1] = "src/corrections/" .. spec.file end
  end

  if #body == 0 then return {} end
  for _, file in ipairs(body) do files[#files + 1] = file end
  files[#files + 1] = "src/corrections/manifest.lua"
  files[#files + 1] = "src/corrections/register.lua"
  files[#files + 1] = "src/corrections/_end.lua"
  return files
end

--- The derived-pass block, bracketed by the files that install and remove its loader shim.
---
--- Source mode only. Baked artifacts never list these files: Generation already applied every
--- pass before encoding, exactly as it already folded in Static Corrections, so a baked client
--- would be re-running a transform over data that has had it (ADR 0004 D3).
config.derivedFiles = {
  "src/derived/registry.lua",
  "src/derived/_begin.lua",
  "src/derived/RamerDouglasPeucker.lua",
  "src/derived/requiredRaces.lua",
  "src/derived/waypoints.lua",
  "src/derived/_end.lua",
}

--------------------------------------------------------------------------------------------
-- Support data
--------------------------------------------------------------------------------------------
--
-- Per-flavor selection happens here and nowhere else: every flavor lists a different variant
-- and all of them assign to the same module field, so there is no runtime selection to get
-- wrong. Taken from Questie's own per-flavor TOCs rather than guessed.

config.supportData = {
  shared = {
    "support/Zones/dungeons.lua",
    "support/Zones/subZoneToParentZone.lua",
    "support/Zones/zoneIds.lua",
    "support/Zones/instanceIdToAreaId.lua",
    "support/DropTables/itemDropCorrections.lua",
  },
  perFlavor = {
    Vanilla = {
      "support/Zones/areaIdToUiMapId.lua", "support/Zones/uiMapIdToAreaId.lua",
      "support/QuestXP/xpDB-classic.lua", "support/FactionTemplates/factionTemplateClassic.lua",
      "support/DropTables/classicItemDrops.lua",
    },
    TBC = {
      "support/Zones/areaIdToUiMapId.lua", "support/Zones/uiMapIdToAreaId.lua",
      "support/QuestXP/xpDB-tbc.lua", "support/FactionTemplates/factionTemplateTBC.lua",
      "support/DropTables/tbcItemDrops.lua",
    },
    Wrath = {
      "support/Zones/areaIdToUiMapId.lua", "support/Zones/uiMapIdToAreaId.lua",
      "support/QuestXP/xpDB-wotlk.lua", "support/FactionTemplates/factionTemplateWotlk.lua",
      "support/DropTables/wotlkItemDrops.lua",
    },
    Cata = {
      "support/Zones/areaIdToUiMapId.lua", "support/Zones/uiMapIdToAreaId.lua",
      "support/QuestXP/xpDB-cata.lua", "support/FactionTemplates/factionTemplateCata.lua",
      "support/DropTables/cataItemDrops.lua",
    },
    -- Mists uses its own zone maps, and loads Cata's drop table alongside its own, exactly as
    -- Questie-Mists.toc does.
    Mists = {
      "support/Zones/MoP/areaIdToUiMapId.lua", "support/Zones/MoP/uiMapIdToAreaId.lua",
      "support/QuestXP/xpDB-mop.lua", "support/FactionTemplates/factionTemplateMoP.lua",
      "support/DropTables/mopItemDrops.lua", "support/DropTables/cataItemDrops.lua",
    },
  },
}

--- The support-data block for one flavor, bracketed by the shim install and removal.
--- With no flavor — the base TOC — every variant is listed; later assignments to the same
--- module field win, which is why Source mode still needs the flavor to pick correctly.
function config.supportFiles(flavor)
  -- The extracted constants come first: the support shim seeds `DropDB.correctionKeys` from
  -- them before `itemDropCorrections.lua` runs.
  local files = { "src/corrections/enum/constants.lua", "src/support/data.lua",
                  "src/support/_begin.lua" }
  for _, file in ipairs(config.supportData.shared) do files[#files + 1] = file end
  if flavor then
    for _, file in ipairs(config.supportData.perFlavor[flavor.name] or {}) do
      files[#files + 1] = file
    end
  else
    -- The base TOC lists every variant, sorted so the order is stable across runs. Sorting is
    -- confined to the data files: the bracket files that install and remove the shim have to
    -- keep their positions, and sorting the whole list once moved them.
    local seen, variants = {}, {}
    for _, name in ipairs({ "Vanilla", "TBC", "Wrath", "Cata", "Mists" }) do
      for _, file in ipairs(config.supportData.perFlavor[name] or {}) do
        if not seen[file] then seen[file] = true; variants[#variants + 1] = file end
      end
    end
    table.sort(variants)
    for _, file in ipairs(variants) do files[#files + 1] = file end
  end
  files[#files + 1] = "src/support/_end.lua"
  return files
end

--- Append `source` to `target`, skipping anything already listed.
---
--- Each block declares its own prerequisites — the support block and the correction block both
--- need `enum/constants.lua`, and neither can assume the other ran. Composing here is what
--- makes that safe: the client rejects a file listed twice with
--- `Duplicate File Load Detected`, and loading a 39 KB constant table twice would be waste
--- even if it did not.
---
--- First occurrence wins, because a block's prerequisites are listed ahead of it and the
--- earliest position is the one that satisfies every later block.
local function append(target, source, seen)
  for _, file in ipairs(source) do
    if not seen[file] then
      seen[file] = true
      target[#target + 1] = file
    end
  end
  return target
end

--- Files a generated flavour TOC lists, in load order.
function config.bakedFileList(flavor)
  local files, seen = {}, {}
  append(files, config.runtimeFiles.head, seen)
  append(files, { config.runtimeFiles.bakedReader }, seen)
  append(files, config.supportFiles(flavor), seen)
  append(files, { "src/read/shared.lua", "src/corrections/registry.lua" }, seen)
  append(files, config.correctionFiles(flavor, "baked"), seen)
  append(files, config.runtimeFiles.tail, seen)
  return files
end

--- Files the committed base TOC lists, in load order. The reader has to come before the data
--- so its shim is in place when the payload assignments happen.
function config.sourceFileList()
  local files, seen = {}, {}
  append(files, config.runtimeFiles.head, seen)
  append(files, { config.runtimeFiles.sourceReader }, seen)
  append(files, config.sourceDataFiles(), seen)
  append(files, config.supportFiles(nil), seen)
  append(files, { "src/read/shared.lua", "src/corrections/registry.lua" }, seen)
  append(files, config.correctionFiles(nil, "source"), seen)
  append(files, config.derivedFiles, seen)
  append(files, config.runtimeFiles.tail, seen)
  return files
end

--- Every interface version QuestieTDB supports, for the base TOC. A single comma-separated
--- list is what lets one committed TOC load on any supported client, which is what source mode
--- needs — a fresh clone has no suffixed TOC to match.
function config.allInterfaceVersions()
  local seen, parts = {}, {}
  for _, flavor in ipairs(config.flavors) do
    for version in flavor.interface:gmatch("%d+") do
      if not seen[version] then
        seen[version] = true
        parts[#parts + 1] = version
      end
    end
  end
  return table.concat(parts, ", ")
end

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
