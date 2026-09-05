-- Admit only the support variants applicable to this client.
local _, LibQuestieDB = ...
local name = LibQuestieDB.flavor.name
LibQuestieDB.Support.SelectScope(name == "Cata" or name == "Mists")
