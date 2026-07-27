# 09 — Corrections registry and Static Corrections

**What to build:** Authored fixes to entity data are folded into the database during Generation, and a contributor can add one by writing a correction file and regenerating — nothing else.

The registry is ported from the prototype's, which already solves load-order namespacing and collision handling. Static Corrections are a build-time input and never ship to end users.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Corrections register with an owner, entity type, name, and load order
- [ ] Load-order collisions are resolved deterministically and reported, not silently overwritten
- [ ] Static Corrections are applied during Generation and appear in the generated artifact
- [ ] Correction data is held behind functions so it materialises only when applied
- [ ] The Era correction set is moved across and produces the same entity values it does in Questie today
- [ ] Static Correction files are excluded from the shipped artifact
- [ ] Deleting a correction and regenerating removes its effect
