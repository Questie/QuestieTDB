-- Focused controls for the ObjectiveFirst oracle and load-boundary lifecycle.
local lib = dofile("generator/lib.lua")
local config = dofile("src/config.lua")
config.correctionManifest = dofile("src/corrections/manifest.lua")
local fidelity = dofile("tools/objective-first.lua")

---@param check fun(condition: boolean, message: string)
---@param questiePath string
---@return nil
return function(check, questiePath)
  fidelity.run(check, questiePath)

  -- A mutation of executable pinned input must produce exactly one localized difference.
  local path = "Database/Corrections/classicQuestFixes.lua"
  local original = lib.readAll(questiePath .. "/" .. path)
  local expected = fidelity.capture({ { path = path, content = original } })
  local controls = {
    { name = "addition", value = "QuestieCorrections.itemObjectiveFirst[503] = true\nQuestieCorrections.itemObjectiveFirst[2147483647] = true", differences = 1 },
    { name = "removal", value = "", differences = 1 },
    { name = "change", value = "QuestieCorrections.itemObjectiveFirst[503] = false", differences = 1 },
    { name = "shape", value = "QuestieCorrections.itemObjectiveFirst[503] = {}", differences = 1 },
    { name = "formatting", value = "QuestieCorrections.itemObjectiveFirst[503] = true -- same hint", differences = 0 },
  }
  for _, control in ipairs(controls) do
    local changed, replacements = original:gsub("QuestieCorrections%.itemObjectiveFirst%[503%] = true", control.value)
    check(replacements == 1, control.name .. " finds exactly one pinned mutation target")
    local actual = fidelity.capture({ { path = path, content = changed } })
    local differences = fidelity.differences(actual, expected)
    check(#differences == control.differences, control.name .. " self-proof: " .. table.concat(differences, "; "))
  end

  local sourceFiles = fidelity.tocFiles("QuestieTDB.toc")
  local vanilla, scopedNamespace, env = fidelity.loadProvider(sourceFiles, "Vanilla", 0, "source")
  check(vanilla.killCreditObjectiveFirst[52] == nil, "Vanilla excludes Cata quest 52")
  check(vanilla.itemObjectiveFirst[503] == true, "Vanilla retains its own quest 503")
  local sod = fidelity.loadProvider(sourceFiles, "Vanilla", 2, "source")
  for _, id in ipairs({ 85304, 85386, 89567 }) do
    check(vanilla.eventObjectiveFirst[id] == nil, "plain Vanilla excludes SoD event " .. id)
    check(sod.eventObjectiveFirst[id] == true, "SoD includes event " .. id)
  end
  for _, flavor in ipairs({ "TBC", "Wrath", "Cata" }) do
    local hints = fidelity.loadProvider(sourceFiles, flavor, 0, "source")
    for _, id in ipairs({ 10068, 10069, 10070, 10071, 10072, 10073 }) do
      check(hints.spellObjectiveFirst[id] == nil, flavor .. " excludes MoP spell " .. id)
    end
  end

  -- Titan has no authored hints today. Synthetic writes prove the season marker itself is
  -- closed, rather than letting an empty upstream table make every negative case vacuous.
  local scopeCases = {
    { flavor = "Vanilla", season = 0, marker = "Sod", admitted = false },
    { flavor = "Vanilla", season = 2, marker = "Sod", admitted = true },
    { flavor = "Vanilla", season = 99, marker = "Sod", admitted = false },
    { flavor = "Wrath", season = 2, marker = "Sod", admitted = false },
    { flavor = "Wrath", season = 109, marker = "Titan", admitted = true },
    { flavor = "Wrath", season = 0, marker = "Titan", admitted = false },
    { flavor = "Wrath", season = 99, marker = "Titan", admitted = false },
    { flavor = "Vanilla", season = 109, marker = "Titan", admitted = false },
    { flavor = "TBC", season = 109, marker = "Titan", admitted = false },
    { flavor = "Cata", season = 109, marker = "Titan", admitted = false },
    { flavor = "Mists", season = 109, marker = "Titan", admitted = false },
  }
  for _, case in ipairs(scopeCases) do
    scopedNamespace.flavor = config.flavorByName[case.flavor]
    env.C_Seasons.GetActiveSeason = function() return case.season end
    local compat = scopedNamespace.CorrectionCompat
    local remove = compat.Install(scopedNamespace.flavor)
    local marker = assert(loadfile("src/corrections/scopes/" .. case.marker .. ".lua"))
    setfenv(marker, env)
    marker("QuestieTDB", scopedNamespace)
    env.QuestieLoader:ImportModule("QuestieCorrections").eventObjectiveFirst[2147483647] = true
    check((compat.objectiveFirst.eventObjectiveFirst[2147483647] == true) == case.admitted,
      case.flavor .. " season " .. case.season .. " admits " .. case.marker .. " hints correctly")
    remove()
  end

  -- Reuse the same shim, not just fresh emulator namespaces. Discarding a later file must
  -- neither erase an earlier hint nor suppress the module's provider definitions.
  local runtime = dofile("generator/runtime.lua")
  local namespace = runtime.build()
  local compat = namespace.CorrectionCompat
  local published = compat.objectiveFirst
  local identities = {}
  for _, field in ipairs(fidelity.fields) do identities[field] = published[field] end
  local previousLoader = rawget(_G, "QuestieLoader")
  local remove = compat.Install(config.flavorByName.Mists)
  local accepted = QuestieLoader:ImportModule("QuestieCorrections")
  accepted.itemObjectiveFirst[503] = true
  compat.SelectObjectiveFirstScope(false)
  local discarded = QuestieLoader:ImportModule("QuestieCorrections")
  discarded.itemObjectiveFirst[503] = false
  discarded.spellObjectiveFirst[10068] = true
  local provider = QuestieLoader:CreateModule("InapplicableHintProvider")
  provider.Load = function() return {} end
  check(published.itemObjectiveFirst[503] == true, "discarded overwrite preserves an earlier applicable hint")
  check(published.spellObjectiveFirst[10068] == nil, "discarded hints never enter the public tables")
  check(compat.modules.InapplicableHintProvider == provider and type(provider.Load) == "function",
    "hint scope does not suppress correction provider definitions")
  compat.SelectObjectiveFirstScope(true)
  check(QuestieLoader:ImportModule("QuestieCorrections") == published, "scope reentry restores the exact hint destination")
  remove()
  check(rawget(_G, "QuestieLoader") == previousLoader, "Remove restores the original loader by identity")
  for _, ids in pairs(discarded) do check(next(ids) == nil, "Remove releases discarded hint contents") end

  remove = compat.Install(config.flavorByName.Vanilla)
  check(compat.objectiveFirst == published, "reinstall preserves the published outer table")
  for _, field in ipairs(fidelity.fields) do
    check(published[field] == identities[field], "reinstall preserves " .. field .. " identity")
    check(next(published[field]) == nil, "reinstall clears prior " .. field .. " contents")
  end
  remove()
  check(rawget(_G, "QuestieLoader") == previousLoader, "reinstall restores the original loader")
end
