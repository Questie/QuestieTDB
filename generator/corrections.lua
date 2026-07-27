-- generator/corrections.lua
--
-- Static Corrections are folded into the TOC metadata store during Generation and never ship
-- to end users. Source mode applies them to base data through this same path, so "what I see
-- in dev is what ships" follows from shared code rather than from a test.
--
-- The registry itself lives in src/corrections/registry.lua and is shared with the runtime;
-- this file is the offline driver that loads QuestieTDB's own correction files, asks the
-- registry for the Static ones, and applies them to the loaded entity tables.

local corrections = {}

--- Apply every Static Correction owned by QuestieTDB to a set of loaded entity tables.
---
--- The generator runs offline with only QuestieTDB present, so it can only ever bake
--- corrections owned by QuestieTDB. Anything registered by Questie or a third party is
--- Dynamic by definition, and this is enforced rather than trusted to convention.
---
---@param loaded table entityTypeName -> { meta = table, entities = table, path = string }
---@param flavor table An entry from config.flavors
---@return number applied Number of (entity, field) values written
function corrections.applyStatic(loaded, flavor)
  local registry = corrections.registry
  if not registry then
    -- Ticket 09 wires the registry in. Until then Generation is a pure pass-through of raw
    -- entity data, which is exactly what the tracer bullet and the round-trip verifier need.
    return 0
  end
  return registry.ApplyStaticTo(loaded, flavor)
end

return corrections
