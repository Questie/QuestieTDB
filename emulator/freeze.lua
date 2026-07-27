-- emulator/freeze.lua
--
-- A pure-Lua stand-in for `table.freeze`, so the ownership guard is present in CI rather than
-- silently absent.
--
-- ## What the client does, and what Lua 5.1 can manage
--
-- `table.freeze` in the WoW client is a VM-level flag, not a metatable proxy: reads are
-- completely unaffected, `rawset` is blocked, `getmetatable` still returns nil, and **every**
-- write raises — including one that overwrites a key the table already has.
--
-- Standard Lua 5.1 has no such flag. The only interception point is `__newindex`, and
-- `__newindex` fires only when the key is *absent*. So the substitute catches:
--
--   frozen[newKey] = v      -> raises          (appending, aliasing a query result onto an object)
--   frozen[existing] = v    -> NOT intercepted (overwriting, and `= nil` deletion)
--
-- The missed case is the important one: `QuestieDB.GetQuest` writes `creatureObjective[3] = nil`
-- into its query results, and that is a write to an existing key. A prevention-only substitute
-- would report a clean run over exactly the mutation `DESIGN.md` expects freezing to surface.
--
-- A proxy table would intercept everything, but `pairs`, `next` and `#` do not route through
-- `__index` in Lua 5.1, so a proxy would present every frozen table as empty to any consumer
-- that iterates it. That trades a real hole for a much larger one.
--
-- ## Prevention plus detection
--
-- So the harness does both:
--
--   * `__newindex` **prevents** new-key writes, raising immediately with the call site intact.
--   * `freeze.audit()` **detects** overwrites and deletions after the fact, by fingerprinting
--     each table when it is frozen and re-walking at the end of a run.
--
-- In the client, prevention covers both cases and the audit is unnecessary. Offline, the two
-- together cover what the client covers, with the overwrite case reported at the end of the
-- run rather than at the moment it happens. `verify.lua --freeze` and
-- `equivalence.lua --freeze` run the audit.
--
-- Cost: one metatable and one fingerprint per frozen table, against the client's measured
-- 0 KiB. That is why this is opt-in rather than always on.

local freeze = {}

local type, pairs, next, tostring = type, pairs, next, tostring
local setmetatable, getmetatable, rawget = setmetatable, getmetatable, rawget

-- Weak keys throughout: freezing a table must not keep it alive.
local frozen = setmetatable({}, { __mode = "k" })
local fingerprints = setmetatable({}, { __mode = "k" })
local serials = setmetatable({}, { __mode = "k" })
local nextSerial = 0

local function refuse(_, key)
  error(("attempted to perform indexed assignment on a frozen table (key %s). " ..
         "QuestieTDB owns the values it returns; take an explicit copy to modify one.")
    :format(tostring(key)), 2)
end

local FROZEN_META = { __newindex = refuse }

--- A stable identity for a value, so a fingerprint can span nested tables without recursing.
local function identity(value)
  local valueType = type(value)
  if valueType ~= "table" then return valueType .. ":" .. tostring(value) end
  local serial = serials[value]
  if not serial then
    nextSerial = nextSerial + 1
    serial = nextSerial
    serials[value] = serial
  end
  return "t:" .. serial
end

--- Order-independent shallow fingerprint. Summing per-pair hashes means `pairs` order — which
--- is not stable in Lua — cannot make an unchanged table look changed.
local function fingerprint(tbl)
  local sum, count = 0, 0
  for key, value in pairs(tbl) do
    count = count + 1
    local pair = identity(key) .. "=" .. identity(value)
    local hash = 5381
    for i = 1, #pair do
      hash = (hash * 33 + pair:byte(i)) % 4294967291
    end
    sum = (sum + hash) % 4294967291
  end
  return count * 4294967291 + sum
end

--------------------------------------------------------------------------------------------
-- Freezing
--------------------------------------------------------------------------------------------

--- Freeze one table. Returns it, so it can be used inline. Re-freezing is a no-op.
function freeze.freeze(tbl)
  if type(tbl) ~= "table" then return tbl end
  if frozen[tbl] then return tbl end
  frozen[tbl] = true
  fingerprints[tbl] = fingerprint(tbl)
  -- Never replace a metatable the value already carries; a redirecting `__newindex` is exactly
  -- the trap this design forbids, and silently overwriting one would hide it.
  if getmetatable(tbl) == nil then
    setmetatable(tbl, FROZEN_META)
  end
  return tbl
end

function freeze.isFrozen(tbl)
  return frozen[tbl] == true
end

--------------------------------------------------------------------------------------------
-- Audit
--------------------------------------------------------------------------------------------

--- Re-walk every frozen table and report the ones whose contents changed.
---
--- This is what catches an overwrite or a `= nil` deletion, which `__newindex` cannot see.
---@return number changed
---@return table report list of { table = tbl, was = number, now = number }
function freeze.audit()
  local changed, report = 0, {}
  for tbl in pairs(frozen) do
    local was = fingerprints[tbl]
    local now = fingerprint(tbl)
    if was ~= now then
      changed = changed + 1
      if #report < 20 then
        report[#report + 1] = { table = tbl, was = was, now = now }
      end
      fingerprints[tbl] = now -- report each change once
    end
  end
  return changed, report
end

function freeze.count()
  local n = 0
  for _ in pairs(frozen) do n = n + 1 end
  return n
end

--- Forget everything, so two loads in one process do not audit each other's tables.
function freeze.reset()
  frozen = setmetatable({}, { __mode = "k" })
  fingerprints = setmetatable({}, { __mode = "k" })
end

--------------------------------------------------------------------------------------------
-- Installation
--------------------------------------------------------------------------------------------

--- Install as the freeze implementation on a loaded addon.
function freeze.install(LibQuestieDB)
  LibQuestieDB.shared.SetFreezeImplementation(freeze.freeze)
  LibQuestieDB.shared.SetIsFrozenImplementation(freeze.isFrozen)
  return freeze
end

return freeze
