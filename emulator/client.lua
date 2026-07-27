-- emulator/client.lua
--
-- The minimum WoW client environment a QuestieTDB addon file needs to load offline.
--
-- Kept separate from emulator/metadata.lua because the two answer different questions: that
-- file stands in for the addon-metadata API, this one stands in for the client. Source mode
-- needs the client (`WOW_PROJECT_ID` selects which expansion's data to keep, `CreateFrame`
-- backs the mode indicator); baked mode needs only the metadata.

local client = {}

local function noop() end

--- Blizzard's project IDs, by the expansion directory name QuestieTDB uses.
client.projectIds = {
  Classic = 2,
  TBC = 5,
  Wotlk = 11,
  Cata = 14,
  MoP = 19,
}

local function stubFrame()
  local frame = {}
  local methods = {
    SetSize = noop, SetPoint = noop, SetMovable = noop, EnableMouse = noop,
    RegisterForDrag = noop, SetScript = noop, SetClampedToScreen = noop,
    Show = noop, Hide = noop, StartMoving = noop, StopMovingOrSizing = noop,
    RegisterEvent = noop, UnregisterEvent = noop, SetAllPoints = noop, SetText = noop,
  }
  for name, fn in pairs(methods) do frame[name] = fn end
  frame.CreateFontString = function()
    return { SetAllPoints = noop, SetText = noop, SetPoint = noop, SetTextColor = noop }
  end
  return frame
end

--- Install client globals. Call before loading an addon TOC.
---@param opts table? { expansion = "Classic" }
function client.install(opts)
  opts = opts or {}

  _G.WOW_PROJECT_CLASSIC = 2
  _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
  _G.WOW_PROJECT_WRATH_CLASSIC = 11
  _G.WOW_PROJECT_CATACLYSM_CLASSIC = 14
  _G.WOW_PROJECT_MISTS_CLASSIC = 19
  _G.WOW_PROJECT_MAINLINE = 1

  _G.WOW_PROJECT_ID = client.projectIds[opts.expansion or "Classic"]

  _G.UIParent = _G.UIParent or stubFrame()
  _G.CreateFrame = function() return stubFrame() end
  _G.GetLocale = function() return opts.locale or "enUS" end
  _G.hooksecurefunc = noop
  _G.tinsert = table.insert
  _G.tremove = table.remove
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.C_Timer = { After = function(_, fn) if fn then fn() end end, NewTicker = noop }
  _G.C_Seasons = { HasActiveSeason = function() return false end, GetActiveSeason = function() return 0 end }

  return _G
end

--- Undo the parts of the environment that would leak between two loads in one process.
--- `QuestieLoader` matters most: source mode installs a shim over it and hands it back, so a
--- stale one left behind would silently swallow the next load's payloads.
function client.reset()
  _G.QuestDB, _G.NpcDB, _G.ItemDB, _G.ObjectDB = nil, nil, nil, nil
  _G.LibQuestieDB = nil
  _G.QuestieLoader = nil
  _G.QuestieTDBSourceModeIndicator = nil
end

return client
