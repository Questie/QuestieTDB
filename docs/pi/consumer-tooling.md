# `-pi` idea: consumer tooling and test fixtures

Smaller harvest items, each independently adoptable.

## LuaLS consumer type stub — recommended follow-up

`-pi` shipped `src/types/LibQuestieDB.lua`, a `---@meta` file (checker-only, never listed
in any TOC) giving consumers typed autocomplete for the whole public API, plus a
compile-check consumer exercising it (`test/luals-consumer/consumer.lua`). This repo has
LuaLS annotations internally but no consumer-facing stub.

Write it **fresh against this repo's current API** — packed `GetAll` (`values.n`),
owner-scoped Corrections, ranged `RequireContract`, and fresh-per-read ownership notes in the
doc comments. Do not port `-pi`'s stub: it types the retired API (frozen
returns, its `GetAll` shape) and one field wrongly (`friendlyToFaction` as
`number|nil` where the normalized contract is string-valued). A stale stub misleads
worse than none; pair it with a CI check that the stub's function list matches
`docs/api.md`.

## Per-validator positive + negative fixture pairs

`-pi`'s `test/validators.lua` carried, for every validator check, a literal corruption
and the exact expected diagnostic (`test/validators.lua:59-63`: name, check slug,
`corrupt = function(state) ... end`, `expected = "current=[] expected=[100]"`). A
validator whose failure mode is never exercised is trusted, not tested. This repo's
validators have committed baselines (drift-visible) but no negative fixtures — the
reconstruction/equivalence self-proof pattern already adopted here should extend to
`validators/checks.lua`.

## TOC test fixtures worth recreating

- `test/fixtures/chunked-metadata-crlf.toc` — a chunked-value artifact with CRLF line
  endings, `.gitattributes`-pinned `-text -diff` so git cannot normalize it. This repo's
  emulator handles CRLF but has no committed CRLF fixture proving it stays true.
- `test/fixtures/entity-structures.toc` — a hand-written minimal artifact exercising
  every structure serializer in isolation.
- `emulator/load_addon_toc.lua` — models WoW's *keep-loading-after-file-error* behavior,
  enabling corrupted-file fixtures that prove a broken correction file cannot take down
  the whole addon load. This repo's source-mode init pcall covers the runtime half; the
  emulator-side model is the missing test half.

## Emulator dual mode

`-pi`'s metadata emulator offered `MODE_TRANSPARENT` (chunks pre-joined, convenient) and
`MODE_RAW_CLIENT` (reader must reassemble, faithful), with every production-path test
forced to raw-client mode. This repo took the opposite single stance (raw always) — which
is stricter and fine; noted only so nobody re-adds a transparent mode to production-path
tests for convenience.

Status: **recommended follow-ups** — the type stub and validator negatives first; the
fixtures whenever the test suite next gets attention.
