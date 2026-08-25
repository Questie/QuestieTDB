---@diagnostic disable: unused-local

-- These names mirror common Questie declarations. QuestieTDB's helper types must coexist
-- without relying on file-local duplicate-diagnostic suppression.
---@alias QuestId number
---@alias NpcId number
---@alias ItemId number
---@alias ObjectId number
---@alias ZoneId number
---@alias FactionId number
---@alias SkillId number
---@alias StartedBy {[1]: NpcId[]?, [2]: ObjectId[]?, [3]: ItemId[]?}
---@alias SkillPair {[1]: SkillId, [2]: number}
---@alias ReputationPair {[1]: FactionId, [2]: number}

-- Literal arguments must select one concrete GetAllIds result shape.
---@type QuestieTDBQuestId
local questId = QuestDB.GetAllIds()[1]
---@type QuestieTDBQuestId
local questIdFromFalse = QuestDB.GetAllIds(false)[1]
---@type true
local questPresent = QuestDB.GetAllIds(true)[1]

---@type QuestieTDBNpcId
local npcId = NpcDB.GetAllIds()[1]
---@type QuestieTDBNpcId
local npcIdFromFalse = NpcDB.GetAllIds(false)[1]
---@type true
local npcPresent = NpcDB.GetAllIds(true)[1]

---@type QuestieTDBItemId
local itemId = ItemDB.GetAllIds()[1]
---@type QuestieTDBItemId
local itemIdFromFalse = ItemDB.GetAllIds(false)[1]
---@type true
local itemPresent = ItemDB.GetAllIds(true)[1]

---@type QuestieTDBObjectId
local objectId = ObjectDB.GetAllIds()[1]
---@type QuestieTDBObjectId
local objectIdFromFalse = ObjectDB.GetAllIds(false)[1]
---@type true
local objectPresent = ObjectDB.GetAllIds(true)[1]

-- Representative reads cover nilability and nested tuple aliases.
---@type string?
local questName = QuestDB.name(2)
---@type QuestieTDBExtraObjective[]?
local extraObjectives = QuestDB.extraObjectives(2)
---@type QuestieTDBReference
local itemReference = { "item", 6948 }

-- Correction methods are dot-called. Registrar methods already bind their owner.
---@type QuestieTDBCorrectionProvider
local correctionProvider = function()
  return { [2] = { [1] = "Sharptalon's Claw" } }
end

local registrar = LibQuestieDB.GetRegistrar("ConsumerAddon")
---@type QuestieTDBCorrectionEntry
local correctionEntry = registrar.RegisterRuntimeCorrection(
  "quest", "rename-quest", correctionProvider, 10)
---@type integer
local registrationSequence = correctionEntry.sequence
---@type integer
local applied = registrar.Apply()
---@type boolean
local removed = LibQuestieDB.Corrections.UnregisterCorrection(
  "ConsumerAddon", "Quest", "rename-quest")
---@type integer
local parameterized = LibQuestieDB.Corrections.ApplyParameterized(
  "LoadDarkmoonFixes", "Elwynn")
---@type QuestieTDBCanonicalDatatype?
local canonical = LibQuestieDB.Corrections.CanonicalDatatype("quest")
LibQuestieDB.Corrections.debug = true
