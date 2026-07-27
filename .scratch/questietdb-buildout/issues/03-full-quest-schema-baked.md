# 03 — Full Quest schema in baked mode

**What to build:** Every field of every Vanilla quest is readable from the TOC metadata store, with values indistinguishable from what Questie's compiler returns today. This is where the storage format becomes real: long values split, absent values behave correctly, and the full ID set is queryable.

Nil and empty semantics are specified in `docs/storage-format.md` and are not open to interpretation — they must match Questie exactly, because ~290 call sites depend on them.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] All 36 quest fields are emitted and readable, each with its declared type
- [ ] Numeric fields return `0` when the source value was nil — never `nil`
- [ ] Table fields return `nil` when the source value was nil or an empty table — never an empty table
- [ ] Empty strings survive the round trip and stay distinct from nil
- [ ] Values longer than the chunk threshold split correctly, and splits never land inside a UTF-8 sequence
- [ ] `QuestDB.GetAllIds()` and `GetAllIds(true)` return the full ID list and hashmap
- [ ] The generic getter and the named getter return identical values for the same field
- [ ] Round-trip verification is green across all Vanilla quests
