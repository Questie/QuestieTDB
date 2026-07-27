# 15 — Public API surface

**What to build:** Another addon can depend on this database: read entity fields, discover the schema, register its own corrections, and detect an incompatible version — all through a documented surface that does not change when internals do.

Questie is the first consumer, but nothing in the API assumes it.

**Blocked by:** 10

**Status:** ready-for-agent

- [ ] Field access, bulk field access, and ID enumeration are exposed per entity type
- [ ] The schema is exposed so consumers can name fields rather than index them
- [ ] Correction registration is public, and a third-party addon can use it without special treatment
- [ ] A base-data read that bypasses the overlay is available for tooling and debugging
- [ ] The winning correction's owner is discoverable for a given field, for bug reports
- [ ] A contract version is published, and mismatch is detectable by a consumer at load
- [ ] The API is documented well enough that a third-party author needs no source reading
