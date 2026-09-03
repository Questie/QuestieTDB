-- generator/rows.lua
--
-- Builds the per-entity Scalar row and Presence mask used by Baked storage.

local normalize = dofile("src/meta/normalize.lua")
local encode = dofile("generator/encode.lua")

local rows = {}

---@param meta table Entity metadata.
---@param sourceRow table Raw composed entity row.
---@param fieldFilter table<string, boolean>? Optional tracer-bullet field selection.
---@return table? scalarRow Scalar values under field-index keys plus `p`, or nil when nothing is stored.
function rows.build(meta, sourceRow, fieldFilter)
  -- Binary64 represents every mask through 2^52 - 1 exactly.
  if meta.fieldCount > 52 then
    error(("%s schema has %d fields; the presence mask supports at most 52")
      :format(meta.entity, meta.fieldCount), 2)
  end

  local scalarRow = {}
  local hasValue = false
  local presence = 0

  for fieldIndex = 1, meta.fieldCount do
    if not fieldFilter or fieldFilter[meta.names[fieldIndex]] then
      local normalized = normalize.field(meta, fieldIndex, sourceRow[fieldIndex])
      if encode.hasStoredValue(meta, fieldIndex, normalized) then
        if meta.types[fieldIndex] == "table" then
          presence = presence + 2 ^ (fieldIndex - 1)
        else
          scalarRow[fieldIndex] = normalized
          hasValue = true
        end
      end
    end
  end

  if presence ~= 0 then
    scalarRow.p = presence
    hasValue = true
  end
  if hasValue then return scalarRow end
  return nil
end

return rows
