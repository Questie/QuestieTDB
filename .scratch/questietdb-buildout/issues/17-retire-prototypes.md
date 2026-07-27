# 17 — Retire the prototypes to `.retired`

**What to build:** The `Getters` and `toc-database` prototype folders are moved out of the active working area into a `.retired` folder at the workspace root, once everything worth keeping has been ported.

They are **moved, not deleted**. Nothing is removed from any remote, and nothing is destroyed locally — retiring is reversible by moving a folder back.

`GetterDB` is the reason this matters: it is a nested git repository with **no remote**, so it exists only on this machine. Moving rather than deleting protects it from the cleanup itself, but not from machine loss — it should be pushed to a remote independently of this ticket.

Do not confuse this with removing the consumer's compiler. That is a separate retirement, in a different repository, gated on entirely different work.

**Blocked by:** 03, 09

**Status:** ready-for-agent

- [ ] `GetterDB` has an off-machine copy, independent of this folder
- [ ] The serializer, including its domain-specific compaction, has been ported and is in use
- [ ] The corrections registry has been ported and is in use
- [ ] The storage format is fully described in this repo's documentation, verified by generating from the spec rather than by reading prototype code
- [ ] No file in this repo references the prototypes
- [ ] Both prototype folders are moved under `.retired` at the workspace root
- [ ] `.retired` carries a README marking it reference-only and warning against the intermediate export format
- [ ] `.retired` is excluded from version control
