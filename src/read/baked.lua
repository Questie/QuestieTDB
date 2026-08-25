-- src/read/baked.lua
--
-- Baked mode: entity reads resolve from the TOC metadata store.
--
-- This file and src/read/source.lua are the only two places the modes diverge. Both provide
-- exactly `readField(id, fieldIndex)` and `getAllIds()`; everything above them —
-- named getters, the generic getter, the Decoded field cache, Correction Overlay lookup,
-- field defaults, freezing, the l10n overlay — is written once in src/read/shared.lua.

local ADDON_NAME, LibQuestieDB = ...

local codec = LibQuestieDB.Meta.codec
local concat = table.concat

local baked = {}

-- `C_AddOns.GetAddOnMetadata` in a live client; the offline harness installs a stand-in with
-- the same signature. See emulator/metadata.lua.
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

--- Read one stored value, reassembling a Chunked metadata value transparently so callers
--- never see chunk markers.
local function getStored(key)
  local value = GetAddOnMetadata(ADDON_NAME, key)
  if not value then return nil end

  local parts = codec.chunkCount[value]
  if not parts then return value end

  local buffer = {}
  for i = 1, parts do
    local part = GetAddOnMetadata(ADDON_NAME, key .. "-" .. i)
    if not part then
      -- A truncated chunk set is corruption, not a missing value. Say so rather than
      -- silently returning a short string.
      error(("QuestieTDB: metadata key %s declares %d parts but part %d is missing")
        :format(key, parts, i), 0)
    end
    buffer[i] = part
  end
  return concat(buffer)
end

baked.getStored = getStored

--- Build the Baked-mode backend for one entity type.
---@param meta table Entity meta from src/meta/<entity>Meta.lua
---@return table backend
function baked.CreateBackend(meta)
  local prefix = "X-" .. meta.metaPrefix
  local decoders = {}
  for fieldIndex = 1, meta.fieldCount do
    decoders[fieldIndex] = codec.decoders[meta.types[fieldIndex]]
  end

  local idList, idMap

  local backend = { mode = "baked" }

  function backend.readField(id, fieldIndex)
    local decoder = decoders[fieldIndex]
    if not decoder then return nil end
    local stored = getStored(prefix .. id .. "-" .. fieldIndex)
    if stored == nil then return nil end
    return decoder(stored)
  end

  --- Compile the stored literal for a table field directly, skipping the decode: the shared
  --- getter caches this producer and executes it per read (ADR 0003 D10). Baked mode already
  --- holds the serialized text, so no decode-then-reserialize round trip is ever paid.
  function backend.tableChunk(id, fieldIndex)
    local stored = getStored(prefix .. id .. "-" .. fieldIndex)
    if stored == nil then return nil end
    return codec.compileTable(stored)
  end

  function backend.getAllIds()
    if not idList then
      local stored = getStored(prefix .. "IDS-LIST")
      idList = codec.decodeIdList(stored)
      idMap = codec.decodeIdMap(stored)
    end
    return idList, idMap
  end

  return backend
end

-- The artifact names its own flavor, so the correction block that loads after this file knows
-- which expansion's Dynamic Corrections apply without asking the client.
local flavorName = GetAddOnMetadata(ADDON_NAME, "X-Flavor")
LibQuestieDB.flavor = flavorName and LibQuestieDB.config.flavorByName[flavorName] or nil

LibQuestieDB.read = LibQuestieDB.read or {}
LibQuestieDB.read.baked = baked
LibQuestieDB.mode = "baked"

return baked
