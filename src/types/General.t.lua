---@meta _

--------------------------------------------------------------------------------
-- Public primitives
--------------------------------------------------------------------------------

---@alias QuestieTDBQuestId number
---@alias QuestieTDBNpcId number
---@alias QuestieTDBItemId number
---@alias QuestieTDBObjectId number
---@alias QuestieTDBZoneId number
---@alias QuestieTDBFactionId number
---@alias QuestieTDBSkillId number

---@alias QuestieTDBCanonicalDatatype "Quest"|"Npc"|"Item"|"Object"
---@alias QuestieTDBDatatype QuestieTDBCanonicalDatatype|"quest"|"npc"|"item"|"object"
---@alias QuestieTDBReadMode "source"|"baked"

---@alias QuestieTDBQuestField "name"|"startedBy"|"finishedBy"|"requiredLevel"|"questLevel"|"requiredRaces"|"requiredClasses"|"objectivesText"|"triggerEnd"|"objectives"|"sourceItemId"|"preQuestGroup"|"preQuestSingle"|"childQuests"|"inGroupWith"|"exclusiveTo"|"zoneOrSort"|"requiredSkill"|"requiredMinRep"|"requiredMaxRep"|"requiredSourceItems"|"nextQuestInChain"|"questFlags"|"specialFlags"|"parentQuest"|"reputationReward"|"breadcrumbForQuestId"|"breadcrumbs"|"extraObjectives"|"requiredSpell"|"requiredSpecialization"|"requiredMaxLevel"|"availableUntilCompleted"|"availableStartingWith"|"requiredRanks"|"disabledByQuest"
---@alias QuestieTDBNpcField "name"|"minLevelHealth"|"maxLevelHealth"|"minLevel"|"maxLevel"|"rank"|"spawns"|"waypoints"|"zoneID"|"questStarts"|"questEnds"|"factionID"|"friendlyToFaction"|"subName"|"npcFlags"
---@alias QuestieTDBItemField "name"|"npcDrops"|"objectDrops"|"itemDrops"|"startQuest"|"questRewards"|"flags"|"foodType"|"itemLevel"|"requiredLevel"|"ammoType"|"class"|"subClass"|"vendors"|"relatedQuests"|"teachesSpell"
---@alias QuestieTDBObjectField "name"|"questStarts"|"questEnds"|"spawns"|"zoneID"|"factionID"|"waypoints"

--------------------------------------------------------------------------------
-- Shared read shapes
--------------------------------------------------------------------------------

---@alias QuestieTDBCoordinate {[1]: number, [2]: number, [3]: number?} Coordinates plus an optional phase.
---@alias QuestieTDBWaypoint {[1]: number, [2]: number} A waypoint never carries a phase.
---@alias QuestieTDBSpawnList table<QuestieTDBZoneId, QuestieTDBCoordinate[]>
---@alias QuestieTDBWaypointList table<QuestieTDBZoneId, QuestieTDBWaypoint[][]>

---@alias QuestieTDBStartedBy {[1]: QuestieTDBNpcId[]?, [2]: QuestieTDBObjectId[]?, [3]: QuestieTDBItemId[]?}
---@alias QuestieTDBFinishedBy {[1]: QuestieTDBNpcId[]?, [2]: QuestieTDBObjectId[]?}

---@alias QuestieTDBSkillPair {[1]: QuestieTDBSkillId, [2]: number}
---@alias QuestieTDBSkillRankPair {[1]: QuestieTDBSkillId, [2]: number}
---@alias QuestieTDBReputationPair {[1]: QuestieTDBFactionId, [2]: number}

---@alias QuestieTDBCreatureObjective {[1]: QuestieTDBNpcId, [2]: string?, [3]: number}
---@alias QuestieTDBObjectObjective {[1]: QuestieTDBObjectId, [2]: string?, [3]: number}
---@alias QuestieTDBItemObjective {[1]: QuestieTDBItemId, [2]: string?, [3]: number}
---@alias QuestieTDBKillCreditObjective {[1]: QuestieTDBNpcId[], [2]: QuestieTDBNpcId, [3]: string?, [4]: number}
---@alias QuestieTDBSpellObjective {[1]: number, [2]: string?, [3]: QuestieTDBItemId}
---@alias QuestieTDBObjectives {[1]: QuestieTDBCreatureObjective[]?, [2]: QuestieTDBObjectObjective[]?, [3]: QuestieTDBItemObjective[]?, [4]: QuestieTDBReputationPair?, [5]: QuestieTDBKillCreditObjective[]?, [6]: QuestieTDBSpellObjective[]?}

---@alias QuestieTDBTrigger {[1]: string, [2]: QuestieTDBSpawnList}
---@alias QuestieTDBReference
---| {[1]: "monster", [2]: QuestieTDBNpcId}
---| {[1]: "item", [2]: QuestieTDBItemId}
---| {[1]: "object", [2]: QuestieTDBObjectId}
---@alias QuestieTDBExtraObjective {[1]: QuestieTDBSpawnList?, [2]: number, [3]: string?, [4]: number, [5]: QuestieTDBReference[]?}

---@class QuestieTDBPackedValues
---@field n integer Number of requested fields, including nil slots.
---@field [integer] any

--------------------------------------------------------------------------------
-- Corrections
--------------------------------------------------------------------------------

---@alias QuestieTDBCorrectionFields table<integer, any>
---@alias QuestieTDBCorrections table<number, QuestieTDBCorrectionFields>
---@alias QuestieTDBCorrectionProvider fun(): QuestieTDBCorrections

---@class QuestieTDBCorrectionEntry
---@field owner string
---@field datatype QuestieTDBCanonicalDatatype
---@field name string
---@field func QuestieTDBCorrectionProvider
---@field loadOrder number
---@field sequence integer Registration order used to break load-order ties.
---@field dynamic boolean
---@field expansions table<string, boolean>? Expansion allow-list for built-in correction sets.
---@field minExpansionOrder number? Earliest expansion for a built-in correction set.
---@field sourceExpansionOrder number? Source expansion used when adapting built-in options.
---@field options table<string, any>? Options passed to built-in correction sets.

---@class QuestieTDBRegistrar
---@field owner string
---@field RegisterCorrection fun(datatype: QuestieTDBDatatype, name: string, func: QuestieTDBCorrectionProvider, loadOrder?: number): QuestieTDBCorrectionEntry
---@field RegisterRuntimeCorrection fun(datatype: QuestieTDBDatatype, name: string, func: QuestieTDBCorrectionProvider, loadOrder?: number): QuestieTDBCorrectionEntry
---@field Apply fun(): integer

---@class QuestieTDBCorrectionsAPI
---@field OWNER string QuestieTDB's correction owner name.
---@field debug boolean Log when one owner overrides another on the same field.
---@field CanonicalDatatype fun(datatype: QuestieTDBDatatype): QuestieTDBCanonicalDatatype? Normalize a supported datatype spelling.
---@field RegisterCorrection fun(owner: string, datatype: QuestieTDBDatatype, name: string, func: QuestieTDBCorrectionProvider, loadOrder?: number): QuestieTDBCorrectionEntry
---@field RegisterRuntimeCorrection fun(owner: string, datatype: QuestieTDBDatatype, name: string, func: QuestieTDBCorrectionProvider, loadOrder?: number): QuestieTDBCorrectionEntry
---@field UnregisterCorrection fun(owner: string, datatype: QuestieTDBDatatype, name: string): boolean
---@field GetRegistrar fun(owner: string): QuestieTDBRegistrar
---@field ApplyRegisteredCorrections fun(owner?: string): integer
---@field GetProvenance fun(datatype: QuestieTDBDatatype, id: number, key: string|integer): string?
---@field GetOwners fun(): string[]
