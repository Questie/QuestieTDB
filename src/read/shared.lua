-- src/read/shared.lua
--
-- Everything the two read modes have in common: named getters, the generic getter, the
-- Decoded field cache, Correction Overlay lookup, field defaults, and freezing.
--
-- Only two functions differ between Source mode and Baked mode — `readField` and `getAllIds` —
-- so the seam stays two functions wide and this file is written once. Source mode and
-- Generation apply Static Corrections through the same path, so "what I see in dev is what
-- ships" follows from shared code rather than from a test.

local _, LibQuestieDB = ...

local shared = {}

local type, rawget, setmetatable, ipairs = type, rawget, setmetatable, ipairs

--------------------------------------------------------------------------------------------
-- Freezing
--------------------------------------------------------------------------------------------
--
-- `table.freeze` is a VM-level flag, not a metatable proxy: reads are completely unaffected,
-- `rawset` is blocked, and `getmetatable` still returns nil. It does not exist in standard
-- Lua 5.1, which is what the generator, verify.lua and the offline harness run on, so
-- capability detection is mandatory and the harness installs a pure-Lua substitute.
--
-- No frozen table may carry `__newindex`: a frozen table *with* one redirects writes to the
-- metamethod instead of failing, which is exactly the trap the prototypes' `EMPTY` sentinel
-- fell into.

local luaTable = rawget(_G, "table")
local freeze = luaTable and rawget(luaTable, "freeze")
local isFrozen = luaTable and rawget(luaTable, "isfrozen")

shared.canFreeze = freeze ~= nil

--- Deep-freeze a value the database owns. Measured on Classic Era 1.15.9 at 0 KiB allocated
--- against CopyTable's ~357 KiB, and 8-20% faster — see docs/table.freeze.md.
---
--- Re-freezing must be harmless: a table field is frozen when the base data loads and again
--- when a read caches it, and the Correction Overlay produces fresh objects on every
--- recomposition.
function shared.Freeze(value)
  if not freeze or type(value) ~= "table" then return value end
  if isFrozen and isFrozen(value) then return value end
  for _, inner in pairs(value) do
    if type(inner) == "table" then shared.Freeze(inner) end
  end
  return freeze(value)
end

--- Install a freeze implementation. Used by the offline harness to make the guard present in
--- CI rather than silently absent — see emulator/freeze.lua.
function shared.SetFreezeImplementation(implementation)
  freeze = implementation
  shared.canFreeze = implementation ~= nil
end

function shared.SetIsFrozenImplementation(implementation)
  isFrozen = implementation
end

function shared.IsFrozen(value)
  if not isFrozen then return false end
  return isFrozen(value) == true
end

--------------------------------------------------------------------------------------------
-- Entity access
--------------------------------------------------------------------------------------------

local NIL = setmetatable({}, { __tostring = function() return "<nil>" end })

--- Build one Entity global over a backend.
---
---@param meta table Entity meta from src/meta/<entity>Meta.lua
---@param backend table { readField(id, fieldIndex) -> value|nil, getAllIds() -> list, map }
---@return table entity
function shared.CreateEntity(meta, backend)
  local normalize = LibQuestieDB.Meta.normalize
  local types = meta.types
  local keys = meta.keys
  local fieldCount = meta.fieldCount

  local entity = {
    meta = meta,
    backend = backend,
  }

  -- Decoded field cache. Scalars are cached unconditionally in both modes because strings and
  -- numbers are immutable and carry no hazard; table fields are cached *and* frozen.
  local cache = {}

  -- Correction Overlay: the composed query-time layer of Dynamic Corrections. Reads resolve
  -- through it first and fall back to base data. Recomposed on apply rather than resolved at
  -- read time, so this stays a single lookup. Populated by src/corrections/registry.lua.
  local overlay = {}
  entity.overlay = overlay

  --- Swap in a freshly composed overlay and drop every cached value, because any of them could
  --- have been decided by the layer being replaced.
  function entity.SetOverlay(composed)
    overlay = composed or {}
    entity.overlay = overlay
    entity.InvalidateCache(nil)
  end

  local function readRaw(id, fieldIndex)
    local layer = overlay[id]
    if layer ~= nil then
      local value = layer[fieldIndex]
      if value ~= nil then
        -- The registry's sentinel for "this Correction sets the field to nil", which a plain
        -- nil in the overlay table cannot express.
        if value == LibQuestieDB.Corrections.NIL then return nil end
        return value
      end
    end
    return backend.readField(id, fieldIndex)
  end

  -- The l10n overlay, when localization data is present. Set by src/l10n/overlay.lua after the
  -- Entity globals exist. nil means "no localization data", and the check below costs nothing.
  local l10nProvider

  function entity.SetL10nProvider(provider)
    l10nProvider = provider
    entity.InvalidateCache(nil)
  end

  function entity.HasL10nProvider()
    return l10nProvider ~= nil
  end

  local function get(id, fieldIndex)
    local byId = cache[id]
    if byId then
      local cached = byId[fieldIndex]
      if cached ~= nil then
        if cached == NIL then return nil end
        return cached
      end
    else
      byId = {}
      cache[id] = byId
    end

    local value = readRaw(id, fieldIndex)

    -- Localization sits above the Correction Overlay and below the cache: a translated value
    -- is cached like any other, and a locale change drops the cache rather than re-reading.
    -- A field with no translation falls back to the base entity value.
    if l10nProvider then
      local translated = l10nProvider(id, fieldIndex)
      if translated ~= nil then value = translated end
    end

    -- Numeric getters default to 0, never nil. An absent value means the field was nil at
    -- source, and Questie returns 0 there. 0 is truthy in Lua, so consumers already test
    -- `~= 0`; returning nil instead would change behaviour at ~290 call sites.
    if value == nil then
      if types[fieldIndex] == "number" then
        byId[fieldIndex] = 0
        return 0
      end
      byId[fieldIndex] = NIL
      return nil
    end

    if type(value) == "table" then
      value = shared.Freeze(value)
    end
    byId[fieldIndex] = value
    return value
  end

  entity.GetByIndex = get

  --- Field access by canonical name or positional index.
  function entity.Get(id, key)
    local fieldIndex = keys[key] or (type(key) == "number" and key or nil)
    if not fieldIndex or fieldIndex < 1 or fieldIndex > fieldCount then return nil end
    return get(id, fieldIndex)
  end

  --- Bulk field access. Returns values in the order the keys were requested.
  function entity.GetAll(id, requestedKeys)
    local values = {}
    for i = 1, #requestedKeys do
      values[i] = entity.Get(id, requestedKeys[i])
    end
    return values
  end

  --- Base data only, bypassing the Correction Overlay. For tooling and debugging.
  function entity.GetRaw(id, key)
    local fieldIndex = keys[key] or (type(key) == "number" and key or nil)
    if not fieldIndex then return nil end
    local value = backend.readField(id, fieldIndex)
    if value == nil and types[fieldIndex] == "number" then return 0 end
    return value
  end

  function entity.GetAllIds(hashmap)
    local list, map = backend.getAllIds()
    if hashmap == true then return map end
    return list
  end

  function entity.Exists(id)
    local _, map = backend.getAllIds()
    return map[id] == true
  end

  --- Drop cached values so the next read recomposes. Called when the overlay changes, and
  --- available to a consumer that registers Corrections late.
  ---
  --- `get` closes over `cache`, so it is cleared in place rather than rebound.
  function entity.InvalidateCache(id)
    if id == nil then
      for key in pairs(cache) do cache[key] = nil end
      return
    end
    cache[id] = nil
  end

  -- Named getters, generated from the schema. `QuestDB.name(2)` reads field 1 of quest 2.
  for fieldIndex = 1, fieldCount do
    local name = meta.names[fieldIndex]
    if name then
      entity[name] = function(id) return get(id, fieldIndex) end
    end
  end

  return entity
end

if LibQuestieDB then
  LibQuestieDB.shared = shared
end

return shared
