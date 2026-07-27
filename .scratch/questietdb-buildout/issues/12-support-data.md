# 12 — Support data

**What to build:** Game reference data that is consumed as whole tables — zone mappings, quest XP, drop tables, faction templates — ships from here rather than from Questie. It stays plain Lua rather than TOC metadata, because callers want the whole table, not lazy per-field access.

Can start immediately alongside the tracer bullet; nothing else blocks on it until the validators need zone data.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Zone, quest XP, drop table, and faction template data ship from this addon
- [ ] Each is exposed for consumption as a whole table
- [ ] Only the data moves — the modules that wrap it stay with the consumer
- [ ] Per-flavor data is selected correctly for each client
- [ ] The drop-table corrections file is reconciled with the corrections system rather than left as a stray data file
