-- generator/runtime.lua
--
-- Stands up the shipped `src/` namespace offline, so Generation applies Static Corrections
-- through the *same* registry the client uses rather than a parallel implementation.
--
-- This is what makes "what I see in dev is what ships" a property of shared code. If the
-- generator had its own correction engine, source/baked equivalence would be testing two
-- implementations against each other and every divergence would be a coin flip about which one
-- was right.

local lib = dofile("generator/lib.lua")

local runtime = {}

--- Load one `src/` file with WoW's addon varargs.
local function execute(path, addonName, addonTable)
  local chunk, err = loadfile(path)
  if not chunk then error("Cannot load " .. path .. ": " .. tostring(err), 0) end
  local ok, execErr = pcall(chunk, addonName, addonTable)
  if not ok then error("Error loading " .. path .. ": " .. tostring(execErr), 0) end
end

runtime.execute = execute

--- Build a `LibQuestieDB` namespace with everything Generation needs: config, the materialized
--- schema, nil/empty semantics, the extracted constants, the corrections registry, and the
--- compat shim. No read backend — the generator reads raw tables directly.
function runtime.build()
  local config = dofile("src/config.lua")
  local LibQuestieDB = {}
  local files = {
    "src/config.lua",
    "src/meta/normalize.lua",
    "src/meta/codec.lua",
    "src/meta/questMeta.lua",
    "src/meta/npcMeta.lua",
    "src/meta/itemMeta.lua",
    "src/meta/objectMeta.lua",
    "src/corrections/registry.lua",
  }
  for _, path in ipairs(files) do
    execute(path, "QuestieTDB", LibQuestieDB)
  end

  -- Correction support is optional: the tracer bullet and a bare data round-trip work without
  -- any corrections ported, and saying so beats failing on a missing file.
  if lib.fileExists("src/corrections/enum/constants.lua") then
    execute("src/corrections/enum/constants.lua", "QuestieTDB", LibQuestieDB)
    execute("src/corrections/compat.lua", "QuestieTDB", LibQuestieDB)
    execute("src/corrections/manifest.lua", "QuestieTDB", LibQuestieDB)
    execute("src/corrections/register.lua", "QuestieTDB", LibQuestieDB)
  end

  -- Derived Passes share this namespace with the correction registry on purpose: Generation
  -- and Source mode must run the same pass code over the same corrected tables, exactly as
  -- they already share ApplyStaticToEntities. See docs/adr/0004-derived-passes.md.
  for _, path in ipairs(config.derivedFiles) do
    execute(path, "QuestieTDB", LibQuestieDB)
  end

  return LibQuestieDB
end

--- Load every correction file the manifest lists for a flavor, and register what it provides.
---@return number registered
---@return number loadedFiles
function runtime.loadCorrections(LibQuestieDB, flavor)
  local manifest = LibQuestieDB.CorrectionManifest
  if not manifest then return 0, 0 end

  local registry = LibQuestieDB.Corrections
  local compat = LibQuestieDB.CorrectionCompat
  local expansionOrder = registry.expansionOrder

  local remove = compat.Install(flavor)
  local loadedFiles = 0

  for _, spec in ipairs(manifest) do
    local applies = true
    if flavor then
      if spec.expansions and not spec.expansions[flavor.expansion] then applies = false end
      if spec.minExpansionOrder and (expansionOrder[flavor.expansion] or 0) < spec.minExpansionOrder then
        applies = false
      end
    end
    if applies then
      local path = "src/corrections/" .. spec.file
      if lib.fileExists(path) then
        execute(path, "QuestieTDB", LibQuestieDB)
        loadedFiles = loadedFiles + 1
      end
    end
  end

  local modules = compat.modules
  local registered = LibQuestieDB.CorrectionRegister.FromManifest(flavor, function(name)
    return modules[name]
  end)

  remove()
  return registered, loadedFiles
end

return runtime
