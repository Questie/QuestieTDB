---@meta _

---@class ItemDB
---@field name fun(id: QuestieTDBItemId): string? Item name.
---@field npcDrops fun(id: QuestieTDBItemId): QuestieTDBNpcId[]? NPCs that drop this item.
---@field objectDrops fun(id: QuestieTDBItemId): QuestieTDBObjectId[]? Objects that drop this item.
---@field itemDrops fun(id: QuestieTDBItemId): QuestieTDBItemId[]? Items that contain this item.
---@field startQuest fun(id: QuestieTDBItemId): QuestieTDBQuestId? Quest started by this item.
---@field questRewards fun(id: QuestieTDBItemId): QuestieTDBQuestId[]? Quests that reward this item.
---@field flags fun(id: QuestieTDBItemId): number? Item flag bitmask.
---@field foodType fun(id: QuestieTDBItemId): number? Food type.
---@field itemLevel fun(id: QuestieTDBItemId): number? Item level.
---@field requiredLevel fun(id: QuestieTDBItemId): number? Required player level.
---@field ammoType fun(id: QuestieTDBItemId): number? Ammo type.
---@field class fun(id: QuestieTDBItemId): number? Item class.
---@field subClass fun(id: QuestieTDBItemId): number? Item subclass.
---@field vendors fun(id: QuestieTDBItemId): QuestieTDBNpcId[]? NPCs that sell this item.
---@field relatedQuests fun(id: QuestieTDBItemId): QuestieTDBQuestId[]? Related quests.
---@field teachesSpell fun(id: QuestieTDBItemId): number? Spell taught when used.
---@field GetByIndex fun(id: QuestieTDBItemId, fieldIndex: integer): any Read a field by positional index.
---@field Get fun(id: QuestieTDBItemId, key: QuestieTDBItemField|integer): any Read a field by canonical name or index.
---@field GetAll fun(id: QuestieTDBItemId, keys: (QuestieTDBItemField|integer)[]): QuestieTDBPackedValues? Read fields into a packed table, or nil for an unknown ID.
---@field GetRaw fun(id: QuestieTDBItemId, key: QuestieTDBItemField|integer): any Read base data without Corrections or localization.
---@field Exists fun(id: QuestieTDBItemId): boolean Test the composed view.
---@field InvalidateCache fun(id?: QuestieTDBItemId) Drop cached fields for one item or every item.
ItemDB = {}

---Returns the composed ID list, or a read-only lookup map when `hashmap` is true.
---@param hashmap? false
---@return QuestieTDBItemId[] ids
---@overload fun(hashmap: true): table<QuestieTDBItemId, true>
function ItemDB.GetAllIds(hashmap) end
