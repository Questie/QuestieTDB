-- data/Wotlk/_flavor.lua
--
-- Marks the start of Wotlk's raw entity data in the base TOC's file list. The loader shim in
-- src/read/source.lua keeps a payload only while this matches the running client, so the base
-- TOC can list all five expansions without a client paying for four of them.

local _, LibQuestieDB = ...
LibQuestieDB.__loadingExpansion = "Wotlk"
