---@meta _

---@class NpcDB
---@field name fun(id: QuestieTDBNpcId): string? NPC name.
---@field minLevelHealth fun(id: QuestieTDBNpcId): number? Deprecated. Returns placeholder `0` for a known NPC; health is no longer stored.
---@field maxLevelHealth fun(id: QuestieTDBNpcId): number? Deprecated. Returns placeholder `1` for a known NPC; health is no longer stored.
---@field minLevel fun(id: QuestieTDBNpcId): number? Minimum NPC level.
---@field maxLevel fun(id: QuestieTDBNpcId): number? Maximum NPC level.
---@field rank fun(id: QuestieTDBNpcId): number? NPC rank.
---@field spawns fun(id: QuestieTDBNpcId): QuestieTDBSpawnList? Spawn coordinates grouped by zone.
---@field waypoints fun(id: QuestieTDBNpcId): QuestieTDBWaypointList? Waypoint paths grouped by zone.
---@field zoneID fun(id: QuestieTDBNpcId): QuestieTDBZoneId? Most common zone.
---@field questStarts fun(id: QuestieTDBNpcId): QuestieTDBQuestId[]? Quests started by this NPC.
---@field questEnds fun(id: QuestieTDBNpcId): QuestieTDBQuestId[]? Quests finished at this NPC.
---@field factionID fun(id: QuestieTDBNpcId): QuestieTDBFactionId? Faction ID.
---@field friendlyToFaction fun(id: QuestieTDBNpcId): "A"|"H"|"AH"? Friendly player factions.
---@field subName fun(id: QuestieTDBNpcId): string? NPC subname.
---@field npcFlags fun(id: QuestieTDBNpcId): number? NPC flag bitmask.
---@field GetByIndex fun(id: QuestieTDBNpcId, fieldIndex: integer): any Read a field by positional index.
---@field Get fun(id: QuestieTDBNpcId, key: QuestieTDBNpcField|integer): any Read a field by canonical name or index.
---@field GetAll fun(id: QuestieTDBNpcId, keys: (QuestieTDBNpcField|integer)[]): QuestieTDBPackedValues? Read fields into a packed table, or nil for an unknown ID.
---@field GetRaw fun(id: QuestieTDBNpcId, key: QuestieTDBNpcField|integer): any Read base data without Corrections or localization.
---@field Exists fun(id: QuestieTDBNpcId): boolean Test the composed view.
---@field InvalidateCache fun(id?: QuestieTDBNpcId) Drop cached fields for one NPC or every NPC.
---@field BuildNameIndex fun() Build the Name index now (a no-op when it exists) instead of on the first IdsByName call; a full pass over every NPC name.
---@field IdsByName fun(name: string): QuestieTDBNpcId[]? Every composed NPC ID whose current name equals `name` exactly, ascending, or nil; shared and read-only.
NpcDB = {}

---Deprecated compatibility getter. Health is no longer stored.
---@deprecated
---@param id QuestieTDBNpcId
---@return number? health Placeholder `0` for a known NPC; `nil` for an unknown ID.
function NpcDB.minLevelHealth(id) end

---Deprecated compatibility getter. Health is no longer stored.
---@deprecated
---@param id QuestieTDBNpcId
---@return number? health Placeholder `1` for a known NPC; `nil` for an unknown ID.
function NpcDB.maxLevelHealth(id) end

---Returns the composed ID list, or a read-only lookup map when `hashmap` is true.
---@param hashmap? false
---@return QuestieTDBNpcId[] ids
---@overload fun(hashmap: true): table<QuestieTDBNpcId, true>
function NpcDB.GetAllIds(hashmap) end
