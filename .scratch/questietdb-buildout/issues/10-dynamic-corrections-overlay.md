# 10 — Dynamic Corrections and the Correction Overlay

**What to build:** Corrections that cannot be known before Generation — faction, season, expansion, consumer settings — are applied at query time, and any addon can contribute them. Every consumer reads one composed view; nobody gets a private one.

**Blocked by:** 06, 09

**Status:** ready-for-agent

- [ ] Dynamic Corrections register per owner and are applied when that owner asks for them to be
- [ ] Applying one owner's corrections does not require or disturb another owner's
- [ ] Reads resolve through the overlay first and fall back to base data
- [ ] Base data is never written to at runtime, in either read mode
- [ ] Re-applying an owner's corrections is idempotent — the composed view is rebuilt, not accumulated into
- [ ] A correction that stops applying can be withdrawn, which the previous merge-only approach could not do
- [ ] Precedence is last-applied-wins across owners, and load order within an owner
- [ ] Cached values are invalidated when the composed view changes
- [ ] A debug mode reports when one owner overrides another on the same field
