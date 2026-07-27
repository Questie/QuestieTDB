# 07 — Source/baked equivalence test

**What to build:** Proof that what a contributor sees in source mode is exactly what ships in baked mode. Both readers are exercised over the entire database and every field, and any divergence fails the build.

This is the load-bearing test in the system. Unlike the compiled/TOC differential, it never retires — two permanent read modes mean it guards forever.

**Blocked by:** 04, 06

**Status:** ready-for-agent

- [ ] Every entity, every field, both modes, compared exhaustively
- [ ] Nil versus empty-table divergence is caught specifically, since it is the predicted failure mode
- [ ] A deliberately introduced divergence makes the test fail — it is proven to be able to fail
- [ ] The test runs offline through the emulator, with no game client
- [ ] It runs fast enough to sit in CI on every commit, or is split so that a representative subset does
