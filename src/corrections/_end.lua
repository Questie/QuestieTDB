-- src/corrections/_end.lua
--
-- Closes the correction block: registers what the manifest describes, then hands
-- `QuestieLoader` back to whoever owned it.
--
-- `Questie` is the one thing the shim leaves behind, deliberately. Correction functions read
-- `Questie.ICON_TYPE_*` and `Questie.Is*` from the **global at apply time**, not captured at
-- load time, so tearing that table down here would leave every Dynamic Correction reading a nil
-- global the moment it ran. The stub only ever fills in fields that are missing, and the
-- consumer's own definitions win as soon as it loads. See src/corrections/compat.lua.

local _, LibQuestieDB = ...

local compat = LibQuestieDB.CorrectionCompat
local modules = compat.modules or {}

LibQuestieDB.CorrectionRegister.FromManifest(LibQuestieDB.flavor, function(name)
  return modules[name]
end)

-- Objective-ordering hints are consumer information, not entity data, so they are published
-- rather than merged into the database.
LibQuestieDB.ObjectiveFirst = compat.objectiveFirst

compat.Remove()
