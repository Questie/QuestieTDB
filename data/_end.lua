-- data/_end.lua
--
-- Closes the raw entity data block: stops capturing and hands `QuestieLoader` back to whoever
-- owned it, so the consumer's own loader is untouched.

local _, LibQuestieDB = ...
LibQuestieDB.__loadingExpansion = nil
if LibQuestieDB.read and LibQuestieDB.read.source then
  LibQuestieDB.read.source.RemoveLoaderShim()
end
