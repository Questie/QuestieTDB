# 11 — Remaining correction sets

**What to build:** Every expansion's corrections live here, not in Questie. TBC, Wotlk, Cata, MoP, and the Season of Discovery sets are moved across and produce the same entity values they do today.

Season of Discovery is the interesting one: it is a Dynamic Correction set over the Era database rather than a separate database, which is what lets Questie's parallel SoD database be deleted later.

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] TBC, Wotlk, Cata, and MoP correction sets are moved and applied in expansion order
- [ ] Season of Discovery loads as Dynamic Corrections over Era, with no separate generated database
- [ ] Load-order constants are used rather than literal numbers, and the intended SoD ordering is settled rather than inherited
- [ ] Correction files reference constants owned here, not Questie's runtime modules
- [ ] Text carried by corrections is stored in English, to be translated at render time by the consumer
- [ ] Entity values match what Questie produces today for a sampled set across every expansion
