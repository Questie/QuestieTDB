-- Admit hints from this expansion and earlier expansions only.
local _, LibQuestieDB = ...
local expansions = LibQuestieDB.CorrectionCompat.modules.Expansions
LibQuestieDB.CorrectionCompat.SelectObjectiveFirstScope(expansions.Current >= expansions.Cata)
