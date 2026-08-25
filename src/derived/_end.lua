-- src/derived/_end.lua
--
-- Closes the derived-pass block: publishes the ported library, hands `QuestieLoader` back, and
-- registers the passes.
--
-- Registration is here rather than in each pass file so the running order is stated in one
-- place, the way the correction manifest states load order in one place.

local _, LibQuestieDB = ...

local modules = LibQuestieDB.__derivedModules or {}
LibQuestieDB.RamerDouglasPeucker = modules.RamerDouglasPeucker

_G.QuestieLoader = LibQuestieDB.__derivedPreviousLoader
LibQuestieDB.__derivedPreviousLoader = nil
LibQuestieDB.__derivedModules = nil

local derived = LibQuestieDB.Derived
local requiredRaces = LibQuestieDB.DerivedRequiredRaces
local waypoints = LibQuestieDB.DerivedWaypoints

-- Questie's Initialize infers requiredRaces before MinimalInit and PreCompile. Register only
-- the exact compatibility transcription; ApplyCorrectedInference documents a safer policy but
-- remains unused while matching Questie's shipped database is the contract.
derived.Register({
  name = "requiredRaces:questieCompatibility",
  writes = "Quest",
  reads = { "Quest", "Npc" },
  order = 50,
  run = requiredRaces.ApplyQuestieCompatibility,
})

-- Upstream's PreCompile walks npcData then objectData. Objects only carry waypoints from Cata
-- onward, so the second pass is a no-op on earlier flavors rather than conditional.
derived.Register(waypoints.Spec("Npc", 100))
derived.Register(waypoints.Spec("Object", 110))
