# 04 — Npc, Item, and Object entity types

**What to build:** All four entity databases are readable, not just quests. Each has its own schema, its own field types, and its own serialization quirks — spawn lists and waypoints in particular are the largest and most structure-heavy values in the whole database.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] `NpcDB`, `ItemDB`, and `ObjectDB` expose the same getter surface as `QuestDB`
- [ ] Each type's schema is taken from Questie's current key enum, not from the prototypes
- [ ] Spawn and waypoint structures round-trip exactly, including nested coordinate tables
- [ ] Nil and empty semantics hold identically across all four types
- [ ] Round-trip verification is green for all four types on Vanilla
- [ ] Adding a further entity type requires no change to the shared getter layer
