-- src/derived/registry.lua
--
-- Derived Passes: deterministic transforms over corrected entity data, run before storage,
-- in both Generation and Source mode. See docs/adr/0004-derived-passes.md.
--
-- A Correction is data (`id -> fieldIndex -> value`); a Derived Pass is code, and may read
-- one entity type while writing another. Questie runs several of these between loading
-- corrections and compiling, and because they are not correction *files*, the byte-copy port
-- never saw them — which is the defect class this module exists to close.
--
-- ## Where passes run
--
--   Generation / verify / reconstruct   generator/flavor.lua, after corrections.applyStatic
--   Source mode                         src/read/source.lua materialize(), after
--                                       ApplyStaticToEntities and before Freeze
--   Baked mode                          nowhere — Generation already applied them
--
-- That is the same seam Static Corrections already share, widened rather than duplicated.
--
-- ## Ordering is load-bearing
--
--   raw data -> Static Corrections -> Derived Passes -> normalize (40.90 grid) -> encode
--
-- Passes see corrected *raw* values, before quantization. Questie transforms raw float
-- coordinates and quantizes afterwards; quantization is deliberately non-idempotent
-- (ADR 0003 D1), so quantize-then-transform cannot be recovered.

local _, LibQuestieDB = ...

local derived = {}

local type, ipairs, pairs = type, ipairs, pairs
local sort, format = table.sort, string.format

local VALID_TYPES = { Quest = true, Npc = true, Item = true, Object = true }

--- Registered passes, in declaration order; `Select` sorts by `order`.
derived.passes = {}

--- Register one pass.
---
--- Declared, never inferred — the same rule the correction manifest follows, and for the same
--- reason: a category guessed from file layout is a category that will eventually be wrong.
---
---@param spec table {
---   name   = string,            unique, appears in error messages
---   writes = "Npc",             the entity type this pass mutates
---   reads  = { "Npc" },         types that must be materialized first; may include `writes`
---   order  = 100,               ascending within a run
---   run    = function(ctx),     ctx.entities(type), ctx.meta(type), ctx.flavor
--- }
function derived.Register(spec)
  if type(spec) ~= "table" then error("Derived.Register: spec must be a table", 2) end
  if type(spec.name) ~= "string" or spec.name == "" then
    error("Derived.Register: name must be a non-empty string", 2)
  end
  if not VALID_TYPES[spec.writes] then
    error(format("Derived.Register(%s): writes must be Quest, Npc, Item or Object - got %s",
      spec.name, tostring(spec.writes)), 2)
  end
  if type(spec.run) ~= "function" then
    error(format("Derived.Register(%s): run must be a function", spec.name), 2)
  end
  if spec.order ~= nil and type(spec.order) ~= "number" then
    error(format("Derived.Register(%s): order must be a number or nil", spec.name), 2)
  end
  for _, readType in ipairs(spec.reads or {}) do
    if not VALID_TYPES[readType] then
      error(format("Derived.Register(%s): reads names an unknown type %s",
        spec.name, tostring(readType)), 2)
    end
  end
  for _, existing in ipairs(derived.passes) do
    if existing.name == spec.name then
      error(format("Derived.Register: duplicate pass name %s", spec.name), 2)
    end
  end

  derived.passes[#derived.passes + 1] = {
    name = spec.name,
    writes = spec.writes,
    reads = spec.reads or { spec.writes },
    order = spec.order or (#derived.passes + 1) * 100,
    run = spec.run,
    expansions = spec.expansions,
  }

  -- A cross-type cycle would make Source mode read a half-built table through the
  -- re-entrancy guard rather than fail, so it is rejected here instead of discovered later.
  local cycle = derived.FindCycle()
  if cycle then
    derived.passes[#derived.passes] = nil
    error(format("Derived.Register(%s): would create a dependency cycle: %s",
      spec.name, cycle), 2)
  end
end

--- Cross-type dependency cycle, as a printable path, or nil.
---
--- A pass reading the type it writes is not a cycle — that is the ordinary case. Only edges
--- between *different* types can deadlock materialization.
function derived.FindCycle()
  local edges = {}
  for _, pass in ipairs(derived.passes) do
    for _, readType in ipairs(pass.reads) do
      if readType ~= pass.writes then
        edges[pass.writes] = edges[pass.writes] or {}
        edges[pass.writes][readType] = true
      end
    end
  end

  local state, path = {}, {}
  local function visit(node)
    if state[node] == "open" then
      path[#path + 1] = node
      return true
    end
    if state[node] == "done" then return false end
    state[node] = "open"
    path[#path + 1] = node
    for next_ in pairs(edges[node] or {}) do
      if visit(next_) then return true end
    end
    state[node] = "done"
    path[#path] = nil
    return false
  end

  for node in pairs(edges) do
    if state[node] == nil then
      path = {}
      if visit(node) then return table.concat(path, " -> ") end
    end
  end
  return nil
end

--- Passes that write `typeName`, in order. With no argument, every pass.
function derived.Select(typeName)
  local selected = {}
  for _, pass in ipairs(derived.passes) do
    if typeName == nil or pass.writes == typeName then selected[#selected + 1] = pass end
  end
  sort(selected, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  return selected
end

local function applies(pass, flavor)
  if not flavor or not pass.expansions then return true end
  return pass.expansions[flavor.expansion] == true
end

--- Run passes and return how many ran.
---
---@param typeName string? Restrict to passes writing this type; nil runs every pass
---@param ctx table { entities = fun(type):table, meta = fun(type):table, flavor = table? }
function derived.Run(typeName, ctx)
  local ran = 0
  for _, pass in ipairs(derived.Select(typeName)) do
    if applies(pass, ctx.flavor) then
      -- Pull read-dependencies first. Offline this is a table lookup; in Source mode it is
      -- materialize(), which is why the dependency is declared rather than discovered.
      for _, readType in ipairs(pass.reads) do
        if readType ~= pass.writes then ctx.entities(readType) end
      end
      pass.run(ctx)
      ran = ran + 1
    end
  end
  return ran
end

if LibQuestieDB then
  LibQuestieDB.Derived = derived
end

return derived
