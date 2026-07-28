-- src/api.lua
--
-- The public surface. Another addon can read entity fields, discover the schema, register its
-- own Corrections, and detect an incompatible version through this file alone.
--
-- Questie is the first consumer, but nothing here assumes it.

local ADDON_NAME, LibQuestieDB = ...

local config = LibQuestieDB.config
local shared = LibQuestieDB.shared

--------------------------------------------------------------------------------------------
-- Entity globals
--------------------------------------------------------------------------------------------

local mode = LibQuestieDB.mode or "source"
local backendFactory = LibQuestieDB.read[mode]
if not backendFactory then
  error("QuestieTDB: no read backend for mode '" .. tostring(mode) .. "'", 0)
end

for _, entityType in ipairs(config.entityTypes) do
  local meta = LibQuestieDB.Meta[entityType.name]
  if meta then
    local entity = shared.CreateEntity(meta, backendFactory.CreateBackend(meta))
    LibQuestieDB[entityType.name] = entity
    -- `QuestDB`, `NpcDB`, `ItemDB`, `ObjectDB` — the shorthand the tracer bullet and
    -- `/dump` use, and what the prototypes exposed.
    _G[entityType.name .. "DB"] = entity
  end
end

--------------------------------------------------------------------------------------------
-- Contract
--------------------------------------------------------------------------------------------

--- Independent release cycles make skew inevitable. A hard `## Dependencies: QuestieTDB`
--- covers *absence*; it does not cover *presence with the wrong version*. A consumer checks
--- this at init and fails with a specific message.
LibQuestieDB.contractVersion = config.contractVersion

LibQuestieDB.addonName = ADDON_NAME

--- "source" or "baked". Mode must be unmistakable, so this is public rather than internal.
LibQuestieDB.readMode = mode

--------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------

--- Drop cached values for one entity, or for everything when both arguments are omitted.
--- Registering a Correction after `ApplyRegisteredCorrections` has run must stay legal, which
--- is what this is for.
function LibQuestieDB.InvalidateCache(datatype, id)
  if datatype == nil then
    for _, entityType in ipairs(config.entityTypes) do
      local entity = LibQuestieDB[entityType.name]
      if entity then entity.InvalidateCache(nil) end
    end
    return
  end
  local entity = LibQuestieDB[datatype]
  if entity then entity.InvalidateCache(id) end
end

--------------------------------------------------------------------------------------------
-- Own corrections
--------------------------------------------------------------------------------------------

--- QuestieTDB applies its own layer at load, so base data is queryable immediately and
--- correctly — step 1 of the initialization order in DESIGN.md. A consumer then registers its
--- policy Corrections and calls `ApplyRegisteredCorrections("<its own name>")` in its staged
--- init; recomposition always includes every live layer, so QuestieTDB's stays visible.
LibQuestieDB.ApplyRegisteredCorrections = LibQuestieDB.Corrections.ApplyRegisteredCorrections
LibQuestieDB.RegisterCorrection = LibQuestieDB.Corrections.RegisterCorrection
LibQuestieDB.RegisterRuntimeCorrection = LibQuestieDB.Corrections.RegisterRuntimeCorrection
LibQuestieDB.GetRegistrar = LibQuestieDB.Corrections.GetRegistrar
LibQuestieDB.GetProvenance = LibQuestieDB.Corrections.GetProvenance
LibQuestieDB.GetOwners = LibQuestieDB.Corrections.GetOwners

LibQuestieDB.Corrections.ApplyRegisteredCorrections(LibQuestieDB.Corrections.OWNER)

--- Localization attaches after the Entity globals exist, and is a no-op when the artifact
--- carries no l10n data.
if LibQuestieDB.l10n and LibQuestieDB.l10n.Initialize then
  LibQuestieDB.l10n.Initialize()
end

--- Mode must be unmistakable in-game, so the indicator comes up as part of loading rather
--- than waiting for a consumer to ask for it.
if LibQuestieDB.ModeIndicator then
  LibQuestieDB.ModeIndicator.Initialize()
end

_G.LibQuestieDB = LibQuestieDB

return LibQuestieDB
