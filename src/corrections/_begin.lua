-- src/corrections/_begin.lua
--
-- Opens the correction block: installs the compat shim so the verbatim copies of Questie's
-- correction files can execute. Closed by src/corrections/_end.lua.

local _, LibQuestieDB = ...
LibQuestieDB.CorrectionCompat.Install(LibQuestieDB.flavor)
