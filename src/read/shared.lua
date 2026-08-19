-- src/read/shared.lua
--
-- Everything the two read modes have in common: named getters, the generic getter, the
-- Decoded field cache, Correction Overlay lookup, field defaults, and the fresh-per-read
-- value contract.
--
-- The seam between Source mode and Baked mode is `readField` and `getAllIds`, plus one
-- optional fast path — `tableChunk`, which Baked mode provides because it already holds the
-- serialized literal for a table field. Source mode and Generation apply Static Corrections
-- through the same path, so "what I see in dev is what ships" follows from shared code
-- rather than from a test.
--
-- ## Value ownership (ADR 0003 Decision 10, revised)
--
-- Table reads return a **fresh, mutable, deeply independent copy on every read** — the
-- caller owns it outright, exactly as Questie's compiler semantics always promised. The
-- mechanism is a cached producer: the compiled chunk (Baked) or a deep-copy closure
-- (Source and Correction Overlay values) is cached instead of a decoded table, and every
-- read executes it. Measured at 0.13–1.8 µs for typical shapes — the same class as a plain
-- cache hit. Scalars are immutable and stay cached as plain values.

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
-- Since ADR 0003 Decision 10 was revised, freezing guards **QuestieTDB-internal shared
-- structures only** — Source mode's base entity tables, which a Correction or consumer must
-- not corrupt. Values returned from reads are never frozen: they are fresh copies the caller
-- owns. The taint-ownership findings that motivated the revision (loadstring chunks are
-- owned by `*** ForceTaint_Strong ***`, so addon code can never freeze what the decoder
-- builds) are recorded in docs/client-metadata-probes.md.
--
-- Freezing still degrades rather than fails: if the VM refuses, the structure stays
-- unfrozen and the refusal is counted, because a load failing over an optional guard is
-- strictly worse than the guard being absent.

local luaTable = rawget(_G, "table")
local freeze = luaTable and rawget(luaTable, "freeze")
local isFrozen = luaTable and rawget(luaTable, "isfrozen")

shared.canFreeze = freeze ~= nil

--- How many times the VM refused to freeze a value, and the last reason. Diagnostic only —
--- consumers never see the failure, so this is the only way to know the guard is not holding.
shared.freezeRefused = 0
shared.lastFreezeError = nil

local function freezeDeep(value)
  if isFrozen and isFrozen(value) then return value end
  for _, inner in pairs(value) do
    if type(inner) == "table" then freezeDeep(inner) end
  end
  return freeze(value)
end

--- Deep-freeze a value the database owns. Measured on Classic Era 1.15.9 at 0 KiB allocated
--- against CopyTable's ~357 KiB, and 8-20% faster — see docs/table.freeze.md.
---
--- Re-freezing must be harmless: a table field is frozen when the base data loads and again
--- when a read caches it, and the Correction Overlay produces fresh objects on every
--- recomposition.
---
--- Always returns `value`, frozen if the VM allowed it and untouched if it did not.
function shared.Freeze(value)
  if not freeze or type(value) ~= "table" then return value end
  -- One pcall around the whole recursion rather than one per nested table: partial freezing
  -- is a fine outcome, and the inner loop stays free of error handling.
  local ok, err = pcall(freezeDeep, value)
  if not ok then
    shared.freezeRefused = shared.freezeRefused + 1
    shared.lastFreezeError = err
  end
  return value
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

  -- Decoded field cache. Scalars are cached as plain values — strings and numbers are
  -- immutable and carry no hazard. A table field caches a **producer function** instead of
  -- the table (ADR 0003 D10): every hit executes it and hands the caller a fresh mutable
  -- copy. A function is unambiguous in the cache because no stored value can be one.
  local cache = {}

  -- Correction Overlay: the composed query-time layer of Dynamic Corrections. Reads resolve
  -- through it first and fall back to base data. Recomposed on apply rather than resolved at
  -- read time, so this stays a single lookup. Populated by src/corrections/registry.lua.
  local overlay = {}
  entity.overlay = overlay

  -- Composed ids: the union of backend ids and overlay-added ids (ADR 0003 D7). An entity a
  -- Dynamic Correction adds is readable, enumerable, and exists — all three or none. Built
  -- lazily, dropped whenever the overlay is replaced.
  local unionList, unionMap

  local function buildUnion()
    local list, map = backend.getAllIds()
    local extra = false
    for id in pairs(overlay) do
      if map[id] ~= true then extra = true break end
    end
    if not extra then
      unionList, unionMap = list, map
      return
    end
    unionMap = {}
    for id in pairs(map) do unionMap[id] = true end
    unionList = {}
    for i = 1, #list do unionList[i] = list[i] end
    for id in pairs(overlay) do
      if unionMap[id] ~= true then
        unionMap[id] = true
        unionList[#unionList + 1] = id
      end
    end
    table.sort(unionList)
  end

  --- Swap in a freshly composed overlay and drop every cached value, because any of them could
  --- have been decided by the layer being replaced. The composed id union is rebuilt too,
  --- since the new overlay may add or withdraw entities.
  function entity.SetOverlay(composed)
    overlay = composed or {}
    entity.overlay = overlay
    unionList, unionMap = nil, nil
    entity.InvalidateCache(nil)
  end

  --- Deep copy of a plain normalized value tree. Correction and Source values carry no
  --- metatables and no cycles — normalization and the registry guarantee plain data.
  local function deepCopy(value)
    local out = {}
    for k, v in pairs(value) do
      if type(v) == "table" then out[k] = deepCopy(v) else out[k] = v end
    end
    return out
  end

  --- A producer over a value the database retains: each call returns a fresh copy, so the
  --- retained original can never be reached — or corrupted — through a read.
  local function copyProducer(value)
    return function() return deepCopy(value) end
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
    if type(id) ~= "number" then return nil end
    local byId = cache[id]
    if byId then
      local cached = byId[fieldIndex]
      if cached ~= nil then
        if cached == NIL then return nil end
        -- A cached producer: execute it for a fresh mutable copy the caller owns.
        if type(cached) == "function" then return cached() end
        return cached
      end
    else
      byId = {}
      cache[id] = byId
    end

    -- The overlay probe happens here rather than in a helper so the localization step below
    -- knows whether a Correction supplied the value: Corrections win over localization
    -- (ADR 0003 D8) — a copied lookup must never replace corrected text with stale text, and
    -- provenance must never name an owner for a value it did not supply.
    local value, corrected
    local layer = overlay[id]
    if layer ~= nil then
      local overlayValue = layer[fieldIndex]
      if overlayValue ~= nil then
        corrected = true
        -- The registry's sentinel for "this Correction sets the field to nil", which a plain
        -- nil in the overlay table cannot express.
        if overlayValue ~= LibQuestieDB.Corrections.NIL then value = overlayValue end
      end
    end

    if not corrected then
      -- Localization overlays base data only. A field with no translation falls back to the
      -- base entity value; a corrected field never consults the lookup at all.
      if l10nProvider then
        local translated = l10nProvider(id, fieldIndex)
        if translated ~= nil then value = translated end
      end

      if value == nil then
        if types[fieldIndex] == "table" and backend.tableChunk then
          -- Baked fast path: compile the stored literal into the producer directly — the
          -- decoded table is never materialised on this side of the cache at all.
          local producer = backend.tableChunk(id, fieldIndex)
          if producer then
            byId[fieldIndex] = producer
            return producer()
          end
        else
          value = backend.readField(id, fieldIndex)
        end
      end
    end

    -- Numeric getters default to 0, never nil — but only for an entity that exists in the
    -- composed view (ADR 0003 D6). An unknown id reads nil for every field, so a missing
    -- entity can no longer masquerade as a valid all-zero row.
    if value == nil then
      if types[fieldIndex] == "number" then
        if not unionMap then buildUnion() end
        if unionMap[id] == true then
          byId[fieldIndex] = 0
          return 0
        end
      end
      byId[fieldIndex] = NIL
      return nil
    end

    if type(value) == "table" then
      -- Overlay, translated, and Source-backend tables reach here: cache a producer closing
      -- over the retained value. Only copies ever escape, so the original — which may be the
      -- overlay's composed row or Source mode's frozen base — stays unreachable.
      local producer = copyProducer(value)
      byId[fieldIndex] = producer
      return producer()
    end
    byId[fieldIndex] = value
    return value
  end

  --- Positional access without the name mapping. Validates the index like `Get` does, so an
  --- out-of-range or non-numeric index returns nil identically in both modes rather than
  --- reaching the Source normalizer and raising (ADR 0003 parity).
  function entity.GetByIndex(id, fieldIndex)
    if type(fieldIndex) ~= "number" or fieldIndex < 1 or fieldIndex > fieldCount then return nil end
    return get(id, fieldIndex)
  end

  --- Field access by canonical name or positional index.
  function entity.Get(id, key)
    local fieldIndex = keys[key] or (type(key) == "number" and key or nil)
    if not fieldIndex or fieldIndex < 1 or fieldIndex > fieldCount then return nil end
    return get(id, fieldIndex)
  end

  --- Bulk field access. Returns a **packed** table — values in requested order plus `n`,
  --- because nullable fields leave holes that make `#` and a bare `unpack` undefined.
  --- Consume with `unpack(values, 1, values.n)`. An unknown entity returns nil (ADR D6/D11).
  function entity.GetAll(id, requestedKeys)
    if not entity.Exists(id) then return nil end
    local n = #requestedKeys
    local values = { n = n }
    for i = 1, n do
      values[i] = entity.Get(id, requestedKeys[i])
    end
    return values
  end

  --- Base data only, bypassing the Correction Overlay and localization. For tooling and
  --- debugging. Table values are fresh copies here too, and an out-of-range or unknown key
  --- returns nil identically in both modes (ADR 0003).
  function entity.GetRaw(id, key)
    if type(id) ~= "number" then return nil end
    local fieldIndex = keys[key] or (type(key) == "number" and key or nil)
    if not fieldIndex or fieldIndex < 1 or fieldIndex > fieldCount then return nil end
    local value = backend.readField(id, fieldIndex)
    if value == nil then
      if types[fieldIndex] == "number" then
        -- GetRaw's existence gate is the backend alone: it bypasses the overlay, so an
        -- overlay-added entity legitimately has no raw row.
        local _, map = backend.getAllIds()
        if map[id] == true then return 0 end
      end
      return nil
    end
    if type(value) == "table" then return deepCopy(value) end
    return value
  end

  --- Every id in the composed view: backend ids plus overlay-added ids (ADR D7). The list is
  --- ascending; the hashmap form is a drop-in for Questie's `*Pointers[id]` checks. Callers
  --- must treat both as read-only — they are shared, not copies.
  function entity.GetAllIds(hashmap)
    if not unionList then buildUnion() end
    if hashmap == true then return unionMap end
    return unionList
  end

  function entity.Exists(id)
    if not unionMap then buildUnion() end
    return unionMap[id] == true
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
