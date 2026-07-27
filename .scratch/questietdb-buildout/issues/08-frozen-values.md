# 08 — Frozen values

**What to build:** The database owns the tables it hands out, and accidental mutation fails loudly instead of silently corrupting shared data. A consumer that genuinely needs to modify a value takes its own copy, deliberately and visibly.

Enforcement is a VM-level flag rather than a metatable proxy, so reads are unaffected — see `docs/table.freeze.md`.

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] Table values returned from either read mode are frozen
- [ ] Source mode's base data is frozen after load, so corrections and consumers cannot corrupt it
- [ ] Freezing is capability-detected, since the API does not exist in standard Lua 5.1
- [ ] The offline harness has a pure-Lua substitute, so the guard is present in CI rather than silently absent
- [ ] No frozen table carries `__newindex` — writes must raise, not redirect
- [ ] Scalar fields are cached without freezing, since strings and numbers cannot be mutated
- [ ] Attempting to mutate a returned table raises an error, demonstrated by a test
