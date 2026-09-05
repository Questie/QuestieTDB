# Support data

QuestieTDB publishes Questie's zone mappings, quest XP, faction templates, drop tables, and
drop-table Corrections as plain Lua values through `LibQuestieDB.Support`. These datasets are
consumed as whole tables, so they do not use the TOC metadata store. The public access points
and value examples are documented in [`api.md`](./api.md#support-data).

## Flavor selection

Baked TOCs list the shared inputs and only the variant inputs for their flavor. The committed
Source TOC must work on every supported client, so it lists each variant once. Scope markers
admit assignments for the active flavor and direct all other assignments to temporary,
unpublished modules. Rejected values never appear through `Support.Get` or `Support.GetAll`.

The selected data follows Questie's flavor TOCs:

- Vanilla, TBC, Wrath, and Cata use the shared area/UI map tables plus their own quest XP,
  faction-template, and drop-table variant.
- Mists uses the MoP area/UI map tables, quest XP, and faction templates.
- Mists loads the MoP drop table followed by the Cata drop table. The cumulative order is
  intentional and matches Questie.

Installing the support shim starts with an empty published module set. This prevents a flavor
loaded later in the emulator from retaining modules or values selected for an earlier flavor.

## Value shapes

Copied values keep the shape authored by Questie. In particular, zone maps and item-drop
sources that Questie's wrappers pass to `loadstring` remain strings. Quest XP, faction
templates, zone IDs, dungeon records, and item-drop Corrections remain tables.

A dungeon's optional second slot is a dense `alternativeAreaIds` list, not a scalar area ID:

```lua
---@class DungeonZoneEntry
---@field [1] string name
---@field [2] AreaId[]? alternativeAreaIds
---@field [3] AreaId parentZone
---@field [4] { [1]: AreaId, [2]: number, [3]: number }[] dungeonLocations
```

Consumers should preserve these raw types when binding the values to their existing wrapper
modules.

## Copied-data inventory

[`tools/support-inventory.lua`](../tools/support-inventory.lua) is the authoritative inventory
of all 24 copied support files. Each entry records:

- `file`: the local QuestieTDB path;
- `questie`: the source path in the checkout pinned by `QUESTIE_COMMIT`;
- `fields`: every public module field the file assigns;
- `luaFields`: fields intentionally published as Lua source strings.

Update the inventory together with `config.supportData` whenever Questie adds, removes, or
moves a support input. Source-mode grouping in `config.supportSourceGroups` must continue to
produce the same effective selection as `config.supportData.perFlavor`. The fidelity gate
fails for unmapped configured inputs, unmapped applicable inputs in Questie's TOCs, and unused
inventory entries.

## Fidelity gate

Run the focused check against the pinned sibling checkout:

```sh
lua5.1 test.lua support support-fidelity
```

`support-fidelity` executes Questie's applicable support inputs and compares their effective
module values with QuestieTDB for every flavor and both factions. It checks configured Source
and Baked loading, the committed Source TOC, and generated Baked TOCs when present. It also
compares each copied input independently so a later assignment cannot hide stale data.

Comparison is semantic rather than byte-based. Formatting-only changes do not fail. Fields
listed in `luaFields` retain their published source type while their decoded table values are
compared, so an equivalent string-to-table change still fails as a public shape change.
Dungeon `alternativeAreaIds` receive a separate dense-list shape check.

The suite runs with an unfiltered `lua5.1 test.lua`, including CI's unit job and the release
quality job, and in the `test` job of `tools/check.sh all`. Issue #19's aggregate side-channel
gate can invoke the focused command above directly.
