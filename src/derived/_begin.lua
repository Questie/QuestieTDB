-- src/derived/_begin.lua
--
-- Opens the derived-pass block: installs a scoped `QuestieLoader` shim so the byte-identical
-- copy of Questie's RamerDouglasPeucker can execute unmodified. Closed by _end.lua.
--
-- Same discipline as the correction and support blocks: the shim exists only for the duration
-- of the block and is handed back afterwards, so nothing leaks into the consumer's environment.

local _, LibQuestieDB = ...

local modules = {}
LibQuestieDB.__derivedModules = modules
LibQuestieDB.__derivedPreviousLoader = rawget(_G, "QuestieLoader")

local function moduleFor(_, name)
  modules[name] = modules[name] or {}
  return modules[name]
end

_G.QuestieLoader = { ImportModule = moduleFor, CreateModule = moduleFor }
