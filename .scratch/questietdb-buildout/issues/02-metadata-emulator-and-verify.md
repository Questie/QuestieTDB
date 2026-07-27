# 02 — Metadata emulator and round-trip verification

**What to build:** Anyone can prove a generated database is correct without launching WoW. A plain-Lua emulator loads a generated `.toc` and stands in for the client's metadata API, and a verifier confirms every stored value decodes back to the value it came from.

This is what makes every later ticket self-checking, and it is the first thing CI will run.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] The emulator parses a generated `.toc` into a key/value map and installs `C_AddOns.GetAddOnMetadata`
- [ ] It reassembles **Chunked metadata values** transparently, so callers never see chunk markers
- [ ] `verify.lua` compares decoded output against the source data for every entity and every field, and exits non-zero on any mismatch
- [ ] Verification passes for the ticket 01 output
- [ ] A deliberately corrupted `.toc` makes verification fail — the check is proven to be able to fail
- [ ] The emulator is usable as a library, since Questie's test harness will consume it later
