-- src/corrections/register.lua
--
-- Turns loaded correction files into registry entries.
--
-- The correction files themselves are verbatim copies of Questie's and know nothing about
-- QuestieTDB; `src/corrections/manifest.lua` says which functions each one provides and
-- whether each is Static or Dynamic. That classification is **declared, never inferred** —
-- folder names are not a reliable signal, as the prototype's `Sod/static/…` file registering
-- dynamic demonstrates.

local _, LibQuestieDB = ...

local register = {}

local registry = LibQuestieDB.Corrections
local compat = LibQuestieDB.CorrectionCompat

--- Wrap one function from a correction module into something the registry can apply.
---
--- Two shapes have to work. Most functions return the correction table. A few — Questie's
--- `LoadMissingQuests` and the `InsertMissing*Ids` helpers called from inside `Load` — instead
--- write straight into `QuestieDB.questData[id]` to make the database emit a row at all. The
--- compat shim captures those writes, and both contributions are merged here, direct writes
--- first so a returned value wins.
---@param module table
---@param functionName string
---@param datatype string
---@return fun(): table
local function wrap(module, functionName, datatype)
  return function()
    compat.BeginCapture()
    local returned = compat.Invoke(module[functionName], module)
    local captured = compat.EndCapture(datatype)

    local merged = {}
    for id, fields in pairs(captured) do
      local row = {}
      for key, value in pairs(fields) do row[key] = value end
      merged[id] = row
    end
    if type(returned) == "table" then
      for id, fields in pairs(returned) do
        local row = merged[id]
        if not row then row = {}; merged[id] = row end
        for key, value in pairs(fields) do row[key] = value end
      end
    end
    return merged
  end
end

--- Whether this manifest entry is a Season of Discovery correction set.
function register.IsSeasonal(spec)
  return spec.file:find("^Sod/") ~= nil
end

--- Whether the running client actually has Season of Discovery active (ADR 0003 D9).
--- SoD is a Dynamic Correction set over the Era database, but it must never apply on
--- ordinary non-seasonal Era — expansion gating alone let 10,640 SoD ids leak onto plain
--- Vanilla. Offline and in the emulator, `C_Seasons.GetActiveSeason()` returns 0, so the
--- default everywhere without a live seasonal client is "not active".
function register.IsSodActive()
  local seasons = rawget(_G, "C_Seasons")
  if not seasons or type(seasons.GetActiveSeason) ~= "function" then return false end
  local enum = rawget(_G, "Enum")
  local sodId = enum and enum.SeasonID and enum.SeasonID.SeasonOfDiscovery or 2
  return seasons.GetActiveSeason() == sodId
end

--- Whether the running client is Titan Reforged. Upstream detects it as a Wrath client whose
--- active season is 109 — `Modules/VersionCheck.lua:89`, whose own comment notes there is no
--- `Enum.SeasonID` entry for it, hence the literal. Offline and in the emulator the season
--- API reports 0, so the default everywhere is plain Wrath.
function register.IsTitanReforgedActive()
  local seasons = rawget(_G, "C_Seasons")
  if not seasons or type(seasons.GetActiveSeason) ~= "function" then return false end
  return seasons.GetActiveSeason() == 109
end

--- Per-function Dynamic gates, named by a manifest entry's `gatedDynamic` map. SoD gating is
--- per-file — the whole `Sod/` tree is that season's set — but these must be per-function:
--- the same upstream file carries gated and ungated Dynamic functions side by side
--- (`wotlkQuestFixes.lua` holds ungated `LoadFactionFixes` beside Titan-only
--- `LoadTitanReforgedFixes`, applied under `if Questie.IsTitanReforged` in
--- `QuestieCorrections:Initialize`). An unrecognized gate name stays closed: a correction
--- set applying where it must not is the defect class this exists to stop.
register.variantActive = {
  TitanReforged = register.IsTitanReforgedActive,
}

--- Parameterized correction functions recorded by `FromManifest`, keyed by function name.
--- Each needs a runtime fact QuestieTDB does not own (the Darkmoon Faire's location), so
--- they are never applied automatically — see `ApplyParameterized`.
register.parameterized = {}

--- Register everything the manifest describes, for one flavor.
---
--- The generator runs offline with only QuestieTDB present, so it can only ever bake
--- corrections owned by QuestieTDB. Anything registered by Questie or a third party is Dynamic
--- by definition; the owner recorded here makes that enforceable rather than conventional.
---@param flavor table? An entry from config.flavors; nil registers everything
---@param moduleFor fun(name: string): table? Resolves a module name to its loaded table
---@return number registered
---@return number skipped
function register.FromManifest(flavor, moduleFor)
  local manifest = LibQuestieDB.CorrectionManifest
  if not manifest then return 0, 0 end

  local order = registry.loadOrder
  local expansionOrder = registry.expansionOrder
  local registered, skipped = 0, 0

  -- Baked mode never applies Static Corrections: Generation already folded them into the
  -- metadata store, and ApplyStaticToEntities is only called by Source mode and the
  -- generator. Skip the registrations rather than build wrap() closures nothing can ever
  -- run — the packaged copies of these files have their static bodies stripped anyway
  -- (tools/strip-static.lua, issue #5). Offline (`generator/runtime.lua`) and in Source
  -- mode `LibQuestieDB.mode` is never "baked", so statics register there as before.
  local registerStatics = LibQuestieDB.mode ~= "baked"

  for index, spec in ipairs(manifest) do
    local applies = true
    if flavor then
      if spec.expansions and not spec.expansions[flavor.expansion] then applies = false end
      if spec.minExpansionOrder and (expansionOrder[flavor.expansion] or 0) < spec.minExpansionOrder then
        applies = false
      end
    end
    if applies and register.IsSeasonal(spec) and not register.IsSodActive() then
      applies = false
    end

    local module = applies and moduleFor(spec.module) or nil
    if not module then
      if applies then skipped = skipped + 1 end
    else
      -- Load-order constants, not literal numbers. The prototype's SoD files passed a literal
      -- 70 rather than SoDBaseDynamicOrder, so despite the comment "Sod will always load last"
      -- they applied *before* Era's faction fixes at 120. Deriving the window from the file's
      -- own expansion makes that class of mistake unrepresentable.
      local window = spec.window or register.WindowFor(spec)

      if registerStatics then
        for offset, functionName in ipairs(spec.static or {}) do
          if type(module[functionName]) == "function" then
            local entry = registry.RegisterCorrection(registry.OWNER, spec.datatype,
              spec.file .. ":" .. functionName,
              wrap(module, functionName, spec.datatype),
              order[window .. "Static"] + (spec.generated and 1 or 10) + offset)
            entry.expansions = spec.expansions
            entry.minExpansionOrder = spec.minExpansionOrder
            -- Expansion-gated files start in their minimum expansion. Only ungated Era files
            -- need a separate source order in the manifest.
            entry.sourceExpansionOrder = spec.sourceExpansionOrder or spec.minExpansionOrder
            entry.options = spec.options
            registered = registered + 1
          end
        end
      end

      for offset, functionName in ipairs(spec.dynamic or {}) do
        local gate = spec.gatedDynamic and spec.gatedDynamic[functionName]
        local gateOpen = not gate
          or (register.variantActive[gate] ~= nil and register.variantActive[gate]())
        if gateOpen and type(module[functionName]) == "function" then
          local entry = registry.RegisterRuntimeCorrection(registry.OWNER, spec.datatype,
            spec.file .. ":" .. functionName,
            wrap(module, functionName, spec.datatype),
            order[window .. "Dynamic"] + (spec.generated and 1 or 10) + offset)
          entry.expansions = spec.expansions
          entry.minExpansionOrder = spec.minExpansionOrder
          entry.options = spec.options
          registered = registered + 1
        end
      end

      -- Parameterized functions are recorded, never registered: each needs an argument only
      -- the consumer knows. Previously these were silently dropped — the baked artifact kept
      -- both Darkmoon Faire locations and could expose the wrong one.
      for offset, functionName in ipairs(spec.parameterized or {}) do
        if type(module[functionName]) == "function" then
          local entries = register.parameterized[functionName]
          if not entries then entries = {}; register.parameterized[functionName] = entries end
          entries[#entries + 1] = {
            spec = spec,
            module = module,
            functionName = functionName,
            loadOrder = order[window .. "Dynamic"] + 50 + offset,
          }
        end
      end
    end
    manifest[index].loaded = module ~= nil
  end

  return registered, skipped
end

--- Apply a parameterized correction set with the consumer-supplied runtime fact — e.g.
--- `ApplyParameterized("LoadDarkmoonFixes", "Elwynn")`. Registers (replacing any previous
--- application of the same set, so a changed argument recomposes rather than accumulates)
--- and applies as an ordinary QuestieTDB Dynamic layer.
---
--- Correction coordinates must be authored values: quantization is deliberately
--- non-idempotent, so never feed back a coordinate read out of the database.
---@return number applied How many recorded sets matched and were registered
function register.ApplyParameterized(functionName, ...)
  local entries = register.parameterized[functionName]
  if not entries or #entries == 0 then return 0 end

  local argCount = select("#", ...)
  local args = { ... }
  local applied = 0

  for _, recorded in ipairs(entries) do
    local spec = recorded.spec
    local name = spec.file .. ":" .. recorded.functionName
    registry.UnregisterCorrection(registry.OWNER, spec.datatype, name)

    local module = recorded.module
    local entry = registry.RegisterRuntimeCorrection(registry.OWNER, spec.datatype, name,
      function()
        -- Re-invoke through the same capture path, with the consumer's arguments.
        compat.BeginCapture()
        local returned = compat.Invoke(
          module[recorded.functionName], module, unpack(args, 1, argCount))
        local captured = compat.EndCapture(spec.datatype)
        local merged = {}
        for id, fields in pairs(captured) do
          local row = {}
          for key, value in pairs(fields) do row[key] = value end
          merged[id] = row
        end
        if type(returned) == "table" then
          for id, fields in pairs(returned) do
            local row = merged[id]
            if not row then row = {}; merged[id] = row end
            for key, value in pairs(fields) do row[key] = value end
          end
        end
        return merged
      end,
      recorded.loadOrder)
    entry.expansions = spec.expansions
    entry.minExpansionOrder = spec.minExpansionOrder
    entry.options = spec.options
    applied = applied + 1
  end

  if applied > 0 then
    registry.ApplyRegisteredCorrections(registry.OWNER)
  end
  return applied
end

registry.ApplyParameterized = register.ApplyParameterized

--- Which load-order window a manifest entry belongs to.
---
--- Season of Discovery is the interesting one: it is a Dynamic Correction set over the Era
--- database rather than a separate database, and it must apply *after* Era's own fixes. The
--- SoD window sits above Era's for exactly that reason.
function register.WindowFor(spec)
  if spec.file:find("^Sod/") then return "SoD" end
  if spec.file:find("^Era/") then return "Era" end
  if spec.file:find("^Tbc/") then return "Tbc" end
  if spec.file:find("^Wotlk/") then return "Wotlk" end
  if spec.file:find("^Cata/") then return "Cata" end
  if spec.file:find("^MoP/") then return "MoP" end
  return "Era" -- Shared/, which applies to every flavor
end

LibQuestieDB.CorrectionRegister = register

return register
