-- tools/differential/dump_value.lua
--
-- Selects the coordinate view for QuestieTDB differential dumps. Default callers, including
-- Golden snapshots, observe raw production values. The compiler differential explicitly asks
-- for the legacy view, where base coordinates are projected onto Questie's compiler grid while
-- Dynamic Correction values remain raw because they bypassed compilation in Questie.

local dumpValue = {}

---Build the value adapter for one dump invocation.
---@param comparisonMode string|nil Nil for raw values, or `--compiler-coordinates`.
---@return fun(meta: table, fieldIndex: number, value: any, overlayRow: table|nil): any adapt
function dumpValue.forMode(comparisonMode)
  assert(comparisonMode == nil or comparisonMode == "--compiler-coordinates",
    "unknown comparison mode " .. tostring(comparisonMode))

  if comparisonMode == nil then
    return function(_, _, value)
      return value
    end
  end

  local compilerCoordinates = dofile("tools/differential/compiler_coordinates.lua")
  return function(meta, fieldIndex, value, overlayRow)
    local fromOverlay = overlayRow ~= nil and overlayRow[fieldIndex] ~= nil
    return compilerCoordinates.adaptField(meta, fieldIndex, value, fromOverlay)
  end
end

return dumpValue
