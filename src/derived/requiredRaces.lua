-- src/derived/requiredRaces.lua
--
-- Temporary Derived Pass for Questie's requiredRaces inference. Questie runs this rule after
-- Static Corrections and before compiling; QuestieTDB must run it over the same corrected raw
-- Quest and Npc tables to preserve the current read contract. Explicit correction data remains
-- the proper representation, tracked by https://github.com/Questie/QuestieTDB/issues/1.
--
-- The active function is a behavioral transcription, including upstream's unsafe guesses. The
-- corrected function beside it is deliberately unused: it records the conservative policy we
-- would prefer, but changing results while Questie still uses the old rule would break parity.
-- The duplicated loops keep those policy differences reviewable without a shared helper hiding
-- them. SoD-only gaps are explicit owned rows in corrections/Sod/sodRequiredRaces.lua;
-- they use normal Dynamic Corrections rather than another inference pass (issue #13).

local _, LibQuestieDB = ...

local next, pairs, type = next, pairs, type

local requiredRaces = {}

---@class RequiredRacesDerivedContext
---@field flavor table Active flavor; `expansion` selects its symbolic race masks.
---@field entities fun(entityType: string): table? Corrected raw rows by entity type.
---@field meta fun(entityType: string): table? Materialized schema by entity type.

---Applies Questie's requiredRaces inference exactly, quirks included.
---This is the compatibility implementation registered as the active Derived Pass.
---@param ctx RequiredRacesDerivedContext
---@return nil
function requiredRaces.ApplyQuestieCompatibility(ctx)
  local quests = ctx.entities("Quest")
  if not quests then return end
  local npcs = ctx.entities("Npc")
  if not npcs then
    error("requiredRaces pass: Npc data is required when Quest data is materialized", 0)
  end

  local questMeta = ctx.meta("Quest")
  local npcMeta = ctx.meta("Npc")
  local questKeys = questMeta and questMeta.keys
  local npcKeys = npcMeta and npcMeta.keys
  local expansion = ctx.flavor and ctx.flavor.expansion
  local enum = LibQuestieDB and LibQuestieDB.Enum
  local expansionEnums = enum and enum.byExpansion and enum.byExpansion[expansion]
  if not questKeys or not npcKeys or not expansionEnums or not expansionEnums.raceKeys then
    error("requiredRaces pass: Quest/Npc schema and flavor race masks must be available", 0)
  end
  local raceKeys = expansionEnums.raceKeys

  -- Keep this loop aligned with QuestieCorrections:Initialize. Missing NPCs and unknown
  -- faction values are ignored, and only creature starters participate in the guess.
  for _, quest in pairs(quests) do
    if (not quest[questKeys.requiredRaces]) or quest[questKeys.requiredRaces] == 0 then
      local canHorde = false
      local canAlliance = false
      local starts = quest[questKeys.startedBy]
      if starts then
        starts = starts[1]
        if starts then
          for _, id in pairs(starts) do
            local npc = npcs[id]
            if npc then
              local friendly = npc[npcKeys.friendlyToFaction]
              if friendly then
                if friendly == "H" then
                  canHorde = true
                elseif friendly == "A" then
                  canAlliance = true
                elseif friendly == "AH" then
                  canAlliance = true
                  canHorde = true
                end
              end
            end
          end
        end
        if canAlliance ~= canHorde then
          if canAlliance then
            quest[questKeys.requiredRaces] = raceKeys.ALL_ALLIANCE
          else
            quest[questKeys.requiredRaces] = raceKeys.ALL_HORDE
          end
        end
      end
    end
  end
end

---Applies the conservative requiredRaces policy we would prefer for incomplete data.
---This remains unregistered while Questie parity is the contract. Unlike the compatibility
---rule, it preserves an explicit zero, rejects non-creature access paths, and infers only when
---every creature starter resolves to the same faction-exclusive value.
---@param ctx RequiredRacesDerivedContext
---@return nil
function requiredRaces.ApplyCorrectedInference(ctx)
  local quests = ctx.entities("Quest")
  if not quests then return end
  local npcs = ctx.entities("Npc")
  if not npcs then
    error("requiredRaces pass: Npc data is required when Quest data is materialized", 0)
  end

  local questMeta = ctx.meta("Quest")
  local npcMeta = ctx.meta("Npc")
  local questKeys = questMeta and questMeta.keys
  local npcKeys = npcMeta and npcMeta.keys
  local expansion = ctx.flavor and ctx.flavor.expansion
  local enum = LibQuestieDB and LibQuestieDB.Enum
  local expansionEnums = enum and enum.byExpansion and enum.byExpansion[expansion]
  if not questKeys or not npcKeys or not expansionEnums or not expansionEnums.raceKeys then
    error("requiredRaces pass: Quest/Npc schema and flavor race masks must be available", 0)
  end
  local raceKeys = expansionEnums.raceKeys

  -- Keep this policy beside the compatibility loop. Its stricter evidence requirements are
  -- intentional and must not leak into the active pass one condition at a time.
  for _, quest in pairs(quests) do
    if quest[questKeys.requiredRaces] == nil then
      local starts = quest[questKeys.startedBy]
      local creatureStarters = starts and starts[1]
      local evidenceIsComplete = type(creatureStarters) == "table" and
                                 next(creatureStarters) ~= nil

      if evidenceIsComplete then
        for starterType, starterIds in pairs(starts) do
          if starterType ~= 1 and
             (type(starterIds) ~= "table" or next(starterIds) ~= nil) then
            evidenceIsComplete = false
            break
          end
        end
      end

      local faction
      if evidenceIsComplete then
        for _, id in pairs(creatureStarters) do
          local npc = npcs[id]
          local friendly = npc and npc[npcKeys.friendlyToFaction]
          if friendly ~= "A" and friendly ~= "H" then
            evidenceIsComplete = false
            break
          end
          if faction and faction ~= friendly then
            evidenceIsComplete = false
            break
          end
          faction = friendly
        end
      end

      if evidenceIsComplete and faction == "A" then
        quest[questKeys.requiredRaces] = raceKeys.ALL_ALLIANCE
      elseif evidenceIsComplete and faction == "H" then
        quest[questKeys.requiredRaces] = raceKeys.ALL_HORDE
      end
    end
  end
end

if LibQuestieDB then
  LibQuestieDB.DerivedRequiredRaces = requiredRaces
end

return requiredRaces
