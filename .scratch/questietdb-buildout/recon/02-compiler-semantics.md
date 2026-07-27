# Recon 02 — Exact read-back semantics of Questie's DB compiler

Source of truth read for this document (all paths absolute):

- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/compiler.lua` (1367 lines, read in full)
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/QuestieStream.lua` (492 lines, read in full — the byte-level primitives)
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/QuestieDB.lua` (2119 lines, consumer)
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/{npcDB,objectDB,questDB,itemDB}.lua` (the four `*CompilerTypes` / `*CompilerOrder` / `*Keys` tables)
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Database/Corrections/QuestieCorrections.lua`
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/QuestieInit.lua`
- `/home/logon/projects/Questie-clones/Questie-toc/Questie/Localization/l10n.lua`
- All 20 raw data files under `Questie/Database/{Classic,TBC,Wotlk,Cata,MoP}/*DB.lua` (loaded and analysed with Lua 5.1)

Scan scripts used (kept for reproducibility, in scratchpad):
`/tmp/claude-1000/-home-logon-projects-Questie-clones-Questie-toc/9922907c-9560-4513-8eee-5d76191da8e4/scratchpad/recon02_{emptyscan,structscan,nilfields,edge,skipmap}.lua`

---

## 0. The four type tables — which type strings are actually in play

| Entity | file:line of `*CompilerTypes` | file:line of `*CompilerOrder` |
|---|---|---|
| npc | `Questie/Database/npcDB.lua:32` | `Questie/Database/npcDB.lua:49` |
| object | `Questie/Database/objectDB.lua:20` | `Questie/Database/objectDB.lua:30` |
| quest | `Questie/Database/questDB.lua:61` | `Questie/Database/questDB.lua:99` |
| item | `Questie/Database/itemDB.lua:93` | `Questie/Database/itemDB.lua:111` |

### npcCompilerTypes (npcDB.lua:32-47)
```lua
['name'] = "u8string",            ['minLevelHealth'] = "u32",
['maxLevelHealth'] = "u32",       ['minLevel'] = "u8",
['maxLevel'] = "u8",              ['rank'] = "u8",
['spawns'] = "spawnlist",         ['waypoints'] = "waypointlist",
['zoneID'] = "u16",               ['questStarts'] = "u8u24array",
['questEnds'] = "u8u24array",     ['factionID'] = "u16",
['friendlyToFaction'] = "faction",['subName'] = "u8string",
['npcFlags'] = "u32",
```

### objectCompilerTypes (objectDB.lua:20-28)
```lua
['name'] = "u8string",  ['spawns'] = "spawnlist",   ['zoneID'] = "u16",
['questStarts'] = "u8u24array", ['questEnds'] = "u8u24array",
['factionID'] = "u16",  ['waypoints'] = "waypointlist",
```

### questCompilerTypes (questDB.lua:61-97)
```lua
name=u8string, startedBy=questgivers, finishedBy=questgivers, requiredLevel=u8,
questLevel=s16, requiredRaces=u32, requiredClasses=u16, objectivesText=u8u16stringarray,
triggerEnd=trigger, objectives=objectives, sourceItemId=u24, preQuestGroup=u8s24array,
preQuestSingle=u8u24array, childQuests=u8u24array, inGroupWith=u8u24array,
exclusiveTo=u8u24array, zoneOrSort=s16, requiredSkill=u12pair, requiredMinRep=s24pair,
requiredMaxRep=s24pair, requiredSourceItems=u8u24array, nextQuestInChain=u24,
questFlags=u24, specialFlags=u16, parentQuest=u24, reputationReward=u8s24pairs,
breadcrumbForQuestId=u24, breadcrumbs=u8u24array, extraObjectives=extraobjectives,
requiredSpell=s24, requiredSpecialization=u24, requiredMaxLevel=u8,
availableUntilCompleted=u24, availableStartingWith=u24, requiredRanks=u8s24pairs,
disabledByQuest=u24
```

### itemCompilerTypes (itemDB.lua:93-110)
```lua
foodType=u8, itemLevel=u16, flags=u32, startQuest=u24, requiredLevel=u8, ammoType=u8,
class=u8, subClass=u8, npcDrops=u16u24array, objectDrops=u8u24array,
itemDrops=u8u24array, vendors=u16u24array, relatedQuests=u8u24array,
questRewards=u8u24array, name=u8string, teachesSpell=u24
```

### Types that exist in `readers`/`writers` but are NOT referenced by any of the four tables
- `s8`, `u16string`, `u8u16array`, `u8s16pairs`, `u16u16array` — **completely unused** (dead code).
- `u24pair` — only used *internally* by `objectives` for slot 4 (reputationObjective).
- `objective`, `spellobjective` — only used internally by `objectives`.
- `reflist` — only used internally by `extraobjectives`.

> Implication for QuestieTDB: only 20 type strings are load-bearing:
> `u8 u16 u24 u32 s16 s24 u8string u12pair s24pair faction spawnlist waypointlist
> u8u24array u8s24array u16u24array u8u16stringarray questgivers trigger objectives extraobjectives`
> plus 4 internal-only: `u24pair objective spellobjective reflist`.

---

## 1. MASTER TABLE — writer / reader / lossiness for EVERY type string

`W:` = what the writer emits. `R:` = what the reader returns.
"src nil" = the field was `nil` in `QuestieDB.<entity>Data[id][keyIndex]`.

| type | W(v) | W(nil) | W(0) | W("") | W({}) | R(normal) | R of W(nil) | R of W(0) | R of W("") | R of W({}) | LOSSY? |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **s8** | byte `v+127` | byte `127` | byte `127` | n/a | n/a | `byte-127` | **`0`** | `0` | – | – | nil→0. Range `[-127,128]`. UNUSED. |
| **u8** | byte `v` | byte `0` | byte `0` | n/a | n/a | byte | **`0`** | `0` | – | – | nil→0 |
| **u16** | short `v` | short `0` | short `0` | n/a | n/a | short | **`0`** | `0` | – | – | nil→0 |
| **s16** | short `32767+v` | short `32767` | short `32767` | n/a | n/a | `short-32767` | **`0`** | `0` | – | – | nil→0. Range `[-32767,32768]` |
| **u24** | int24 `v` | int24 `0` | int24 `0` | n/a | n/a | int24 | **`0`** | `0` | – | – | nil→0 |
| **s24** | int24 `8388607+v` | int24 `8388607` | int24 `8388607` | n/a | n/a | `int24-8388607` | **`0`** | `0` | – | – | nil→0. **offset 8388607** (≠ s24pair!). Range `[-8388607,8388608]` |
| **u32** | int32 `v` | int32 `0` | int32 `0` | n/a | n/a | int32 | **`0`** | `0` | – | – | nil→0 |
| **u12pair** | 3B `Int12Pair(v[1] or 0, v[2] or 0)` | 3B `Int24(0)` (=={0,0}) | n/a | n/a | 3B `Int12Pair(0,0)` | `{a,b}`, **`nil` if a==0 and b==0** | **`nil`** | – | – | **`nil`** | `{0,0}`→nil, `{}`→nil, nil→nil. `{0,n}`/`{n,0}` survive. 12-bit each (max 4095) |
| **u24pair** | 2×int24 `v[1] or 0`, `v[2] or 0` | 2×int24 `0` | n/a | n/a | 2×int24 `0` | `{a,b}`, **`nil` if a==0 and b==0** | **`nil`** | – | – | **`nil`** | same as u12pair |
| **s24pair** | 2×int24 `(v[i] or 0)+8388608` | 2×int24 `8388608` | n/a | n/a | 2×int24 `8388608` | `{a-8388608,b-8388608}`, **`nil` if both 0** | **`nil`** | – | – | **`nil`** | `{0,0}`→nil. **offset 8388608** (≠ scalar s24). Range `[-8388608,8388607]` |
| **u8string** | `WriteTinyString(v)` (1B len + bytes) | `WriteTinyString("nil")` | n/a | `WriteTinyString("")` → 1B `0x00` | n/a | `ReadTinyString()`; **`nil` if result == `"nil"`** | **`nil`** | – | **`""`** | – | **`""` round-trips as `""`**; a genuine source string `"nil"` round-trips as **`nil`** (LOSSY). Max 255 bytes |
| **u16string** | `WriteShortString(v)` (2B len) | `WriteShortString("nil")` | n/a | 2B `0x0000` | n/a | `ReadShortString()`; `nil` if `"nil"` | **`nil`** | – | `""` | – | same. UNUSED by any table |
| **u8u16array** | 1B count + count×short | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else array | **`nil`** | – | – | **`nil`** | `{}`→nil. UNUSED |
| **u8s16pairs** | 1B count + count×(2 shorts `+32767`) | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{{a-32767,b-32767},...}` | **`nil`** | – | – | **`nil`** | `{}`→nil. UNUSED |
| **u16u16array** | 2B count + count×short | 2B `0` | n/a | n/a | 2B `0` | count==0 → **`nil`** | **`nil`** | – | – | **`nil`** | UNUSED |
| **u8s24pairs** | 1B count + count×(2 int24 `(v[i] or 0)+8388608`) | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{{a-8388608,b-8388608},...}` | **`nil`** | – | – | **`nil`** | `{}`→nil. Inner `{0,0}` pairs are **kept** (no zero-collapse at the inner level) |
| **u8u24array** | 1B count + count×int24 `v` (no `or 0`) | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else array | **`nil`** | – | – | **`nil`** | `{}`→nil. count is capped at 255 (silently wraps `WriteByte` if >255) |
| **u8s24array** | 1B count + count×int24 `v+8388608` | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{v-8388608,...}` | **`nil`** | – | – | **`nil`** | `{}`→nil |
| **u16u24array** | 2B count + count×int24 `v` | 2B `0` | n/a | n/a | 2B `0` | count==0 → **`nil`** | **`nil`** | – | – | **`nil`** | `{}`→nil. Used for npcDrops/vendors which routinely exceed 255 entries |
| **u8u16stringarray** | 1B count + count×`WriteShortString(v or "nil")` | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{ReadShortString(),...}` | **`nil`** | – | – | **`nil`** | `{}`→nil. **Elements use plain `ReadShortString`, so `""` elements ARE preserved** — no `"nil"` sentinel on read. The `v or "nil"` in the writer is dead code (`pairs()` never yields nil) |
| **faction** | see below | 1B `3` | n/a | 1B `3` | n/a | 3→`nil`, 2→`"AH"`, 1→`"H"`, else→`"A"` | **`nil`** | – | **`nil`** | – | `""`→`nil` (LOSSY). Any string not in {`"A"`,`"H"`,`""`} → 2 → reads back as `"AH"` (e.g. `"HA"` becomes `"AH"`) |
| **spawnlist** | 1B zoneCount, then per zone: 2B zone, 2B spawnCount, then per spawn 3B Int12Pair(floor(x*40.90),floor(y*40.90)) + 2B phase | 1B `0` | n/a | n/a | 1B `0` | zoneCount==0 → **`nil`**; else `{[zone]={ {x/40.9,y/40.9} or {x/40.9,y/40.9,phase} or {-1,-1} }}` | **`nil`** | – | – | **`nil`** | `{}`→nil. **Coordinates are quantised to 1/40.90 (~0.02445) and lose precision**. `{-1,-1}` sentinel is encoded as `Int24(0)`; on read, `x==0 and y==0` → `{-1,-1}`. `phase==0` → the 3rd element is dropped |
| **waypointlist** | 1B zoneCount, per zone: 2B zone, 1B listCount, per list: 2B spawnCount, per spawn 3B Int12Pair (**NO phase byte**) | 1B `0` | n/a | n/a | 1B `0` | zoneCount==0 → **`nil`**; else `{[zone]={ {{x,y},...}, ... }}` | **`nil`** | – | – | **`nil`** | `{}`→nil. Same quantisation. `{-1,-1}` sentinel supported. **A 3rd element (phase) on a waypoint is silently dropped** |
| **trigger** | `WriteTinyString(v[1])` (errors if v[1]==nil) + spawnlist(v[2]) | 2 bytes `0x00 0x00` | n/a | n/a | would error (`string.len(nil)`) | `ReadShort()==0` → **`nil`**; else rewind 2 and return `{ReadTinyStringNil(), spawnlist}` | **`nil`** | – | – | – | `{"", nil}` and `{"", {}}` → **`nil`** (LOSSY). `{"text", nil}` → `{"text", nil}` (OK). Text uses `ReadTinyStringNil` so a zero-length text reads back as `nil` in slot 1 |
| **questgivers** | 3× `u8u24array(v[1..3])` | 3 bytes `0x00 0x00 0x00` | n/a | n/a | 3 bytes `0` | **ALWAYS a table** `{a,b,c}` where each is `u8u24array` result (may be nil) | **`{}`** (a table with all 3 slots nil) | – | – | **`{}`** | **`nil` → `{}` — NEVER nil.** This is the single biggest asymmetry. Inner `{}` → nil |
| **objective** (internal) | 1B count, per rec: int24 `pair[1]`, `WriteTinyString(pair[2] or "")`, byte `pair[3] or 0` | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{{int24, ReadTinyStringNil(), byte}, ...}` | **`nil`** | – | – | **`nil`** | text nil→`""`→nil (round-trips). text `""` → `""` → **`nil`** (LOSSY). icon nil→0→**`0`** (NOT nil) |
| **spellobjective** (internal) | 1B count, per rec: int24 `d[1]`, `WriteTinyString(d[2] or "")`, int24 `d[3] or 0` | 1B `0` | n/a | n/a | 1B `0` | count==0 → **`nil`**, else `{{int24, ReadTinyStringNil(), int24}, ...}` | **`nil`** | – | – | **`nil`** | text `""`→nil. item nil→0→**`0`** |
| **objectives** | see §2 | 7 bytes: `0,0,0, Int24(0), Int24(0), 0, 0` | n/a | n/a | same as nil | **ALWAYS a 6-slot table** | **`{}`** (all 6 slots nil) | – | – | **`{}`** | **`nil` → `{}` — NEVER nil** |
| **reflist** (internal) | 1B `#value` (**no nil guard — errors on nil**), per rec: byte refTypeIdx, int24 id | – | n/a | n/a | 1B `0` | count==0 → **`nil`** (implicit), else `{{refTypes[byte], int24}, ...}` | – | – | – | **`nil`** | `{}`→nil. Uses `#value` for count but `pairs()` for iteration |
| **extraobjectives** | 1B `#value`, per rec: spawnlist(d[1]), int24 `d[2]`, `WriteShortString(d[3])` (**errors on nil**), int24 `d[4] or 0`, reflist(`d[5] or {}`) | 1B `0` | n/a | n/a | 1B `0` (because `#{}`==0) | count==0 → **`nil`**, else `{{spawnlist, int24, ReadShortString(), int24, reflist}, ...}` | **`nil`** | – | – | **`nil`** | `{}`→nil. desc `""` preserved (`ReadShortString`). `d[4]` nil→0→**`0`**. `d[5]` nil→`{}`→**`nil`** |

---

## 2. Verbatim code — readers (compiler.lua:115-410)

```lua
local readers = {}
local skippers = {}

readers["s8"] = function(stream)
    return stream:ReadByte() - 127
end
readers["u8"] = QuestieStream.ReadByte
readers["u16"] = QuestieStream.ReadShort
readers["s16"] = function(stream)
    return stream:ReadShort() - 32767
end
readers["u24"] = QuestieStream.ReadInt24
readers["s24"] = function(stream)
    return stream:ReadInt24() - 8388607
end
readers["u32"] = QuestieStream.ReadInt
readers["u12pair"] = function(stream)
    local a,b = stream:ReadInt12Pair()
    -- bit of a hack
    if a == 0 and b == 0 then
        return nil
    end
    return {a, b}
end
readers["u24pair"] = function(stream)
    local a,b = stream:ReadInt24(), stream:ReadInt24()
    -- bit of a hack
    if a == 0 and b == 0 then
        return nil
    end

    return {a, b}
end
readers["s24pair"] = function(stream)
    local a,b = stream:ReadInt24()-8388608, stream:ReadInt24()-8388608
    -- bit of a hack
    if a == 0 and b == 0 then
        return nil
    end

    return {a, b}
end
readers["u8string"] = function(stream)
    local ret = stream:ReadTinyString()
    if ret == "nil" then-- I hate this but we need to support both nil strings and empty strings
        return nil
    else
        return ret
    end
end
readers["u16string"] = function(stream)
    local ret = stream:ReadShortString()
    if ret == "nil" then-- I hate this but we need to support both nil strings and empty strings
        return nil
    else
        return ret
    end
end
readers["u8u16array"] = function(stream)
    local count = stream:ReadByte()

    if count == 0 then return nil end

    local list = {}

    for i = 1, count do
        list[i] = stream:ReadShort()
    end
    return list
end
readers["u8s16pairs"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local list = {}
    for i = 1, count do
        list[i] = {stream:ReadShort() - 32767, stream:ReadShort() - 32767}
    end
    return list
end
readers["u16u16array"] = function(stream)
    local count = stream:ReadShort()
    if count == 0 then return nil end
    ...
end
readers["u8s24pairs"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local list = {}
    for i = 1, count do
        list[i] = {stream:ReadInt24()-8388608, stream:ReadInt24()-8388608}
    end
    return list
end
readers["u8u24array"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end
    local list = {}
    for i = 1, count do
        list[i] = stream:ReadInt24()
    end
    return list
end
readers["u8s24array"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end
    local list = {}
    for i = 1, count do
        list[i] = stream:ReadInt24() - 8388608
    end
    return list
end
readers["u16u24array"] = function(stream)
    local count = stream:ReadShort()
    if count == 0 then return nil end
    ...
end
readers["u8u16stringarray"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local list = {}
    for i = 1, count do
        list[i] = stream:ReadShortString()      -- NOTE: NOT the "nil"-sentinel variant
    end
    return list
end
readers["faction"] = function(stream)
    local val = stream:ReadByte()
    if val == 3 then
        return nil
    elseif val == 2 then
        return "AH"
    elseif val == 1 then
        return "H"
    else
        return "A"
    end
end
readers["spawnlist"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local spawnlist = {}
    for _ = 1, count do
        local zone = stream:ReadShort()
        local spawnCount = stream:ReadShort()
        local list = {}
        for i = 1, spawnCount do
            local x, y = stream:ReadInt12Pair()
            local phase = stream:ReadShort()
            if x == 0 and y == 0 then
                list[i] = {-1, -1}
            elseif phase == 0 then
                list[i] = {x / 40.90, y / 40.90}
            else
                list[i] = {x / 40.90, y / 40.90, phase}
            end
        end
        spawnlist[zone] = list
    end
    return spawnlist
end
readers["trigger"] = function(stream)
    if stream:ReadShort() == 0 then
        return nil
    else
        stream._pointer = stream._pointer - 2
    end
    return {stream:ReadTinyStringNil(), readers["spawnlist"](stream)}
end
local u8u24arrayReader = readers["u8u24array"]
readers["questgivers"] = function(stream)
    return {
        u8u24arrayReader(stream),
        u8u24arrayReader(stream),
        u8u24arrayReader(stream)
    }
end
readers["objective"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local ret = {}
    for i = 1, count do
        ret[i] = {stream:ReadInt24(), stream:ReadTinyStringNil(), stream:ReadByte()}
    end
    return ret
end
readers["spellobjective"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local ret = {}
    for i = 1, count do
        ret[i] = {stream:ReadInt24(), stream:ReadTinyStringNil(), stream:ReadInt24()}
    end
    return ret
end

readers["objectives"] = function(stream)
    local ret = {
        readers["objective"](stream),
        readers["objective"](stream),
        readers["objective"](stream),
        readers["u24pair"](stream),
    }

    local count = stream:ReadByte()
    if count == 0 then
        ret[5] = nil
    else
        local killobjectives = {}
        for i=1, count do
            local creditCount = stream:ReadByte()
            local creditList = {}
            for j=1, creditCount do
                creditList[j] = stream:ReadInt24()
            end
            killobjectives[i] = {creditList, stream:ReadInt24(), stream:ReadTinyStringNil(), stream:ReadByte()}
        end
        ret[5] = killobjectives
    end

    ret[6] = readers["spellobjective"](stream)

    return ret
end
readers["reflist"] = function(stream)
    local count = stream:ReadByte()
    if count > 0 then
        local ret = {}
        for i=1,count do
            ret[i] = {refTypes[stream:ReadByte()], stream:ReadInt24()}
        end
        return ret
    end
end
readers["extraobjectives"] = function(stream)
    local count = stream:ReadByte()
    if count > 0 then
        local ret = {}
        for i=1,count do
            ret[i] = {
                readers["spawnlist"](stream),
                stream:ReadInt24(),
                stream:ReadShortString(),
                stream:ReadInt24(),
                readers["reflist"](stream)
            }
        end
        return ret
    end
    return nil
end
readers["waypointlist"] = function(stream)
    local count = stream:ReadByte()
    if count == 0 then return nil end

    local waypointlist = {}
    for _ = 1, count do
        local lists = {}
        local zone = stream:ReadShort()
        local listCount = stream:ReadByte()
        for j = 1, listCount do
            local spawnCount = stream:ReadShort()
            local list = {}
            for i = 1, spawnCount do
                local x, y = stream:ReadInt12Pair()
                if x == 0 and y == 0 then
                    list[i] = {-1, -1}
                else
                    list[i] = {x / 40.90, y / 40.90}
                end
            end
            lists[j] = list
        end
        waypointlist[zone] = lists
    end
    return waypointlist
end
```

`refTypes` (compiler.lua:102-113):
```lua
local refTypes = { "monster", "item", "object" }
QuestieDBCompiler.refTypesReversed = { monster = 1, item = 2, object = 3 }
```

---

## 3. Verbatim code — writers (compiler.lua:412-735)

```lua
QuestieDBCompiler.writers = {
    ["s8"]  = function(stream, value) stream:WriteByte((value or 0)+127) end,
    ["u8"]  = function(stream, value) stream:WriteByte(value or 0) end,
    ["u16"] = function(stream, value) stream:WriteShort(value or 0) end,
    ["s16"] = function(stream, value) stream:WriteShort(32767 + (value or 0)) end,
    ["u24"] = function(stream, value) stream:WriteInt24(value or 0) end,
    ["s24"] = function(stream, value) stream:WriteInt24(8388607 + (value or 0)) end,
    ["u32"] = function(stream, value) stream:WriteInt(value or 0) end,
    ["u12pair"] = function(stream, value)
        if value then
            stream:WriteInt12Pair(value[1] or 0, value[2] or 0)
        else
            stream:WriteInt24(0)
        end
    end,
    ["u24pair"] = function(stream, value)
        if value then
            stream:WriteInt24(value[1] or 0)
            stream:WriteInt24(value[2] or 0)
        else
            stream:WriteInt24(0); stream:WriteInt24(0)
        end
    end,
    ["s24pair"] = function(stream, value)
        if value then
            stream:WriteInt24((value[1] or 0) + 8388608)
            stream:WriteInt24((value[2] or 0) + 8388608)
        else
            stream:WriteInt24(8388608); stream:WriteInt24(8388608)
        end
    end,
    ["u8string"] = function(stream, value)
        stream:WriteTinyString(value or "nil") -- I hate this but we need to support both nil strings and empty strings
    end,
    ["u16string"] = function(stream, value)
        stream:WriteShortString(value or "nil")
    end,
    ["u8u16array"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do stream:WriteShort(v) end
        else
            stream:WriteByte(0)
        end
    end,
    ["u8s16pairs"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do
                stream:WriteShort((v[1] or 0) + 32767)
                stream:WriteShort((v[2] or 0) + 32767)
            end
        else stream:WriteByte(0) end
    end,
    ["u16u16array"] = ... WriteShort(count) ... else stream:WriteShort(0) end,
    ["u8s24pairs"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do
                stream:WriteInt24((v[1] or 0) + 8388608)
                stream:WriteInt24((v[2] or 0) + 8388608)
            end
        else stream:WriteByte(0) end
    end,
    ["u8u24array"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do stream:WriteInt24(v) end
        else stream:WriteByte(0) end
    end,
    ["u8s24array"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do stream:WriteInt24(v + 8388608) end
        else stream:WriteByte(0) end
    end,
    ["u16u24array"] = ... WriteShort(count) ... else stream:WriteShort(0) end,
    ["u8u16stringarray"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _,v in pairs(value) do stream:WriteShortString(v or "nil") end
        else
            stream:WriteByte(0)
        end
    end,
    ["faction"] = function(stream, value)
        if value == nil then
            stream:WriteByte(3)
        elseif "A" == value then
            stream:WriteByte(0)
        elseif "H" == value then
            stream:WriteByte(1)
        elseif "" == value then
            stream:WriteByte(3)
        else
            stream:WriteByte(2)
        end
    end,
    ["spawnlist"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for zone, spawnlist in pairs(value) do
                count = 0 for _ in pairs(spawnlist) do count = count + 1 end
                stream:WriteShort(zone)
                stream:WriteShort(count)
                for _, spawn in pairs(spawnlist) do
                    if spawn[1] == -1 and spawn[2] == -1 then -- instance spawn
                        stream:WriteInt24(0) -- 0 instead
                    else
                        stream:WriteInt12Pair(floor(spawn[1] * 40.90), floor(spawn[2] * 40.90))
                    end
                    stream:WriteShort(spawn[3] or 0) -- spawn phase
                end
            end
        else
            stream:WriteByte(0)
        end
    end,
    ["trigger"] = function(stream, value)
        if value then
            stream:WriteTinyString(value[1])
            QuestieDBCompiler.writers["spawnlist"](stream, value[2])
        else
            stream:WriteByte(0)
            stream:WriteByte(0)
        end
    end,
    ["questgivers"] = function(stream, value)
        if value then
            QuestieDBCompiler.writers["u8u24array"](stream, value[1])
            QuestieDBCompiler.writers["u8u24array"](stream, value[2])
            QuestieDBCompiler.writers["u8u24array"](stream, value[3])
        else
            stream:WriteByte(0); stream:WriteByte(0); stream:WriteByte(0)
        end
    end,
    ["objective"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _, pair in pairs(value) do
                stream:WriteInt24(pair[1])
                stream:WriteTinyString(pair[2] or "")
                stream:WriteByte(pair[3] or 0)
            end
        else stream:WriteByte(0) end
    end,
    ["spellobjective"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for _, data in pairs(value) do
                stream:WriteInt24(data[1])
                stream:WriteTinyString(data[2] or "")
                stream:WriteInt24(data[3] or 0)
            end
        else stream:WriteByte(0) end
    end,
    ["objectives"] = function(stream, value)
        if value then
            QuestieDBCompiler.writers["objective"](stream, value[1])
            QuestieDBCompiler.writers["objective"](stream, value[2])
            QuestieDBCompiler.writers["objective"](stream, value[3])
            QuestieDBCompiler.writers["u24pair"](stream, value[4])

            local killobjectives = value[5]
            if type(killobjectives) == "table" and #killobjectives > 0 then
                stream:WriteByte(#killobjectives)
                for i=1, #killobjectives do
                    local killobjective = killobjectives[i]
                    local npcIds = killobjective[1]
                    assert(type(npcIds) == "table", "killobjective's npcids is not a table.")
                    assert(#npcIds > 0, "killobjective has 0 npcIDs.")
                    stream:WriteByte(#npcIds)
                    for j=1, #npcIds do stream:WriteInt24(npcIds[j]) end
                    stream:WriteInt24(killobjective[2])
                    stream:WriteTinyString(killobjective[3] or "")
                    stream:WriteByte(killobjective[4] or 0)
                end
            else
                stream:WriteByte(0)
            end

            QuestieDBCompiler.writers["spellobjective"](stream, value[6])
        else
            stream:WriteByte(0); stream:WriteByte(0); stream:WriteByte(0)
            stream:WriteInt24(0); stream:WriteInt24(0)
            stream:WriteByte(0); stream:WriteByte(0)
        end
    end,
    ["reflist"] = function(stream, value)
        stream:WriteByte(#value)
        for _, v in pairs(value) do
            stream:WriteByte(QuestieDBCompiler.refTypesReversed[v[1]])
            stream:WriteInt24(v[2])
        end
    end,
    ["extraobjectives"] = function(stream, value)
        if value then
            stream:WriteByte(#value)
            for _, data in pairs(value) do
                QuestieDBCompiler.writers["spawnlist"](stream, data[1])
                stream:WriteInt24(data[2]) -- icon
                stream:WriteShortString(data[3]) -- description
                stream:WriteInt24(data[4] or 0) -- objective index (or 0)
                QuestieDBCompiler.writers["reflist"](stream, data[5] or {})
            end
        else stream:WriteByte(0) end
    end,
    ["waypointlist"] = function(stream, value)
        if value then
            local count = 0 for _ in pairs(value) do count = count + 1 end
            stream:WriteByte(count)
            for zone, spawnlists in pairs(value) do
                stream:WriteShort(zone)
                count = 0 for _ in pairs(spawnlists) do count = count + 1 end
                stream:WriteByte(count)
                for _, spawnlist in pairs(spawnlists) do
                    count = 0 for _ in pairs(spawnlist) do count = count + 1 end
                    stream:WriteShort(count)
                    for _, spawn in pairs(spawnlist) do
                        if spawn[1] == -1 and spawn[2] == -1 then
                            stream:WriteInt24(0)
                        else
                            stream:WriteInt12Pair(floor(spawn[1] * 40.90), floor(spawn[2] * 40.90))
                        end
                    end
                end
            end
        else stream:WriteByte(0) end
    end
}
```

### Relevant stream primitives (QuestieStream.lua)

```lua
function QuestieStreamLib:_ReadTinyString_raw()      -- line 312
    local p = self._pointer
    local length = stringbyte(self._bin, p)
    p = p + 1
    self._pointer = p + length
    return stringsub(self._bin, p, p+length-1)       -- length 0 -> ""
end

function QuestieStreamLib:_ReadTinyStringNil_raw()   -- line 320
    local p = self._pointer
    local length = stringbyte(self._bin, p)
    p = p + 1
    if length == 0 then
        self._pointer = p
        return nil                                    -- length 0 -> nil
    end
    self._pointer = p + length
    return stringsub(self._bin, p, p+length-1)
end

function QuestieStreamLib:_ReadShortString_raw()     -- line 358
    ... length = a*256+b ... return stringsub(...)    -- length 0 -> ""
end

function QuestieStreamLib:_WriteTinyString(val)      -- line 445
    local length = string.len(val)                   -- errors if val is nil
    self:WriteByte(length)
    for i=1, length do self:WriteByte(stringbyte(val, i)) end
end

function QuestieStreamLib:WriteShortString(val)      -- line 461
    local length = string.len(val)                   -- errors if val is nil
    self:WriteShort(length)
    ...
end

function QuestieStreamLib:_WriteInt12Pair(val1, val2) -- line 408 — MASKS, no bounds check
    self:WriteByte(band(rshift(val1, 8), 15) + lshift(band(rshift(val2, 8), 15), 4))
    self:WriteByte(val1 % 256)
    self:WriteByte(val2 % 256)
end
```

---

## 4. Answers to the specific questions

### (a) Does a numeric field whose source is nil read back as 0? — **YES, always.**

Every scalar numeric writer applies `(value or 0)`:
```lua
["u8"]  = function(stream, value) stream:WriteByte(value or 0) end,       -- compiler.lua:416
["u16"] = function(stream, value) stream:WriteShort(value or 0) end,      -- compiler.lua:419
["u24"] = function(stream, value) stream:WriteInt24(value or 0) end,      -- compiler.lua:425
["u32"] = function(stream, value) stream:WriteInt(value or 0) end,        -- compiler.lua:431
["s16"] = function(stream, value) stream:WriteShort(32767 + (value or 0)) end, -- compiler.lua:422
["s24"] = function(stream, value) stream:WriteInt24(8388607 + (value or 0)) end, -- compiler.lua:428
["s8"]  = function(stream, value) stream:WriteByte((value or 0)+127) end, -- compiler.lua:413
```
and every scalar numeric reader returns a plain number (never nil).

**Consumer proof** — code that would crash if this were not true:
- `Questie/Modules/Quest/QuestieQuest.lua:687` — `quest.sourceItemId > 0`
- `Questie/Modules/Quest/QuestieQuest.lua:994` — `if quest and quest.sourceItemId > 0 then`
- `Questie/Modules/Journey/QuestDetailsFrame.lua:412-413`
  ```lua
  local breadcrumbForQuestId = QuestieDB.QueryQuestSingle(quest.Id, "breadcrumbForQuestId")
  if breadcrumbForQuestId and breadcrumbForQuestId ~= 0 then
  ```
- `Questie/Modules/Journey/tabs/QuestsByFaction/QuestsByFactions.lua:619` — `if nextQuestInChain and nextQuestInChain ~= 0 then`

> **QuestieTDB must reproduce `nil → 0` for every field typed `u8/u16/u24/u32/s8/s16/s24`.**

### (b) String fields: nil vs `""`, and the `"nil"` sentinel

- `nil` **reads back as `nil`**, via the `"nil"` string sentinel.
- `""` **reads back as `""`** (preserved!).
- The sentinel goes **write-side → read-side**: the writer substitutes the 3-char literal `"nil"` for a nil value; the reader maps the literal `"nil"` back to nil.

```lua
-- writer, compiler.lua:459-468
["u8string"] = function(stream, value)
    stream:WriteTinyString(value or "nil") -- I hate this but we need to support both nil strings and empty strings
end,
-- reader, compiler.lua:157-164
readers["u8string"] = function(stream)
    local ret = stream:ReadTinyString()
    if ret == "nil" then-- I hate this but we need to support both nil strings and empty strings
        return nil
    else
        return ret
    end
end
```

**LOSSY CASE:** a real source string whose value is exactly `"nil"` reads back as Lua `nil`. Verified: **no such value exists** in any raw data file for `name`/`subName` (scan `recon02_edge.lua` → 0 hits for `npc.name_LITERAL_nil`, `object.name_LITERAL_nil`, `item.name_LITERAL_nil`, `quest.name_LITERAL_nil`, `npc.subName_LITERAL_nil`).

`u8u16stringarray` (objectivesText) is **different**: its element reader is plain `ReadShortString()` with **no** `"nil"` check (compiler.lua:251). So `""` elements survive; the writer's `v or "nil"` is dead code because `pairs()` never yields nil.

`objective` / `spellobjective` / killobjective texts use `ReadTinyStringNil()` and are written as `pair[2] or ""` — so **nil→nil (correct), but a genuine `""` also reads back as `nil`.**

### (c) Do table fields whose source is nil or `{}` both read back as nil? — **Mostly yes, with TWO major exceptions.**

For all length-prefixed array/list types the answer is yes:
```lua
-- writer: `if value then <count from pairs()> else WriteByte(0) end`
--         an empty table yields count == 0, identical bytes to the nil branch
-- reader:
local count = stream:ReadByte()
if count == 0 then return nil end
```
Applies to: `u8u16array, u8s16pairs, u16u16array, u8s24pairs, u8u24array, u8s24array, u16u24array, u8u16stringarray, spawnlist, waypointlist, objective, spellobjective, reflist, extraobjectives`.

For `u12pair` / `u24pair` / `s24pair`: nil and `{}` both encode as the zero-pair and read back nil (see (d)).

**EXCEPTION 1 — `questgivers` never returns nil.** `readers["questgivers"]` (compiler.lua:300-306) unconditionally constructs a 3-element table. `startedBy`/`finishedBy` therefore always read back as a table (possibly one whose 3 slots are all nil, i.e. `{}` by `next()`), never nil.
`Questie/Database/QuestieDB.lua:1495-1501` depends on this:
```lua
local startedBy = QO.startedBy
QO.Starts = { NPC = startedBy[1], GameObject = startedBy[2], Item = startedBy[3] }
```
Raw-data evidence: **11534 quests have `startedBy == nil`** and **3017 have `finishedBy == nil`** across the 5 expansions — every one of them reads back as `{}`.

**EXCEPTION 2 — `objectives` never returns nil.** `readers["objectives"]` (compiler.lua:328-355) always returns a 6-slot table. Raw-data evidence: **21358 quests have `objectives == nil`**; all read back as a table with 6 nil slots.
Note `QuestieDB.lua:1526` (`if objectives then`) is therefore always true.

### (d) The pair types: `{0,0}` → nil, and the documenting comment

The comment is literally `-- bit of a hack`, appearing three times:

- `compiler.lua:131-138` (`u12pair`), comment on **line 133**
- `compiler.lua:139-147` (`u24pair`), comment on **line 141**
- `compiler.lua:148-156` (`s24pair`), comment on **line 150**

```lua
readers["u12pair"] = function(stream)
    local a,b = stream:ReadInt12Pair()
    -- bit of a hack
    if a == 0 and b == 0 then
        return nil
    end
    return {a, b}
end
```

- `{0, 0}` → **nil** (indistinguishable from nil / `{}`).
- `{0, n}` with n≠0 → **`{0, n}`** — survives intact.
- `{n, 0}` with n≠0 → **`{n, 0}`** — survives intact.

Only *both* components zero triggers the collapse. Also note a partially-nil source table is normalised: `{nil, 5}` → `{0, 5}` (writer uses `value[1] or 0`).

**Raw-data reality (all 5 expansions):**

| field | type | `{0,0}` | `{0,n}` | `{n,0}` |
|---|---|---|---|---|
| `requiredSkill` | u12pair | **0** | 0 | **175** (e.g. classic quest 8193 → `{356,0}`) |
| `requiredMinRep` | s24pair | **0** | 0 | **294** (e.g. classic quest 8576 → `{910,0}`) |
| `requiredMaxRep` | s24pair | **0** | 0 | **25** (e.g. classic quest 9268 → `{369,0}`) |
| `objectives[4]` (reputationObjective) | u24pair | **0** | 0 | occurs (`[2]` min value is 0) |

So the `{0,0}` collapse is currently **harmless** for real data, but `{n,0}` is common and **must be preserved**.

### (e) The ±32767 / ±8388607 / ±8388608 offsets exist ONLY in the encoder/decoder

Confirmed. The offsets appear **only** in `compiler.lua`:

| type | writer offset | reader offset | compiler.lua lines |
|---|---|---|---|
| `s8` | `+127` | `-127` | 413-415 / 118-120 |
| `s16` | `+32767` | `-32767` | 422-424 / 123-125 |
| `s24` | **`+8388607`** | **`-8388607`** | 428-430 / 127-129 |
| `s24pair` | **`+8388608`** | **`-8388608`** | 450-458 / 148-156 |
| `u8s16pairs` | `+32767` | `-32767` | 488-499 / 185-194 |
| `u8s24pairs` | **`+8388608`** | **`-8388608`** | 511-522 / 205-214 |
| `u8s24array` | **`+8388608`** | **`-8388608`** | 534-544 / 225-234 |

⚠️ **The scalar `s24` offset (8388607) differs from the offset used by `s24pair`/`u8s24pairs`/`u8s24array` (8388608).** Each type is internally symmetric so round-trips are fine, but the *representable ranges* differ:
`s16 ∈ [-32767, 32768]`, `s24 ∈ [-8388607, 8388608]`, `s24pair/u8s24pairs/u8s24array ∈ [-8388608, 8388607]`, `s8 ∈ [-127, 128]`.

**Raw data verification.** Grepping the 20 data files for the literals `32767`, `8388607`, `8388608` yields only these, none of which is an offset artefact:

| file | literal | occurrences | what it actually is |
|---|---|---|---|
| Cata/cataQuestDB.lua | 8388608 | 28 | `questFlags` bit 23 (field 23, u24) |
| MoP/mopQuestDB.lua | 8388608 | 108 | `questFlags` bit 23 |
| Wotlk/Cata/MoP NpcDB | 32767 | 1 each | ordinary numeric values |
| Wotlk/Cata/MoP ItemDB | 32767 / 8388608 | 1–4 each | ordinary item flags/ids |
| all others | – | **0** | – |

Direct proof that the raw data is *unoffset*: MoP quest 3091 (`MoP/mopQuestDB.lua:1760`) stores `zoneOrSort` (s16, field 17) as `-81` and `questLevel` (s16, field 5) as `3`:
```lua
[3091] = {"Simple Note",{{44927}},{{3059}},3,3,32,1,{"Read the Simple Note..."},nil,nil,9547,nil,{24852},nil,nil,nil,-81,nil,nil,nil,nil,nil,8388608,4,nil,{{81,3}}},
```
Observed value ranges in raw data (whole DB): `questLevel ∈ [-1, 255]`, `zoneOrSort ∈ [-436, 6757]`, `requiredSpell` never present in raw data, `reputationReward[i][2] ∈ [-500, 42000]` (negative values do occur → the s24 pair offset is genuinely needed).

### (f) The `faction` type (`friendlyToFaction`) — exactly what it normalizes

```lua
-- WRITER, compiler.lua:568-580
["faction"] = function(stream, value)
    if value == nil then
        stream:WriteByte(3)
    elseif "A" == value then
        stream:WriteByte(0)
    elseif "H" == value then
        stream:WriteByte(1)
    elseif "" == value then
        stream:WriteByte(3)
    else
        stream:WriteByte(2)
    end
end,
-- READER, compiler.lua:255-266
readers["faction"] = function(stream)
    local val = stream:ReadByte()
    if val == 3 then
        return nil
    elseif val == 2 then
        return "AH"
    elseif val == 1 then
        return "H"
    else
        return "A"
    end
end
```

Normalizations performed:
1. `nil` → byte 3 → **`nil`** (round-trips).
2. `""` → byte 3 → **`nil`** (LOSSY — empty string becomes nil).
3. `"A"` → 0 → `"A"`; `"H"` → 1 → `"H"` (round-trip).
4. **Everything else** (including `"AH"`, but also `"HA"`, `"ah"`, any typo) → byte 2 → **`"AH"`**. So the type collapses the entire "not A, not H, not empty" space onto the canonical string `"AH"`.
5. The reader's `else` branch catches byte 0 **and any byte ≥ 4**, returning `"A"` — but only bytes 0-3 are ever written.

`""` is actually used: `Questie/Database/Corrections/wotlkNPCFixes.lua:35`
```lua
[npcKeys.friendlyToFaction] = "",
```
(clears a faction to nil via the compiler). Raw data files never contain `""` for field 13; only `"A"` (21127), `"H"` (18528), `"AH"` (65629), or `nil` (59314). No other string values exist.

Consumer: `QuestieDB.IsFriendlyToPlayer` (`QuestieDB.lua:1811-1823`) treats `nil` and `"AH"` as friendly-to-everyone.

### (g) `questgivers`, `objectives`, `spawnlist`, `waypointlist`, `trigger`, `extraobjectives`

#### `questgivers` (startedBy / finishedBy)
- **Expects:** `{ {creatureIds...}?, {objectIds...}?, {itemIds...}? }` — each slot an array of u24 ids, each slot optional (nil).
  `finishedBy` uses only slots 1 (creature) and 2 (object); **slot 3 is never populated in any raw data file** (0 occurrences).
- **Encoding:** three consecutive `u8u24array` blocks, always all three, in order.
- **Returns:** ALWAYS a fresh 3-element table. Each slot is `nil` (when the source slot was nil or `{}`) or a compacted array.
- **nil holes:** a hole such as `{nil, {31}}` is perfectly supported because each slot is written independently. Raw data has **4226** `startedBy` entries and **2415** `finishedBy` entries with slot-1 nil.
- **Element-level nil holes inside a slot** (e.g. `{5, nil, 7}`) would be silently *compacted* by the writer (`pairs()` skips nils, count is `pairs()`-based). No such holes exist in raw data.
- **nil → `{}`** (see (c) Exception 1).

#### `objectives`
- **Expects** a 6-slot table:
  1. `creatureObjective` — `{{creatureId, text?, iconIdx?}, ...}` (type `objective`)
  2. `objectObjective` — same shape
  3. `itemObjective` — same shape
  4. `reputationObjective` — `{factionId, requiredValue}` (type `u24pair`)
  5. `killCreditObjective` — `{ { {creatureId,...}, baseCreatureId, baseCreatureText?, iconIdx? }, ... }`
  6. `spellObjective` — `{{spellId, text?, itemId?}, ...}` (type `spellobjective`)
- **Wire order:** objective(1), objective(2), objective(3), u24pair(4), 1B killCreditCount + records, spellobjective(6). Minimum footprint for an all-nil objectives is 7 bytes (`0,0,0, Int24(0), 0, 0` — actually `WriteByte(0)×3, WriteInt24(0)×2, WriteByte(0)×2`).
- **Returns** ALWAYS a 6-slot table. Slots 1,2,3,5,6 are nil when their count byte was 0; slot 4 is nil when the u24pair was `{0,0}`.
- **nil holes inside `objectives`**: fully supported — 20387 quests in raw data have `objectives` with a hole (e.g. `{nil,nil,{{1234}}}`).
- **Per-record normalization inside slots 1-3**: `text` nil → `""` on write → **nil** on read (via `ReadTinyStringNil`); `icon` nil → `0` on write → **`0`** on read (NOT nil).
- **killCredit** slot 5: the writer requires `killobjective[1]` to be a non-empty table (two `assert`s, compiler.lua:663-664). It uses `#killobjectives` and `#npcIds` (length operator) rather than a `pairs()` count. `text` nil→`""`→nil, `icon` nil→`0`→**`0`**.
- **Raw-data reality:** slot 6 (`spellObjective`) is **never present in any raw data file** (0 occurrences) — it only ever comes from corrections. Records in slots 1-3 are always length 1 or 2 (id, or id+text) — **the icon element is never present in raw data**, so post-read it is always `0` unless a correction supplied it.

#### `spawnlist`
- **Expects:** `{ [zoneId:number] = { {x:number, y:number} | {x,y,phase:number} | {-1,-1}, ... }, ... }`
- **Wire:** `1B zoneCount`, then per zone `2B zoneId`, `2B spawnCount`, then per spawn `3B Int12Pair(floor(x*40.90), floor(y*40.90))` + `2B phase (spawn[3] or 0)`.
- **Returns:** `nil` if zoneCount==0; else a zone-keyed table. Per spawn: `{-1,-1}` if the decoded `x==0 and y==0`; `{x/40.90, y/40.90}` if phase==0; `{x/40.90, y/40.90, phase}` otherwise.
- **Normalizations:** coordinates are quantised to 1/40.90 ≈ 0.024449 (values 0..4095 → 0..100.12); the `{-1,-1}` "instance spawn" sentinel is stored as three zero bytes; a `phase` of 0 is dropped from the returned tuple.
- **Zone iteration order is `pairs()` order** on the wire, but the reader rebuilds a keyed table so order is irrelevant.
- **Per-zone spawn arrays with nil holes** would be compacted (`pairs()`-based count + `pairs()` iteration). None exist in raw data.
- **Raw-data reality:** 17335 npc + 5081 object instance-spawn `{-1,-1}` markers; 722 npc + 675 object spawns carry a phase (phase values 169-632). **No spawn in raw data is literally `{0,0}` and none quantise down to `{0,0}`.**

#### `waypointlist`
- **Expects:** `{ [zoneId] = { {{x,y},{x,y},...}, {{x,y},...} , ... }, ... }` — a zone maps to a **list of lists** of coordinate pairs.
- **Wire:** `1B zoneCount`, per zone `2B zoneId`, `1B listCount`, per list `2B spawnCount`, per spawn `3B Int12Pair` — **no phase byte**.
- **Returns:** `nil` if zoneCount==0; per spawn `{-1,-1}` if x==0 and y==0, else `{x/40.90, y/40.90}` — **never a 3rd element**.
- ⚠️ **listCount is a single byte** (max 255 lists per zone); `zoneCount` is also a byte.
- Note `QuestieCorrections:OptimizeWaypoints` (`Corrections/QuestieCorrections.lua:375-416`) rewrites `waypoints` before compilation (Ramer–Douglas–Peucker + subdivision), and it also *normalises* the `{{x,y},...}` single-list shape into `{{{x,y},...}}`. `QuestieCorrections:PreCompile()` (line 418) runs this over every npc and object.

#### `trigger` (`triggerEnd`)
- **Expects:** `{ text:string, spawnlist? }`.
- **Wire:** `WriteTinyString(value[1])` (**errors if `value[1]` is nil** — `string.len(nil)`), then a full `spawnlist` block.
- **Returns:**
  ```lua
  readers["trigger"] = function(stream)
      if stream:ReadShort() == 0 then
          return nil
      else
          stream._pointer = stream._pointer - 2
      end
      return {stream:ReadTinyStringNil(), readers["spawnlist"](stream)}
  end
  ```
  The nil-probe reads the **first two bytes as a short** — the nil writer emits exactly `0x00 0x00` (text-length 0 + spawnlist-count 0), so the probe is `textLen*256 + firstByteAfter == 0`.
- **Edge:** if `text == ""` **and** the spawnlist is empty, the whole trigger reads back as `nil`. If `text == ""` but the spawnlist is non-empty, `ReadTinyStringNil()` returns `nil` for slot 1. Both are lossy; **neither occurs in raw data** (0 quests with empty or nil trigger text).
- **Raw-data reality:** only **245** quests have `triggerEnd` at all (52161 of 52406 are nil); **19** of them have `triggerEnd = {text}` with no spawnlist — those read back as `{text, nil}` correctly.

#### `extraobjectives` (`extraObjectives`)
- **Expects:** `{ { spawnlist?, iconIdx:number, description:string, objectiveIndex?:number, reflist? }, ... }`
  where `reflist` is `{ {"monster"|"item"|"object", id:number}, ... }`.
- **Wire:** `1B #value`, then per record: spawnlist block, `3B Int24(icon)`, `WriteShortString(description)`, `3B Int24(objectiveIndex or 0)`, reflist block (`1B count` + per ref `1B typeIdx` + `3B id`).
- **Returns:** `nil` when count==0; else records `{spawnlist|nil, icon:number, description:string, objectiveIndex:number, reflist|nil}`.
- **Normalizations:** `data[1]` nil/`{}` → **nil**; `data[4]` nil → **`0`**; `data[5]` nil/`{}` → **nil** (writer coerces to `{}`, reader collapses count 0 to nil). `data[2]` and `data[3]` are **mandatory** — the writer errors on nil.
- Description uses `ReadShortString()`, so an empty description round-trips as `""`.
- **Raw-data reality:** `extraObjectives` (field 29) is **never present in any raw data file** — it comes exclusively from corrections.
- ⚠️ Writer uses `#value` for the count but `pairs(value)` for iteration; a sparse `extraObjectives` table desyncs the count from the payload and corrupts the stream.

### (h) Every normalization that changes what the reader sees vs. the raw data

1. **`nil` numeric → `0`** (types `s8 u8 u16 s16 u24 s24 u32`). Applies to every scalar field on every entity.
2. **`nil` string → `nil` via the literal `"nil"`** (types `u8string`, `u16string`); **and the reverse: a source string equal to `"nil"` becomes `nil`.**
3. **`""` string preserved** for `u8string`/`u16string`/`u8u16stringarray`/`extraobjectives.description` — but **`""` → `nil`** for `objective`/`spellobjective`/killobjective texts and for the `trigger` text (all use `ReadTinyStringNil`).
4. **`""` faction → `nil`**; **any non-`""`/`"A"`/`"H"` faction string → `"AH"`.**
5. **empty table `{}` → `nil`** for every count-prefixed collection type (`u8u16array u8s16pairs u16u16array u8s24pairs u8u24array u8s24array u16u24array u8u16stringarray spawnlist waypointlist objective spellobjective reflist extraobjectives`).
6. **`{0,0}` pair → `nil`** for `u12pair`, `u24pair`, `s24pair`. A pair with a nil component gets `or 0` first, so `{nil,0}`, `{0,nil}`, `{nil,nil}` all become `nil`.
7. **`nil` questgivers → `{}` (a 3-slot table)** and **`nil` objectives → `{}` (a 6-slot table)** — these are the only two types that turn nil into a truthy value.
8. **Objective/killobjective/extraobjective icon `nil` → `0`** (u8 or u24 write of `x or 0`).
9. **`extraObjectives[i][4]` (objectiveIndex) `nil` → `0`.**
10. **Spawn coordinate quantisation**: `x` is replaced by `floor(x*40.90)/40.90` — a lossy round to ~0.0244 units. `spawn[3]` (phase) of `0` or `nil` is dropped from the returned tuple. `{-1,-1}` is round-tripped exactly (via the zero encoding).
11. **Waypoint 3rd element dropped** — `waypointlist` never writes or reads a phase.
12. **Array compaction / reordering**: all array writers count with `pairs()` and iterate with `pairs()`. A sparse array is compacted; the on-wire order is `pairs()` order (deterministic and in-order for proper Lua sequences, arbitrary once a hole exists). No holes exist in raw data for these fields.
13. **Silent truncation on overflow (no assert in the default `raw` stream mode)**: `WriteByte` uses `stringchar(val)` (errors above 255), `WriteShort/WriteInt24/WriteInt` use `% 256` on each byte, `WriteInt12Pair` **masks to 12 bits**. In `Questie.db.profile.debugEnabled` the compiler picks the `raw_assert` stream (`compiler.lua:977`) which asserts ranges instead.
14. **Extra (non-numeric-key) fields are dropped**: `CompileTableCoroutine` only reads `entry[lookup[key]]` for keys in `*CompilerOrder`. In particular `entry.hidden` (set by `_QuestieDB:HideClassAndRaceQuests`, `QuestieDB.lua:2052/2058`) is never compiled — and `QuestieDB.lua:1502` `QO.isHidden = rawdata.hidden or ...` therefore always sees `nil` from the compiled path. (That function is also never called: only `DeleteGatheringNodes` is invoked, at `QuestieInit.lua:130`.)

### (i) All sites that mutate values returned from the database

Exhaustive grep over `Questie/Modules/` and `Questie/Database/` for `<expr>[n] = nil` and equivalents. **Only four real sites, all in `QuestieDB.GetQuest`:**

| file:line | code | why |
|---|---|---|
| `Questie/Database/QuestieDB.lua:1530-1532` | `if creatureObjective[3] == 0 then creatureObjective[3] = nil end` | undo the `icon nil→0` normalization for `objectives[1]` |
| `Questie/Database/QuestieDB.lua:1546-1548` | `if objectObjective[3] == 0 then objectObjective[3] = nil end` | same for `objectives[2]` |
| `Questie/Database/QuestieDB.lua:1567-1569` | `if itemObjective[3] == 0 then itemObjective[3] = nil end` | same for `objectives[3]` |
| `Questie/Database/QuestieDB.lua:1595-1597` | `if creditObjective[4] == 0 then creditObjective[4] = nil end` | same for `objectives[5]` killCredit icon |

Full context (`QuestieDB.lua:1526-1541`):
```lua
local objectives = QO.objectives
if objectives then
    if objectives[1] then
        for _, creatureObjective in pairs(objectives[1]) do
            if creatureObjective then
                if creatureObjective[3] == 0 then
                    creatureObjective[3] = nil
                end
                QO.ObjectiveData[#QO.ObjectiveData+1] = {
                    Type = "monster",
                    Id = creatureObjective[1],
                    Text = creatureObjective[2],
                    Icon = creatureObjective[3]
                }
            end
        end
    end
```

Notes:
- These mutations are safe against the compiled path because each `Query`/`QuerySingle` call **constructs fresh tables** (readers allocate). They are **not** safe against the *overrides* path: `handle.Query` returns the override table **by reference** (`compiler.lua:1199`, `ret[index] = override[rootIndex]`). A quest with an `objectives` override would have its correction table permanently mutated. In practice `GetQuest` results are memoised in `_QuestieDB.questCache` (`QuestieDB.lua:1732`), so the mutation only happens once per session per quest.
- `Questie/Modules/Journey/tabs/QuestsByZone/*.lua:88/203/295/302` `_QuestieJourney.lastZoneSelection[3] = nil` — **not** DB data, a UI selection tuple.
- `Questie/Database/compiler.lua:338` `ret[5] = nil` — inside the `objectives` reader itself, not a consumer mutation.
- `Questie/Database/QuestieDB.lua:1836` `QuestieDB.objectData[id][objectSpawnsKey] = nil` (`_QuestieDB:DeleteGatheringNodes`) mutates the **pre-compile source table**, not query results.

---

## 5. Is any field genuinely an EMPTY STRING `""` in the source data?

**YES — 6299 occurrences across the 5 expansions.** Method: every `*DB.lua` blob was `loadstring`-ed and walked (script `recon02_emptyscan.lua`); this avoids false positives from adjacent quotes or escapes.

### Per-file totals

| file | entries | empty strings | empty tables |
|---|---:|---:|---:|
| Classic/classicNpcDB.lua | 10119 | 1 | 0 |
| Classic/classicObjectDB.lua | 6645 | 80 | 0 |
| Classic/classicQuestDB.lua | 4244 | 467 | 0 |
| Classic/classicItemDB.lua | 14889 | 0 | 0 |
| TBC/tbcNpcDB.lua | 18499 | 2 | 0 |
| TBC/tbcObjectDB.lua | 9073 | 90 | 0 |
| TBC/tbcQuestDB.lua | 6519 | 491 | 0 |
| TBC/tbcItemDB.lua | 25010 | 2 | 0 |
| Wotlk/wotlkNpcDB.lua | 29601 | 3 | 0 |
| Wotlk/wotlkObjectDB.lua | 12959 | 874 | 0 |
| Wotlk/wotlkQuestDB.lua | 9086 | 726 | 0 |
| Wotlk/wotlkItemDB.lua | 36752 | 0 | 0 |
| Cata/cataNpcDB.lua | 46311 | 0 | 0 |
| Cata/cataObjectDB.lua | 17407 | 959 | 0 |
| Cata/cataQuestDB.lua | 15008 | 813 | 0 |
| Cata/cataItemDB.lua | 62086 | 0 | 0 |
| MoP/mopNpcDB.lua | 60068 | 0 | 0 |
| MoP/mopObjectDB.lua | 20081 | 961 | 0 |
| MoP/mopQuestDB.lua | 17549 | 830 | 0 |
| MoP/mopItemDB.lua | 80026 | 0 | 0 |

### Per entity type & field (all 5 expansions combined)

| entity | field | key index | compiler type | count | round-trips? |
|---|---|---:|---|---:|---|
| **object** | `name` | 1 | `u8string` | **2964** | ✅ yes (`""` → `""`) |
| **quest** | `objectivesText[i]` | 8 | `u8u16stringarray` | **3327** | ✅ yes (`""` → `""`) |
| **npc** | `name` | 1 | `u8string` | **6** | ✅ yes |
| **item** | `name` | 1 | `u8string` | **2** | ✅ yes |
| everything else | – | – | – | **0** | – |

First examples: `Classic/classicObjectDB.lua id=126337` (object name), `Classic/classicNpcDB.lua id=15672` (npc name), `TBC/tbcItemDB.lua id=751` (item name).

`""` inside `objectivesText` is a *deliberate* paragraph separator, e.g.
`Classic/classicQuestDB.lua`: `{"Kill 15 Kurzen Jungle Fighters.","","Return to Sergeant Yohwa at the Rebel Camp."}`
and in corrections, e.g. `Corrections/wotlkQuestFixes.lua:7882`, `Corrections/classicQuestFixes.lua:1924/2553/3789/4744/4751`, `Corrections/sodQuestFixes.lua:554/3374`, `Corrections/Automatic/sodBaseQuests.lua`.

### `""` from corrections (applied before compile)

- `Corrections/wotlkNPCFixes.lua:35` — `[npcKeys.friendlyToFaction] = "",` → this is the only source of the `""` faction case; it deliberately means "clear to nil".

### **Verdict for the storage format**

> **An empty-string marker IS required.** `""` occurs 6299 times in the source data and must be distinguishable from `nil` for the fields `object.name`, `npc.name`, `item.name` (all `u8string`) and `quest.objectivesText[i]` (`u8u16stringarray`), because Questie's compiler *does* preserve it there.
>
> Conversely, `""` must **collapse to `nil`** for `friendlyToFaction` (faction type) and for the `ReadTinyStringNil`-backed texts (`objective`/`spellobjective`/killobjective text, `trigger` text) — but no such `""` values exist in the source data today.

### Empty tables `{}` in the source

**Zero empty tables in any raw data file** (top-level or nested — scan checked every field of every entry). However **corrections use `{}` heavily** as a "clear this field" idiom, e.g.:
- `Corrections/classicNPCFixes.lua:25/28/62/76/85` — `[npcKeys.waypoints] = {}`
- `Corrections/classicNPCFixes.lua:143/158/161` — `[npcKeys.questStarts] = {}`
- `Corrections/classicItemFixes.lua:40/58/61/62/75/76` — `[itemKeys.npcDrops] = {}`, `[itemKeys.objectDrops] = {}`
- `Corrections/classicQuestFixes.lua:24-37` — `QuestieDB.questData[5640] = {}` (creates a fully-empty quest entry)

Occurrence counts of `{}` per corrections file (grep):
`Automatic/classicQuestReputationFixes.lua` 1611, `cataQuestFixes` 935, `wotlkQuestFixes` 554, `classicItemFixes` 300, `tbcQuestFixes` 287, `mopQuestFixes` 262, `classicQuestFixes` 252, `cataNPCFixes` 231, `classicNPCFixes` 139, `cataItemFixes` 126, `tbcNPCFixes` 87, `wotlkItemFixes` 63, `wotlkNPCFixes` 32, `tbcItemFixes` 17, `mopNPCFixes` 14, `classicObjectFixes` 14, `tbcObjectFixes` 10, `cataObjectFixes` 9, `sodNPCFixes` 9, `sodQuestFixes` 7, `mopItemFixes` 4, `sodObjectFixes` 3, `mopObjectFixes` 2, `wotlkObjectFixes` 2.

> **QuestieTDB must therefore also implement `{}` → `nil`** for collection-typed fields, or corrections that clear a field will stop working.

---

## 6. Additional structural facts derived from the raw data (all 5 expansions)

| observation | count |
|---|---:|
| `startedBy` (quest field 2) is `nil` | 11534 |
| `finishedBy` (field 3) is `nil` | 3017 |
| `objectives` (field 10) is `nil` | 21358 |
| `objectivesText` (field 8) is `nil` | 6941 |
| `triggerEnd` (field 9) is `nil` | 52161 (of 52406 quests) |
| `quest.name` is `nil` | 0 |
| `startedBy` has a nil hole (e.g. `{nil,{31}}`) | 4226 |
| `finishedBy` has a nil hole | 2415 |
| `objectives` has a nil hole | 20387 |
| `startedBy[3]` (itemStart) populated | 1774 |
| `finishedBy[3]` populated | **0** (never used) |
| `objectives[6]` (spellObjective) populated in raw data | **0** (corrections only) |
| `extraObjectives` (field 29) populated in raw data | **0** (corrections only) |
| `objectives[1..3]` records of length 3 (icon present) | **0** — icons only from corrections |
| `objectives[5]` (killCredit) records | 1176 |
| `triggerEnd` present but with no spawnlist | 19 |
| nil holes in any plain id array (`preQuestGroup`, `exclusiveTo`, `questStarts`, `npcDrops`, …) | **0** |
| npc spawns with a phase (3rd element) | 722 |
| object spawns with a phase | 675 |
| npc waypoint spawns with a 3rd element | **0** |
| npc `{-1,-1}` instance spawns | 17335 |
| object `{-1,-1}` instance spawns | 5081 |
| spawns whose quantised coords would become `{0,0}` (→ would falsely read back as `{-1,-1}`) | **0** |
| item `npcDrops` arrays with >255 entries (why `u16u24array`) | 1884 (max 412) |
| item `vendors` arrays with >255 entries | 24 (max 309) |
| npc/object/quest `u8`-counted arrays with >255 entries | **0** |

### ⚠️ Real defect found in the raw data: 12-bit spawn-coordinate overflow

**420 spawn coordinates in `MoP/mopNpcDB.lua` overflow the 12-bit `Int12Pair` encoding.** `_WriteInt12Pair` (QuestieStream.lua:408) masks rather than validates, so these are silently corrupted today (and would `assert` under `debugEnabled`/`raw_assert`).

Examples:
```
MoP/mopNpcDB.lua id=58898 zone=6052 coord={36.46,138.13}  scaled={1491,5649}   -- y overflows
MoP/mopNpcDB.lua id=61071 zone=365  coord={2128.7,517}    scaled={87063,21145}
MoP/mopNpcDB.lua id=61080 zone=365  coord={1387.78,2329.93} scaled={56760,95294}
```
Observed raw ranges: `npc.spawns.x ∈ [0.01, 2943.67]`, `npc.spawns.y ∈ [0.02, 6025.32]` (object spawns are all sane, ≤ 99.84).

> QuestieTDB storing raw floats will **not** reproduce this corruption — that is a *behavioural difference* (an improvement) that must be a conscious decision, because any consumer relying on the wrapped coordinates would change behaviour.

---

## 7. Consumption layer: `GetDBHandle`, skip maps, pointers, overrides

### `BuildSkipMap` (compiler.lua:1049-1076)
```lua
function QuestieDBCompiler:BuildSkipMap(types, order)
    local skipmap, indexToKey, keyToIndex = {}, {}, {}
    local ptr, haveDynamic, lastIndex = 0, false, nil
    for index = 1, #order do
        local key = order[index]
        local typ = types[key]
        indexToKey[index] = key
        keyToIndex[key] = index
        if not haveDynamic then skipmap[key] = ptr end
        if QuestieDBCompiler.dynamics[typ] then
            if not haveDynamic then lastIndex = index end
            haveDynamic = true
        else
            ptr = ptr + QuestieDBCompiler.statics[typ]
        end
    end
    skipmap = {skipmap, lastIndex, ptr, types, order, indexToKey, keyToIndex}
    return skipmap
end
```
`statics` (compiler.lua:865-877): `u8=1 s8=1 u16=2 s16=2 u24=3 s24=3 u32=4 faction=1 u12pair=3 u24pair=6 s24pair=6`
`dynamics` (compiler.lua:844-863): everything else that's actually used, including `waypointlist`.

Computed layouts (script `recon02_skipmap.lua`):

| entity | static-prefix bytes (`lastPtr`) | first dynamic index (`lastIndex`) |
|---|---:|---:|
| npc | **20** | 10 (`name`) |
| object | **4** | 3 (`name`) |
| quest | **59** | 21 (`name`) |
| item | **17** | 10 (`name`) |

npc static offsets: `minLevelHealth`=0, `maxLevelHealth`=4, `minLevel`=8, `maxLevel`=9, `rank`=10, `zoneID`=11, `factionID`=13, `friendlyToFaction`=15, `npcFlags`=16; `name`=20 (first dynamic, still gets a direct offset).
object: `zoneID`=0, `factionID`=2, `name`=4.
quest: `requiredLevel`=0, `questLevel`=1, `requiredRaces`=3, `requiredClasses`=7, `sourceItemId`=9, `zoneOrSort`=12, `requiredSkill`=14, `requiredMinRep`=17, `requiredMaxRep`=23, `nextQuestInChain`=29, `questFlags`=32, `specialFlags`=35, `parentQuest`=37, `requiredSpell`=40, `requiredSpecialization`=43, `requiredMaxLevel`=46, `breadcrumbForQuestId`=47, `availableUntilCompleted`=50, `availableStartingWith`=53, `disabledByQuest`=56, `name`=59.
item: `flags`=0, `startQuest`=4, `itemLevel`=7, `requiredLevel`=9, `foodType`=10, `ammoType`=11, `class`=12, `subClass`=13, `teachesSpell`=14, `name`=17.

### `QuerySingle` / `Query` contracts (compiler.lua:1113-1367)

- Two variants are generated depending on whether an `overrides` table was passed. All four DB handles get one (`QuestieDB.lua:293-299` pass `QuestieDB.{npc,quest,object,item}DataOverrides`), so the **override branch is always the live one**.
- `QuerySingle(id, key)`:
  - Override hit → returns `override[keyToRootIndex[key]]`, **but with the empty-table→nil normalization applied** (compiler.lua:1136-1141):
    ```lua
    if type(override[kti]) ~= "table" or next(override[kti]) then
        return override[kti]
    else
        -- We want to return nil if the table is empty, to match the compiler behavior
        return nil
    end
    ```
  - `pointers[id] == nil` → returns `nil` (a missing entity yields nil for every key).
  - Unknown key → `Questie:Error("ERROR: Unhandled db key: " .. key)` and `nil`.
- `Query(id, keys)` returns a **positional array** parallel to `keys`, `nil` when the id has no pointer *and* no override. **It does NOT apply the empty-table→nil normalization to override values** (compiler.lua:1198-1199) — an inconsistency with `QuerySingle`.
- `QueryValidator(id, keys)` is `Query` plus a per-field cross-check that the skipper and the reader advance the stream identically.
- `handle.pointers` is exposed as `QuestieDB.{NPC,Quest,Object,Item}Pointers` (`QuestieDB.lua:307-310`) — used as the authoritative "does this id exist" set.
- Pointer map format (compiler.lua:896-928): `3B count` then `count × (3B id, 3B offset)`. **All ids and offsets are u24 — a hard 16,777,215 cap on both entity ids and the binary blob size.**
- ⚠️ The stream is **shared mutable state**: `handle.stream` is a single stream object whose `_pointer` is moved on every query. There is exactly one stream per handle and it is not reentrant.

### Compile driver (compiler.lua:942-1047)
- Iterates ids `0..max_id` to get deterministic order, builds `pointerMap[id] = stream._pointer` before writing the entry's fields in `*CompilerOrder` order.
- Type check before each write (compiler.lua:1025-1028):
  ```lua
  if v and not supportedTypes[type(v)][t] then
      error("|cFFFF0000Invalid datatype!|r   " .. kind .. "s[" .. tostring(id) .. "]."..key..": \"" .. type(v) .. "\" is not compatible with type \"" .. t .."\"")
  end
  ```
  `supportedTypes` (compiler.lua:63-100) maps Lua type → allowed compiler types. Note `faction` is listed under `"string"` only, so a numeric faction would error; `boolean` has **no** entry, so a boolean value would index a nil table and throw.
- Output goes to `Questie.db.global[databaseKey.."Bin"]` / `[...".."Ptrs"]` (or the `.sod` sub-table for SoD).

### Pre-compile mutation pipeline (order matters)
`QuestieInit.lua:110-135` `loadFullDatabase()`:
1. `QuestieInit:LoadBaseDB()` — `loadstring` the 4 blobs into `QuestieDB.{npc,object,quest,item}Data`.
2. `QuestieCorrections:Initialize()` — `_LoadCorrections` writes into `QuestieDB.<table>[id][key]`, **creating missing entries as `{}`** (`QuestieCorrections.lua:236-238`); then the auto `requiredRaces` patch (`QuestieCorrections.lua:313-350`) sets `ALL_ALLIANCE`/`ALL_HORDE` on quests whose questgivers are single-faction. Finally `MinimalInit()` populates the four `*DataOverrides`.
3. `Townsfolk.Initialize()`
4. `l10n:Initialize()` (`Localization/l10n.lua:45-97`) — **overwrites** `itemData[id][name]`, `questData[id][name]`, `questData[id][objectivesText]`, `npcData[id][name]`, `npcData[id][subName]` (subName may be set to nil), `objectData[id][name]` with locale strings.
5. `QuestieDB.private:DeleteGatheringNodes()` (`QuestieDB.lua:1827-1838`) — nils out `objectData[id][spawns]` for 24 gathering-node object ids.
6. `QuestieCorrections:PreCompile()` — RDP waypoint optimization on every npc and object.

Then `QuestieDBCompiler:Compile()`.

Recompile trigger (`QuestieInit.lua:161`): addon version change, UI locale change, `WOW_PROJECT_ID` change, or `dbIsCompiled == false`.
