-- generator/schema.lua
--
-- Derives QuestieTDB's field table from Questie's schema rather than hand-maintaining a copy.
--
-- A hand-written schema is a second version of someone else's schema, and it drifts — observed,
-- not theoretical: the `Getters` prototype sits at 32 quest fields against Questie's 36, having
-- gone stale during exactly this kind of development gap. Deriving turns drift into a build
-- failure instead of a discovery months later.
--
-- Two halves of Questie's schema meet different fates:
--
--   *Keys           lives in Database/<entity>DB.lua AND duplicated inside each data file.
--                   Survives Questie's phase 13, so it keeps deriving indefinitely.
--   *CompilerTypes  lives in Database/<entity>DB.lua only. Dies with the compiler.
--
-- So the type map is *materialized* into src/meta/ and committed — a mechanism whose job is to
-- capture something before it disappears. `schema.check()` compares the committed copy against
-- a fresh derivation, which is how drift becomes a build failure.

local serialize = dofile("generator/serialize.lua")
local lib = dofile("generator/lib.lua")

local schema = {}

--------------------------------------------------------------------------------------------
-- Compiler type map
--------------------------------------------------------------------------------------------
--
-- Questie's compiler type names describe a byte stream. Most of that means nothing in a text
-- store:
--
--   * Width is dead.        u8/u16/u24/u32/s8/s16/s24 all become the same decimal text.
--   * Array width is dead.  u8u16array/u16u16array/u8u24array/u8s24array/u16u24array all
--                           become one ID array.
--   * Signedness is dead.   The stream offsets (`value - 32767`) exist only inside the
--                           encoder. Generation reads raw data pre-compile, so no offset is
--                           ever present.
--
-- Three things do not collapse: structure, nil semantics, and `faction`'s normalizer.
--
-- `storage`   is what the decoder does with the stored text: number | string | table.
-- `structure` names the shape, for validators and for documentation. It does not select a
--             serializer — one generic serializer handles every shape, see
--             generator/serialize.lua.
-- `emptyIsNil` marks table types whose "no content" form must read back as nil.
-- `zeroPairIsNil` marks the pair types, where Questie's documented hack makes {0,0} read as
--             nil.

schema.compilerTypeMap = {
  -- Numbers. Width and signedness are stream concerns only.
  u8  = { storage = "number" },
  u12 = { storage = "number" },
  u16 = { storage = "number" },
  u24 = { storage = "number" },
  u32 = { storage = "number" },
  s8  = { storage = "number" },
  s16 = { storage = "number" },
  s24 = { storage = "number" },

  -- Strings.
  u8string  = { storage = "string" },
  u16string = { storage = "string" },
  faction   = { storage = "string", normalize = "faction" },

  -- ID arrays. Five stream types, one behaviour.
  u8u16array  = { storage = "table", structure = "idarray", emptyIsNil = true },
  u8u24array  = { storage = "table", structure = "idarray", emptyIsNil = true },
  u8s24array  = { storage = "table", structure = "idarray", emptyIsNil = true },
  u16u16array = { storage = "table", structure = "idarray", emptyIsNil = true },
  u16u24array = { storage = "table", structure = "idarray", emptyIsNil = true },

  -- String arrays.
  u8u16stringarray = { storage = "table", structure = "stringarray", emptyIsNil = true },

  -- Pairs. {0,0} reads back as nil — Questie's documented hack for coordinate-style pairs.
  u12pair = { storage = "table", structure = "pair", emptyIsNil = true, zeroPairIsNil = true },
  s24pair = { storage = "table", structure = "pair", emptyIsNil = true, zeroPairIsNil = true },

  -- Lists of pairs.
  u8s24pairs = { storage = "table", structure = "pairs", emptyIsNil = true },

  -- Structured values. Each needs its own validator, not its own serializer.
  questgivers     = { storage = "table", structure = "questgivers", emptyIsNil = true },
  objectives      = { storage = "table", structure = "objectives", emptyIsNil = true },
  spawnlist       = { storage = "table", structure = "spawnlist", emptyIsNil = true },
  waypointlist    = { storage = "table", structure = "waypointlist", emptyIsNil = true },
  trigger         = { storage = "table", structure = "trigger", emptyIsNil = true },
  extraobjectives = { storage = "table", structure = "extraobjectives", emptyIsNil = true },
}

--------------------------------------------------------------------------------------------
-- Localization coverage
--------------------------------------------------------------------------------------------
--
-- Field coverage matches what Questie translates today, and no more.

schema.l10nFieldNames = {
  Quest  = { "name", "objectivesText" },
  Npc    = { "name", "subName" },
  Item   = { "name" },
  Object = { "name" },
}

--------------------------------------------------------------------------------------------
-- Field documentation
--------------------------------------------------------------------------------------------
--
-- These descriptions are emitted beside the generated Database Key Enums. Keep shape details
-- here so schema regeneration preserves the domain contract instead of leaving only storage
-- types and positional indices.

schema.fieldDescriptions = {
  Item = {
    name = "Localized item name.",
    npcDrops = "NPC IDs that can drop this item.",
    objectDrops = "Object IDs that can drop this item.",
    itemDrops = "Item IDs for containers that can contain this item.",
    startQuest = "ID of the quest started by this item.",
    questRewards = "Quest IDs that reward this item.",
    flags = "Item flag bitmask; see https://github.com/cmangos/issues/wiki/Item_template#flags",
    foodType = "Food category; see https://github.com/cmangos/issues/wiki/Item_template#foodtype",
    itemLevel = "Item level.",
    requiredLevel = "Player level required to equip or use this item.",
    ammoType = "Ammo category used by projectile items.",
    class = "Item class ID.",
    subClass = "Item subclass ID within the item class.",
    vendors = "NPC IDs for vendors that sell this item.",
    relatedQuests = "IDs of quests related to this item.",
    teachesSpell = "Spell ID taught when this item is used.",
  },
  Npc = {
    name = "Localized NPC name.",
    minLevelHealth = "Deprecated health field; known NPCs return the compatibility placeholder 0.",
    maxLevelHealth = "Deprecated health field; known NPCs return the compatibility placeholder 1.",
    minLevel = "Minimum NPC level.",
    maxLevel = "Maximum NPC level.",
    rank = "NPC rank; see https://github.com/cmangos/issues/wiki/creature_template#rank",
    spawns = "Spawn coordinates grouped by zone: {[zoneId] = {{x, y, phase?}, ...}}.",
    waypoints = "Movement paths grouped by zone: {[zoneId] = {{{x, y}, ...}, ...}}.",
    zoneID = "Best estimate of the zone where this NPC is most common.",
    questStarts = "IDs of quests started by this NPC.",
    questEnds = "IDs of quests finished at this NPC.",
    factionID = "FactionTemplate ID; see https://github.com/cmangos/issues/wiki/FactionTemplate.dbc",
    friendlyToFaction = "Player factions this NPC is friendly to: A, H, AH, or nil when hostile to both.",
    subName = "Localized NPC title or function, such as Weapon Vendor.",
    npcFlags = "Bitmask describing NPC functions such as vendor, trainer, or flight master.",
  },
  Object = {
    name = "Localized object name.",
    questStarts = "IDs of quests started by this object.",
    questEnds = "IDs of quests finished at this object.",
    spawns = "Spawn coordinates grouped by zone: {[zoneId] = {{x, y, phase?}, ...}}.",
    zoneID = "Best estimate of the zone where this object is most common.",
    factionID = "Faction restriction mask used by spawn data.",
    waypoints = "Movement paths for objects attached to transports such as ships or zeppelins.",
  },
  Quest = {
    name = "Localized quest name.",
    startedBy = "Quest starters: {npcIds?, objectIds?, itemIds?}; known quests always return a table.",
    finishedBy = "Quest finishers: {npcIds?, objectIds?}; known quests always return a table.",
    requiredLevel = "Minimum player level.",
    questLevel = "Quest level.",
    requiredRaces = "Allowed-race bitmask.",
    requiredClasses = "Allowed-class bitmask.",
    objectivesText = "Localized quest objective text lines.",
    triggerEnd = "Completion trigger: {text, spawn coordinates grouped by zone}.",
    objectives = "Six positional groups: creature, object, item, reputation, kill-credit, and spell; known quests always return a table.",
    sourceItemId = "ID of the item provided by the quest starter.",
    preQuestGroup = "IDs of grouped prerequisite quests.",
    preQuestSingle = "IDs of alternative single prerequisite quests.",
    childQuests = "IDs of quests unlocked by this quest.",
    inGroupWith = "IDs of quests in the same quest group.",
    exclusiveTo = "IDs of mutually exclusive quests.",
    zoneOrSort = "Positive AreaTable ID or negative QuestSort ID.",
    requiredSkill = "Required profession pair: {skillId, value}.",
    requiredMinRep = "Minimum reputation pair: {factionId, value}.",
    requiredMaxRep = "Maximum reputation pair: {factionId, value}.",
    requiredSourceItems = "Item IDs that are not objectives but are still needed for the quest.",
    nextQuestInChain = "Quest that makes this quest unavailable once active or completed.",
    questFlags = "Quest flag bitmask; see https://github.com/cmangos/issues/wiki/Quest_template#questflags",
    specialFlags = "Special flag bitmask: repeatable, event-gated, and monthly-reset flags.",
    parentQuest = "Quest that must be active for this quest to be available.",
    reputationReward = "Reputation rewards as {{factionId, value}, ...}.",
    breadcrumbForQuestId = "ID of the quest this optional breadcrumb leads to.",
    breadcrumbs = "IDs of breadcrumb quests that lead to this quest.",
    extraObjectives = "Hidden-objective rows: {{spawnList?, iconType, text?, objectiveIndex, references?}, ...}.",
    requiredSpell = "Spell ID the character must know.",
    requiredSpecialization = "Profession or specialization requirement ID.",
    requiredMaxLevel = "Maximum player level at which this quest is available.",
    availableUntilCompleted = "Quest that must remain uncompleted for this quest to stay available.",
    availableStartingWith = "Quest that must be active or completed for this quest to become available.",
    requiredRanks = "Alternative profession rank requirements as {{skillId, value}, ...}.",
    disabledByQuest = "Quest that temporarily disables this quest while active.",
  },
}

--------------------------------------------------------------------------------------------
-- Constant fields
--------------------------------------------------------------------------------------------
--
-- Constant fields remain in the Database Key Enum for positional compatibility, but their
-- source values are obsolete. Reads return the placeholder declared here and Generation emits
-- no per-entity metadata for them.

schema.constantFields = {
  Npc = {
    minLevelHealth = 0,
    maxLevelHealth = 1,
  },
}

--------------------------------------------------------------------------------------------
-- Derivation
--------------------------------------------------------------------------------------------

--- Build one entity type's field table from Questie's `*Keys` and `*CompilerTypes`.
---
--- An unrecognised compiler type fails the build rather than defaulting. A new Questie type is
--- a decision, not a fallback.
---@param entityType table An entry from config.entityTypes
---@param keys table fieldName -> fieldIndex
---@param compilerTypes table fieldName -> compiler type string
---@return table meta
function schema.derive(entityType, keys, compilerTypes)
  local meta = {
    entity = entityType.name,
    metaPrefix = entityType.metaPrefix,
    keys = {},
    names = {},
    types = {},
    structures = {},
    compilerTypes = {},
    emptyIsNil = {},
    zeroPairIsNil = {},
    normalize = {},
    constantValues = {},
    fieldCount = 0,
  }

  local seenIndex = {}
  for name, index in pairs(keys) do
    if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
      error(entityType.name .. ": field '" .. tostring(name) .. "' has a non-positional index " .. tostring(index), 0)
    end
    if seenIndex[index] then
      error(entityType.name .. ": field index " .. index .. " claimed by both '" ..
            seenIndex[index] .. "' and '" .. name .. "'", 0)
    end
    seenIndex[index] = name
    if index > meta.fieldCount then meta.fieldCount = index end
    meta.keys[name] = index
    meta.names[index] = name
  end

  for index = 1, meta.fieldCount do
    if not meta.names[index] then
      error(entityType.name .. ": field index " .. index .. " has no name — the key enum has a hole", 0)
    end
  end

  local fieldDescriptions = schema.fieldDescriptions[entityType.name]
  if not fieldDescriptions then
    error(entityType.name .. ": no generated field descriptions configured", 0)
  end
  for index = 1, meta.fieldCount do
    local name = meta.names[index]
    if not fieldDescriptions[name] then
      error(entityType.name .. ": field '" .. name .. "' has no generated description", 0)
    end
  end
  for name in pairs(fieldDescriptions) do
    if not meta.keys[name] then
      error(entityType.name .. ": description for unknown field '" .. name .. "'", 0)
    end
  end

  for index = 1, meta.fieldCount do
    local name = meta.names[index]
    local compilerType = compilerTypes[name]
    if not compilerType then
      error(entityType.name .. ": field '" .. name .. "' (index " .. index ..
            ") has no entry in " .. entityType.typesField, 0)
    end
    local mapping = schema.compilerTypeMap[compilerType]
    if not mapping then
      error(entityType.name .. ": unrecognised compiler type '" .. compilerType .. "' on field '" ..
            name .. "'. Add it to schema.compilerTypeMap — a new Questie type is a decision, " ..
            "not a fallback.", 0)
    end
    meta.compilerTypes[index] = compilerType
    meta.types[index] = mapping.storage
    meta.structures[index] = mapping.structure
    meta.emptyIsNil[index] = mapping.emptyIsNil or nil
    meta.zeroPairIsNil[index] = mapping.zeroPairIsNil or nil
    meta.normalize[index] = mapping.normalize
  end

  for name in pairs(compilerTypes) do
    if not meta.keys[name] then
      error(entityType.name .. ": " .. entityType.typesField .. " has '" .. name ..
            "' which is absent from " .. entityType.keysField, 0)
    end
  end

  for name, value in pairs(schema.constantFields[entityType.name] or {}) do
    local index = meta.keys[name]
    if not index then
      error(entityType.name .. ": constant field '" .. name .. "' is not in the key enum", 0)
    end
    if type(value) ~= meta.types[index] then
      error(string.format("%s: constant field '%s' expects a %s, got %s",
        entityType.name, name, tostring(meta.types[index]), type(value)), 0)
    end
    meta.constantValues[index] = value
  end

  meta.l10nFields = {}
  for _, name in ipairs(schema.l10nFieldNames[entityType.name] or {}) do
    local index = meta.keys[name]
    if not index then
      error(entityType.name .. ": localized field '" .. name .. "' is not in the key enum", 0)
    end
    meta.l10nFields[#meta.l10nFields + 1] = index
  end
  table.sort(meta.l10nFields)

  return meta
end

--- Check a data file's own copy of the key enum against the derived schema.
---
--- `questKeys` is defined inside each data file, so a *disagreement* there means the data and
--- the schema have drifted apart and generation must stop. A trailing *omission* is different
--- and legitimate: a field can be added to the canonical enum before every expansion's data
--- file is regenerated, and until then no row in that file carries the field. Two such
--- omissions exist today — `itemKeys.teachesSpell` (16) is absent from all five item data
--- files, and `objectKeys.waypoints` (7) is absent from MoP's.
---
---@return table omitted fieldName -> fieldIndex present in the schema but not in the data file
function schema.checkKeys(meta, keys, where)
  for name, index in pairs(keys) do
    if meta.keys[name] == nil then
      error(string.format("%s: key enum drift in %s — '%s' (index %s) is not in the derived schema. " ..
        "Re-run `lua generate.lua meta` against a current Questie checkout.",
        meta.entity, where, name, tostring(index)), 0)
    end
    if meta.keys[name] ~= index then
      error(string.format("%s: key enum drift in %s — '%s' is %s there and %s in the derived schema",
        meta.entity, where, name, tostring(index), tostring(meta.keys[name])), 0)
    end
  end

  local omitted = {}
  for name, index in pairs(meta.keys) do
    if keys[name] == nil then omitted[name] = index end
  end
  return omitted
end

--- Fail if any row carries data in a field the data file's key enum never declared. This is
--- what makes a trailing omission safe to tolerate rather than merely tolerated.
function schema.assertNoDataBeyondKeys(meta, entities, keys, where)
  local declared = 0
  for _, index in pairs(keys) do
    if index > declared then declared = index end
  end
  for id, row in pairs(entities) do
    for index in pairs(row) do
      if type(index) == "number" and index > declared then
        error(string.format("%s: %s id %s carries data at field index %d, but its key enum " ..
          "declares only %d fields", meta.entity, where, tostring(id), index, declared), 0)
      end
    end
  end
end

--------------------------------------------------------------------------------------------
-- Materialization
--------------------------------------------------------------------------------------------

local function emitIndexedTable(out, name, values, count, quoteValues)
  out[#out + 1] = "  " .. name .. " = {"
  local parts = {}
  for index = 1, count do
    local value = values[index]
    if value ~= nil then
      local encoded
      if quoteValues then
        encoded = serialize.quote(tostring(value))
      elseif value == true then
        encoded = "true"
      else
        encoded = serialize.value(value)
      end
      parts[#parts + 1] = "[" .. index .. "]=" .. encoded
    end
  end
  out[#out + 1] = table.concat(parts, ", ")
  out[#out + 1] = "  },"
end

--- Render one entity type's meta as a committable Lua source file.
function schema.render(meta)
  local out = {}
  out[#out + 1] = "-- src/meta/" .. meta.entity:lower() .. "Meta.lua"
  out[#out + 1] = "--"
  out[#out + 1] = "-- GENERATED by `lua generate.lua meta`. Do not edit by hand."
  out[#out + 1] = "--"
  out[#out + 1] = "-- Derived from Questie's " .. meta.entity:lower() .. "Keys and " ..
                  meta.entity:lower() .. "CompilerTypes. The key enum keeps deriving because"
  out[#out + 1] = "-- each data file carries its own copy; the compiler-type column is"
  out[#out + 1] = "-- materialized here because Questie's copy dies with the compiler."
  out[#out + 1] = ""
  out[#out + 1] = "local _, LibQuestieDB = ..."
  out[#out + 1] = ""
  out[#out + 1] = "local meta = {"
  out[#out + 1] = "  entity = " .. serialize.quote(meta.entity) .. ","
  out[#out + 1] = "  metaPrefix = " .. serialize.quote(meta.metaPrefix) .. ","
  out[#out + 1] = "  fieldCount = " .. meta.fieldCount .. ","
  out[#out + 1] = ""

  out[#out + 1] = "  --- fieldName -> fieldIndex. The Database Key Enum."
  out[#out + 1] = "  keys = {"
  local names = {}
  for index = 1, meta.fieldCount do names[index] = meta.names[index] end
  local keyParts = {}
  local fieldDescriptions = schema.fieldDescriptions[meta.entity]
  if not fieldDescriptions then
    error(meta.entity .. ": no generated field descriptions configured", 0)
  end
  for index = 1, meta.fieldCount do
    local fieldName = names[index]
    local description = fieldDescriptions[fieldName]
    if description then
      keyParts[#keyParts + 1] = "    -- " .. description
    end
    keyParts[#keyParts + 1] = string.format("    [%s] = %d,", serialize.quote(fieldName), index)
  end
  out[#out + 1] = table.concat(keyParts, "\n")
  out[#out + 1] = "  },"
  out[#out + 1] = ""

  out[#out + 1] = "  --- fieldIndex -> fieldName"
  emitIndexedTable(out, "names", meta.names, meta.fieldCount, true)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> storage type: number | string | table"
  emitIndexedTable(out, "types", meta.types, meta.fieldCount, true)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> structural shape, for validators. nil for scalars."
  emitIndexedTable(out, "structures", meta.structures, meta.fieldCount, true)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> Questie compiler type. Materialized provenance."
  emitIndexedTable(out, "compilerTypes", meta.compilerTypes, meta.fieldCount, true)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> true when an empty table must read back as nil"
  emitIndexedTable(out, "emptyIsNil", meta.emptyIsNil, meta.fieldCount, false)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> true when {0,0} must read back as nil"
  emitIndexedTable(out, "zeroPairIsNil", meta.zeroPairIsNil, meta.fieldCount, false)
  out[#out + 1] = ""
  out[#out + 1] = "  --- fieldIndex -> named normalizer"
  emitIndexedTable(out, "normalize", meta.normalize, meta.fieldCount, true)
  out[#out + 1] = ""
  if next(meta.constantValues) ~= nil then
    out[#out + 1] = "  --- fieldIndex -> placeholder returned without storing per-entity metadata"
    emitIndexedTable(out, "constantValues", meta.constantValues, meta.fieldCount, false)
    out[#out + 1] = ""
  end
  out[#out + 1] = "  --- field indices carrying translations"
  out[#out + 1] = "  l10nFields = " .. serialize.value(meta.l10nFields) .. ","
  out[#out + 1] = "}"
  out[#out + 1] = ""
  out[#out + 1] = "if LibQuestieDB then"
  out[#out + 1] = "  LibQuestieDB.Meta = LibQuestieDB.Meta or {}"
  out[#out + 1] = "  LibQuestieDB.Meta[" .. serialize.quote(meta.entity) .. "] = meta"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return meta"
  out[#out + 1] = ""

  return table.concat(out, "\n")
end

function schema.metaPath(entityType)
  return "src/meta/" .. entityType.name:lower() .. "Meta.lua"
end

--- Load the committed meta for one entity type.
function schema.loadMaterialized(entityType)
  local path = schema.metaPath(entityType)
  if not lib.fileExists(path) then
    error("Missing materialized schema " .. path .. " — run `lua generate.lua meta`", 0)
  end
  return dofile(path)
end

return schema
