-- src/corrections/registry.lua
--
-- Registration, application and recomposition of Corrections.
--
-- Two categories, declared by the author. There is no automatic promotion, and therefore
-- nothing that can misfire:
--
--   Static Correction   folded in during Generation. Never shipped to end users.
--   Dynamic Correction  conditional, or otherwise not knowable before Generation. Applied at
--                       query time through the Correction Overlay.
--
-- Filled in by tickets 09 and 10. Until then this file exists so both read modes have the
-- namespace they expect and a consumer registering early is not silently dropped.

local _, LibQuestieDB = ...

local registry = {
  --- owner -> datatype -> name -> { func = function, loadOrder = number, dynamic = boolean }
  registered = {},
  --- Application order, outermost precedence. Last applied wins.
  appliedOwners = {},
  pending = {},
}

LibQuestieDB.Corrections = registry

return registry
