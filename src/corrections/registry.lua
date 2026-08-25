-- src/corrections/registry.lua
--
-- Registration, application and recomposition of Corrections.
--
-- Two categories, declared by the author. There is no automatic promotion, and therefore
-- nothing that can misfire:
--
--   Static Correction   folded in during Generation. Never shipped to end users. In Source
--                       mode it is applied to base data through the same path the generator
--                       uses, which is what makes *deleting* one observable — something an
--                       overlay-based dev addon could never manage.
--   Dynamic Correction  conditional, or otherwise not knowable before Generation. Applied at
--                       query time through the Correction Overlay.
--
-- Ported from Getters/GetterDB/Corrections/Corrections.lua, which already solved load-order
-- namespacing, collision reporting, and holding corrections behind functions so the data
-- materialises only on apply. Two things changed:
--
--   * Registration is owner-scoped. Third-party addons declare `## Dependencies: Questie` and
--     therefore register *after* Questie has already applied, so applying has to be
--     addressable per owner.
--   * A load-order collision no longer displaces the sitting entry by probing upward. That
--     cascaded: the displaced entry could take the slot the next registrant wanted, silently
--     reordering things. Entries are kept in a list and sorted by (loadOrder, registration
--     sequence), so a collision is reported and resolved without moving anyone.

local _, LibQuestieDB = ...

local registry = {}

local type, pairs, ipairs, next = type, pairs, ipairs, next
local sort = table.sort
local format = string.format

--------------------------------------------------------------------------------------------
-- Load-order namespaces
--------------------------------------------------------------------------------------------
--
-- Each expansion gets a 100-wide window. Auto-generated sets sit below the hand-maintained
-- ones so hand corrections win.
--
-- `loadOrder` means "sequence within an owner", not a global sequence. Precedence is
-- two-level — outer by the order owners FIRST applied, inner by loadOrder — and within a
-- field the later-ranked owner wins. An owner's rank is fixed at first apply; re-applying
-- refreshes that owner's layer in place. That follows load order naturally:
-- QuestieTDB < Questie < third-party.

registry.loadOrder = {
  EraStatic = 0,     EraDynamic = 100,
  SoDStatic = 200,   SoDDynamic = 300,
  TbcStatic = 400,   TbcDynamic = 500,
  WotlkStatic = 600, WotlkDynamic = 700,
  CataStatic = 800,  CataDynamic = 900,
  MoPStatic = 1000,  MoPDynamic = 1100,
}

registry.OWNER = "QuestieTDB"

--------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------

--- owner -> { name, sequence, entries = { <entry>, ... } }
registry.owners = {}
--- Owners in the order they were first seen, which is load order.
registry.ownerOrder = {}
--- Owners in the order `ApplyRegisteredCorrections` last ran for them. Outer precedence.
registry.appliedOrder = {}

--- datatype -> id -> fieldIndex -> value. The composed Correction Overlay.
registry.composed = {}
--- datatype -> id -> fieldIndex -> owner. Which owner supplied the winning value.
registry.provenance = {}

--- Set true to log when one owner overrides another on the same field.
registry.debug = false

local registrationSequence = 0

local VALID_DATATYPES = { Quest = true, Npc = true, Item = true, Object = true }

registry.expansionOrder = { Classic = 1, TBC = 2, Wotlk = 3, Cata = 4, MoP = 5 }

--- Accept `"quest"` as well as `"Quest"`: the prototype and Questie's own correction files use
--- lowercase, and refusing it would make porting them a rename exercise for no gain.
local function canonicalDatatype(datatype)
  if type(datatype) ~= "string" then return nil end
  local canonical = datatype:sub(1, 1):upper() .. datatype:sub(2):lower()
  if VALID_DATATYPES[canonical] then return canonical end
  return nil
end

registry.CanonicalDatatype = canonicalDatatype

local function ownerRecord(owner)
  local record = registry.owners[owner]
  if not record then
    record = { name = owner, entries = {}, pending = true }
    registry.owners[owner] = record
    registry.ownerOrder[#registry.ownerOrder + 1] = owner
  end
  return record
end

local function warn(message)
  if type(rawget(_G, "print")) == "function" then
    print("|cFFFFD100QuestieTDB:|r " .. message)
  end
end

--------------------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------------------

local function register(owner, datatype, name, func, loadOrder, dynamic)
  if type(owner) ~= "string" or owner == "" then
    error("RegisterCorrection: owner must be a non-empty string", 2)
  end
  local canonical = canonicalDatatype(datatype)
  if not canonical then
    error("RegisterCorrection: datatype must be one of Quest, Npc, Item, Object — got " ..
          tostring(datatype), 2)
  end
  if type(func) ~= "function" then
    -- Corrections are held behind functions so the data materialises only on apply. A
    -- multi-megabyte literal never lives in memory between load and apply, and constants the
    -- body reads are resolved at apply time rather than load time.
    error("RegisterCorrection: func must be a function returning the correction table, not the " ..
          "table itself", 2)
  end
  if loadOrder ~= nil and type(loadOrder) ~= "number" then
    error("RegisterCorrection: loadOrder must be a number or nil", 2)
  end

  local record = ownerRecord(owner)
  registrationSequence = registrationSequence + 1

  if loadOrder ~= nil then
    for _, existing in ipairs(record.entries) do
      if existing.datatype == canonical and existing.dynamic == dynamic and
         existing.loadOrder == loadOrder then
        -- Reported, not silently overwritten, and not displaced either: the tie breaks on
        -- registration sequence, which is deterministic and does not move the sitting entry.
        warn(format("load order %d is claimed by both '%s' and '%s' for %s %s corrections " ..
                    "(owner %s). Applying in registration order.",
          loadOrder, tostring(existing.name), tostring(name), canonical,
          dynamic and "dynamic" or "static", owner))
        break
      end
    end
  end

  local entry = {
    owner = owner,
    datatype = canonical,
    name = name or ("correction#" .. registrationSequence),
    func = func,
    loadOrder = loadOrder or (registrationSequence * 0.001),
    sequence = registrationSequence,
    dynamic = dynamic,
  }
  record.entries[#record.entries + 1] = entry
  record.pending = true
  return entry
end

--- Register a Static Correction — folded in during Generation, applied to base data in Source
--- mode, never shipped to end users.
function registry.RegisterCorrection(owner, datatype, name, func, loadOrder)
  return register(owner, datatype, name, func, loadOrder, false)
end

--- Register a Dynamic Correction — applied at query time through the Correction Overlay.
function registry.RegisterRuntimeCorrection(owner, datatype, name, func, loadOrder)
  return register(owner, datatype, name, func, loadOrder, true)
end

--- Withdraw a registration. Recomposition rebuilds from the registry rather than accumulating
--- into it, so re-applying after this genuinely removes the correction's effect — which the
--- previous merge-only `addOverride` could not do.
function registry.UnregisterCorrection(owner, datatype, name)
  local record = registry.owners[owner]
  if not record then return false end
  local canonical = canonicalDatatype(datatype)
  for index, entry in ipairs(record.entries) do
    if entry.datatype == canonical and entry.name == name then
      table.remove(record.entries, index)
      record.pending = true
      return true
    end
  end
  return false
end

--- Optional convenience wrapper so a consumer does not repeat its own name.
function registry.GetRegistrar(owner)
  return {
    owner = owner,
    RegisterCorrection = function(datatype, name, func, loadOrder)
      return registry.RegisterCorrection(owner, datatype, name, func, loadOrder)
    end,
    RegisterRuntimeCorrection = function(datatype, name, func, loadOrder)
      return registry.RegisterRuntimeCorrection(owner, datatype, name, func, loadOrder)
    end,
    Apply = function() return registry.ApplyRegisteredCorrections(owner) end,
  }
end

--------------------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------------------

local function compareEntries(a, b)
  if a.loadOrder ~= b.loadOrder then return a.loadOrder < b.loadOrder end
  return a.sequence < b.sequence
end

--- Every registered entry matching the filters, in apply order.
---@param filter table { owner?, datatype?, dynamic? }
function registry.Select(filter)
  filter = filter or {}
  local selected = {}
  local owners = filter.owner and { filter.owner } or registry.ownerOrder
  for _, owner in ipairs(owners) do
    local record = registry.owners[owner]
    if record then
      for _, entry in ipairs(record.entries) do
        local matches = true
        if filter.datatype and entry.datatype ~= canonicalDatatype(filter.datatype) then matches = false end
        if filter.dynamic ~= nil and entry.dynamic ~= filter.dynamic then matches = false end
        if matches then selected[#selected + 1] = entry end
      end
    end
  end
  sort(selected, compareEntries)
  return selected
end

--------------------------------------------------------------------------------------------
-- Applying Static Corrections to base data
--------------------------------------------------------------------------------------------

--- Merge one correction table into a set of entity rows.
---
--- Shape is `id -> fieldIndex -> value`, matching Questie's. Two of Questie's idioms carry
--- over unchanged:
---
---   * `[key] = nil` in a correction literal is a no-op, because Lua's table constructor drops
---     it and `pairs` never visits the key. Occurrences in the ported files are documentation.
---   * `[key] = {}` is the delete idiom. An empty table reads back as nil under
---     docs/storage-format.md, so writing `{}` into base data removes the field for every
---     reader — the generator omits the line, Source mode normalizes it away.
---
--- An id absent from the base data is normally created, which is how `LoadMissingQuests`
--- and the `InsertMissing*Ids` helpers make the database emit a row at all. `noNewEntries`
--- forbids creation outright. Inherited Static Corrections additionally set
--- `allowNamedInheritedEntry`, matching Questie's exception for a Correction whose field 1 names
--- a complete entity rather than adding fields to an entity a later expansion removed.
---@param entities table id -> field array
---@param corrections table id -> fieldIndex -> value
---@param options table? { noOverwrites = boolean, noNewEntries = boolean, allowNamedInheritedEntry = boolean }
---@return number applied
function registry.MergeInto(entities, corrections, options)
  options = options or {}
  local applied = 0
  for id, fields in pairs(corrections) do
    local row = entities[id]
    local mayCreate = not options.noNewEntries
      or (options.allowNamedInheritedEntry and fields[1] ~= nil)
    if not row and mayCreate then
      row = {}
      entities[id] = row
    end
    if row then
      for fieldIndex, value in pairs(fields) do
        if type(fieldIndex) == "number" then
          if options.noOverwrites then
            if row[fieldIndex] == nil then
              row[fieldIndex] = value
              applied = applied + 1
            end
          else
            row[fieldIndex] = value
            applied = applied + 1
          end
        end
      end
    end
  end
  return applied
end

--- Resolve merge policy for one Static Correction in the target flavor.
--- Older-expansion Corrections may update surviving entities but cannot resurrect entities the
--- target expansion removed. A field-1 name is the explicit exception for a complete entity.
--- The exception is confined here so generic `noNewEntries` remains strict.
---@param entry table Registered Static Correction
---@param flavor table? Target flavor
---@return table? options Merge options, or the entry's original options when no overlay is needed
local function staticMergeOptions(entry, flavor)
  if not flavor or not entry.sourceExpansionOrder then return entry.options end

  local targetOrder = registry.expansionOrder[flavor.expansion]
  if not targetOrder or targetOrder <= entry.sourceExpansionOrder then return entry.options end

  local options = {}
  for key, value in pairs(entry.options or {}) do options[key] = value end
  options.noNewEntries = true
  options.allowNamedInheritedEntry = true
  return options
end

--- Apply every Static Correction for one entity type to a loaded table.
---
--- Used by Generation and by Source mode. Same code, same order, same result — which is the
--- whole point: "what I see in dev is what ships" follows from shared code rather than from a
--- test.
---@param datatype string "Quest" | "Npc" | "Item" | "Object"
---@param entities table
---@param flavor table? An entry from config.flavors
---@param owner string? Restrict to one owner; Generation passes "QuestieTDB"
---@return number applied
function registry.ApplyStaticToEntities(datatype, entities, flavor, owner)
  local applied = 0
  for _, entry in ipairs(registry.Select({ datatype = datatype, dynamic = false, owner = owner })) do
    if registry.EntryApplies(entry, flavor) then
      local corrections = entry.func()
      if type(corrections) == "table" then
        applied = applied + registry.MergeInto(
          entities, corrections, staticMergeOptions(entry, flavor))
      end
    end
  end
  return applied
end

--- Whether an entry applies to a flavor. An entry may declare `expansions = { Classic = true }`
--- or `minExpansion = 2`; declaring nothing means "every flavor".
function registry.EntryApplies(entry, flavor)
  if not flavor then return true end
  if entry.expansions and not entry.expansions[flavor.expansion] then return false end
  if entry.minExpansionOrder then
    local order = registry.expansionOrder[flavor.expansion]
    if not order or order < entry.minExpansionOrder then return false end
  end
  return true
end

--------------------------------------------------------------------------------------------
-- Composing the Correction Overlay
--------------------------------------------------------------------------------------------

--- Rebuild the composed view for the given owners.
---
--- Recomposition is O(total corrections) but runs only on init and setting changes, and it is
--- **idempotent by construction** — it rebuilds from the registry instead of accumulating into
--- it. That is what makes a withdrawn correction actually disappear, and it composes cleanly
--- with freezing, because each recomposition produces fresh objects.
local function recompose(flavor)
  local normalize = LibQuestieDB.Meta.normalize
  local composed, provenance = {}, {}

  for _, owner in ipairs(registry.appliedOrder) do
    for _, entry in ipairs(registry.Select({ owner = owner, dynamic = true })) do
      if registry.EntryApplies(entry, flavor) then
        local corrections = entry.func()
        if type(corrections) == "table" then
          local datatype = entry.datatype
          local meta = LibQuestieDB.Meta[datatype]
          local byType = composed[datatype]
          if not byType then byType = {}; composed[datatype] = byType end
          local provByType = provenance[datatype]
          if not provByType then provByType = {}; provenance[datatype] = provByType end

          for id, fields in pairs(corrections) do
            -- Rows are created only when a write survives validation. In particular, a
            -- Correction containing only ignored constant fields must not invent an entity.
            local row = byType[id]
            local provRow = provByType[id]

            for fieldIndex, value in pairs(fields) do
              if type(fieldIndex) == "number" and meta and fieldIndex <= meta.fieldCount then
                local constantValues = meta.constantValues
                if constantValues and constantValues[fieldIndex] ~= nil then
                  -- Constant fields no longer accept runtime ownership. Reads keep the schema
                  -- placeholder and provenance remains with QuestieTDB.
                  if registry.debug then
                    warn(format('owner "%s" wrote deprecated constant %s %s field %s — dropped',
                      owner, datatype, tostring(id), tostring(meta.names[fieldIndex])))
                  end
                elseif type(value) == "table" and next(value) ~= nil and
                       meta.types[fieldIndex] ~= "table" then
                  -- A non-empty table arriving at a scalar-typed field is a correction-author
                  -- error. Generation fails loudly on the same input; the overlay reports and
                  -- drops the write rather than raising out of recomposition.
                  warn(format('owner "%s" wrote a table into %s-typed %s %s field %s — dropped',
                    owner, tostring(meta.types[fieldIndex]), datatype, tostring(id),
                    tostring(meta.names[fieldIndex])))
                else
                  if not row then row = {}; byType[id] = row end
                  if not provRow then provRow = {}; provByType[id] = provRow end

                  -- `[key] = {}` is the delete idiom for every field type. Scalar deletes are
                  -- decided here because normalize passes tables through scalar branches.
                  if type(value) == "table" and next(value) == nil then
                    row[fieldIndex] = registry.NIL
                    provRow[fieldIndex] = owner
                  else
                    if registry.debug and provRow[fieldIndex] and provRow[fieldIndex] ~= owner then
                      warn(format('owner "%s" overrode "%s" on %s %s field %s',
                        owner, provRow[fieldIndex], datatype, tostring(id),
                        tostring(meta.names[fieldIndex])))
                    end
                    -- The overlay stores normalized values so `{0,0}` and other nil semantics
                    -- match base data without another read-time decision.
                    local normalized = normalize.field(meta, fieldIndex, value)
                    if normalized == nil then
                      row[fieldIndex] = registry.NIL
                    else
                      row[fieldIndex] = normalized
                    end
                    provRow[fieldIndex] = owner
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  registry.composed = composed
  registry.provenance = provenance
end

--- Sentinel for "the overlay sets this field to nil", which a plain nil cannot express.
registry.NIL = setmetatable({}, { __tostring = function() return "<overlay nil>" end })

--- Install the composed view onto the Entity globals and drop stale cache entries.
local function publish()
  local config = LibQuestieDB.config
  for _, entityType in ipairs(config.entityTypes) do
    local entity = LibQuestieDB[entityType.name]
    if entity then
      entity.SetOverlay(registry.composed[entityType.name] or {})
    end
  end
end

--- Apply pending Corrections.
---
--- The owner parameter selects **which layer is being refreshed**, never which layers are
--- visible: recomposition always includes every live layer. This is required by load order,
--- not a convenience — a third-party addon declares `## Dependencies: Questie` and therefore
--- registers after Questie has already applied.
---@param owner string? One owner, or every pending owner when omitted
function registry.ApplyRegisteredCorrections(owner)
  local owners
  if owner then
    if not registry.owners[owner] then return 0 end
    owners = { owner }
  else
    owners = {}
    for _, name in ipairs(registry.ownerOrder) do
      if registry.owners[name].pending then owners[#owners + 1] = name end
    end
  end

  for _, name in ipairs(owners) do
    -- Owner rank is fixed at first apply; a re-apply refreshes the owner's layer in place.
    -- Moving a re-applying owner to the end would let a consumer state refresh hoist one
    -- owner's whole layer above corrections registered later, inverting the documented
    -- QuestieTDB < Questie < third-party order.
    local ranked = false
    for _, applied in ipairs(registry.appliedOrder) do
      if applied == name then ranked = true; break end
    end
    if not ranked then registry.appliedOrder[#registry.appliedOrder + 1] = name end
    registry.owners[name].pending = false
  end

  -- Both read modes publish their flavor as LibQuestieDB.flavor (source.lua, baked.lua), so
  -- entry-level expansion filters compose identically in both — reading only the Source
  -- backend here left them inert in Baked mode.
  recompose(LibQuestieDB.flavor)
  publish()
  return #owners
end

--- Which owner supplied the winning value for a field, for bug reports.
function registry.GetProvenance(datatype, id, key)
  local canonical = canonicalDatatype(datatype)
  if not canonical then return nil end
  local meta = LibQuestieDB.Meta[canonical]
  local fieldIndex = (meta and meta.keys[key]) or (type(key) == "number" and key or nil)
  if not fieldIndex then return nil end
  local byType = registry.provenance[canonical]
  local row = byType and byType[id]
  if row and row[fieldIndex] then return row[fieldIndex] end
  -- No Dynamic Correction won, so the value came from base data — which in Baked mode already
  -- has QuestieTDB's Static Corrections folded in.
  return registry.OWNER
end

--- Owners in applied order, so a debug view can show precedence.
function registry.GetOwners()
  local owners = {}
  for index, name in ipairs(registry.appliedOrder) do owners[index] = name end
  return owners
end

function registry.Reset()
  registry.owners = {}
  registry.ownerOrder = {}
  registry.appliedOrder = {}
  registry.composed = {}
  registry.provenance = {}
  registrationSequence = 0
end

LibQuestieDB.Corrections = registry

return registry
