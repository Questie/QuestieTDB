---@meta _

---@class ObjectDB
---@field name fun(id: QuestieTDBObjectId): string? Object name.
---@field questStarts fun(id: QuestieTDBObjectId): QuestieTDBQuestId[]? Quests started by this object.
---@field questEnds fun(id: QuestieTDBObjectId): QuestieTDBQuestId[]? Quests finished at this object.
---@field spawns fun(id: QuestieTDBObjectId): QuestieTDBSpawnList? Spawn coordinates grouped by zone.
---@field zoneID fun(id: QuestieTDBObjectId): QuestieTDBZoneId? Most common zone.
---@field factionID fun(id: QuestieTDBObjectId): QuestieTDBFactionId? Faction ID.
---@field waypoints fun(id: QuestieTDBObjectId): QuestieTDBWaypointList? Waypoint paths grouped by zone.
---@field GetByIndex fun(id: QuestieTDBObjectId, fieldIndex: integer): any Read a field by positional index.
---@field Get fun(id: QuestieTDBObjectId, key: QuestieTDBObjectField|integer): any Read a field by canonical name or index.
---@field GetAll fun(id: QuestieTDBObjectId, keys: (QuestieTDBObjectField|integer)[]): QuestieTDBPackedValues? Read fields into a packed table, or nil for an unknown ID.
---@field GetRaw fun(id: QuestieTDBObjectId, key: QuestieTDBObjectField|integer): any Read base data without Corrections or localization.
---@field Exists fun(id: QuestieTDBObjectId): boolean Test the composed view.
---@field InvalidateCache fun(id?: QuestieTDBObjectId) Drop cached fields for one object or every object.
ObjectDB = {}

---Returns the composed ID list, or a read-only lookup map when `hashmap` is true.
---@param hashmap? false
---@return QuestieTDBObjectId[] ids
---@overload fun(hashmap: true): table<QuestieTDBObjectId, true>
function ObjectDB.GetAllIds(hashmap) end
