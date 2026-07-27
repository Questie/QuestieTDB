# 01 — Tracer bullet: quest name end to end

**What to build:** A player with QuestieTDB installed can query a quest name from the TOC metadata store in-game. Only the `name` field, only Vanilla, only quests — but the whole path works: Questie's raw entity data is read, serialized, emitted as TOC metadata, and decoded back at runtime.

This is the spine every later ticket widens. Keep it narrow deliberately: no chunking, no corrections, no other fields.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A loader reads Questie's `classicQuestDB.lua` under a mocked environment and returns the quest table plus its **Database Key Enum**
- [ ] `generate.lua` emits `QuestieTDB_Vanilla.toc` containing one `## X-<id>-1: <name>` line per quest
- [ ] The addon exposes `QuestDB.name(id)`, reading through `C_AddOns.GetAddOnMetadata`
- [ ] In a live client, `/dump QuestDB.name(2)` returns `Sharptalon's Claw`
- [ ] Generation runs with a plain `lua` interpreter — no `lfs`, no other C dependency
- [ ] Repeated generation of unchanged input produces a byte-identical `.toc`
