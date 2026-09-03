# Plan: CBOR scalar rows and CBOR tables in Baked mode

Implements `docs/adr/0010-cbor-rows-and-tables.md`, decided 2026-09-03: scalar rows per
entity as the middle ground between today's per-field literals and pre-decoded columns,
trading the columns' read speed for memory that follows what a session touches. Read the ADR
first, then
`docs/storage-format.md`, `src/read/baked.lua`, `src/read/shared.lua`, `generator/encode.lua`
and `generate.lua`. The numbers behind every decision are in `docs/read-performance.md` and
`docs/client-metadata-probes.md` §10.

**Do not commit.** Leave every change in the working tree for review. Do not touch
`tools/probe-addon/TDBProbe.toc` beyond restoring it with `git checkout` if it is dirty.

Assume `C_EncodingUtil` exists on every supported client. Do not add a literal fallback path.

## What exists already

- `tools/prototype-cbor/gen.lua` and `proto.lua`: a throwaway prototype of exactly this layout,
  generated from the real composition pipeline, verified in the client against every field of
  every Vanilla entity with zero differences, and benchmarked on Vanilla and Mists. It is the
  reference for the row encoding, the presence mask, and the table byte cache. It is not
  production code: no overlay, no l10n, globals, its own chunk reader.
- `../../Questie-PR-Review/cli/mocks/BlizzardCBOR.lua` plus its tests and fixtures: the offline
  CBOR codec, already verified byte-compatible with `C_EncodingUtil` on live captures.
- `../Questie/Libs/LibDeflate/LibDeflate.lua`: pure Lua zlib, runs under `lua5.1`; its
  `CompressZlib` output decodes with `C_EncodingUtil.DecompressString(bytes, 1)` (verified).
- The offline harness: `emulator/`, `verify.lua`, `equivalence.lua`, `test.lua`,
  `tools/differential/golden.py`, `tools/check.sh`. All of it keeps working once the emulator
  can stand in for `C_EncodingUtil`.

## Storage format, precisely

Per entity type, in the flavour TOC, after the header:

```
## X-<Type>-IDS: <base64 of zlib(CBOR(ids array))>        chunked with ~N~ as any value
## X-<Type>-<id>-S: <base64 of CBOR(row)>                  one per entity that stores anything
## X-<Type>-<id>-<fieldIndex>: <base64 of CBOR(table)>     table fields only, present only
```

`row`:

```lua
{
  [fieldIndex] = scalar,      -- every number or string field hasStoredValue says to store
  p = bitmask,                -- sum of 2^(fieldIndex - 1) over stored table fields; absent when 0
}
```

Rules, all inherited from `normalize.field` and `encode.hasStoredValue`:

- A scalar is stored when `hasStoredValue` says so: numbers ≠ 0, any string including `""`.
- A table is stored when non-empty after normalization. Its key exists and its bit is set.
- Constant fields are never stored.
- An entity with no stored scalar and no stored table has no `-S` key. It still exists: it is
  in `IDS`.
- `X-<Type>-IDS-LIST` is no longer emitted. `X-l10n-<Type>-IDS-LIST` and every l10n key are
  unchanged.
- Chunking, the 1,023-byte line limit and the `~N~` marker are unchanged. `~E~` and `~Q~` are
  not used for entity values any more; `codec.lua` keeps them for l10n.
- `X-Contract-Version: 2`.
- The generator errors if `meta.fieldCount > 52`.

Measured sizes from the prototype, base64 text in the TOC:

| Flavour | Rows plus ids | Table keys | Entity data total | Today |
| --- | ---: | ---: | ---: | ---: |
| Vanilla | 1.75 MB | 4.9 MB | 6.6 MB | 8.7 MB |
| Mists | 9.6 MB | 18.2 MB | 27.8 MB | not measured |

## Work breakdown

Each step names the files it owns. Steps 1 to 3 are independent of each other. Do them in
order anyway; each later step has a check that depends on the earlier ones.

### 1. Vendor the offline codecs

- Create `generator/vendor/BlizzardCBOR.lua` from `Questie-PR-Review/cli/mocks/BlizzardCBOR.lua`,
  with a header comment naming the source path and commit, and the same for its compatibility
  fixtures (`BlizzardCBORCompatibilityCases.lua`, `...Fixtures.lua`) so the vendored copy can
  be re-verified here.
- Create `generator/vendor/LibDeflate.lua` from `Questie/Libs/LibDeflate/LibDeflate.lua`.
  Keep its zlib licence header intact.
- Create `generator/base64.lua`: `encode(bytes)` and `decode(text)`, standard alphabet with
  `=` padding, pure Lua 5.1 arithmetic. The prototype has an encoder to start from.
- Add deterministic map-key ordering to the way the generator calls the CBOR encoder: a
  wrapper in `generator/cbor.lua` that rebuilds maps with sorted keys before encoding, or an
  option on the vendored encoder if that is cleaner. The determinism gate in `tools/check.sh`
  is the check.
- `test.lua`: suites for base64 round trip including all three padding cases, the vendored
  CBOR against its fixtures, LibDeflate zlib round trip, and deterministic encoding of a map
  built in two different insertion orders.

Check: `lua5.1 test.lua base64 cbor deflate`.

### 2. Emulator stand-ins for `C_EncodingUtil`

- `emulator/client.lua`: install `C_EncodingUtil` with `DecodeBase64`, `EncodeBase64`,
  `DecompressString(bytes, method)` for methods 0, 1, 2 via LibDeflate, `CompressString`,
  `DeserializeCBOR`, `SerializeCBOR`. Baked mode needs the client stand-in now; today it needs
  only the metadata emulator, so make sure `verify.lua`, `equivalence.lua`, the differential
  dumps and Questie's harness path (see the comment at the top of `emulator/metadata.lua`)
  all install it before loading the addon.
- The stand-ins must reject what the client rejects: a bad checksum on method 1 and 2 raises,
  and `DeserializeCBOR` on trailing bytes raises. An artifact that only decodes in the
  emulator is worthless.

Check: a `test.lua` suite that round-trips an id header and a row through the stand-ins,
plus a negative control that corrupts one byte and expects the error.

### 3. Generator

- `generator/rows.lua` (new): `build(meta, row)` returning the scalar row table with `p`, or
  nil when nothing is stored, following the prototype's loop: normalize, decide storage with
  `encode.hasStoredValue`, scalars into `[f]`, tables set a bit. Unit-testable without
  encoding.
- `generator/encode.lua`: `encode.field` for table fields returns base64 CBOR. Scalars no
  longer go through `encode.field` in generation; `hasStoredValue` stays the single decision
  point. `encode.string` and the marker-collision logic stay for the l10n writer and are
  documented as l10n-only. `encode.idList` becomes the compressed `IDS` blob encoder.
- `generate.lua` `writeEntityMetadata`: per id, write table keys and then the `-S` row;
  after the loop, write `X-<Type>-IDS`. Everything goes through `lib.writeMetadata` so
  chunking and the key-collision check are shared. Report row count and byte totals in the
  summary line.
- `src/config.lua`: `contractVersion = 2`.
- Field-count guard as above.

Check: `lua5.1 generate.lua Vanilla` produces a TOC; `awk 'length > 1023'` finds no line;
a `test.lua` suite for `rows.build` on a fixture covering an entity with nothing stored, a
constant field, an empty string against an absent string, a zero against an absent number,
and a table-present bit.

### 4. Baked backend

`src/read/baked.lua`, keeping the file's contract: `readField`, `tableChunk`, `getAllIds`,
plus `getStored` for the l10n overlay. Add one function, `scalarRow(id)`.

- On `CreateBackend(meta)`: decode `X-<Type>-IDS` through `getStored` and `C_EncodingUtil`
  (base64, zlib method 1, CBOR); keep the list and build the `[id] = true` map in a loop.
  This is the only decode at load.
- `scalarRow(id)`: `getStored("X-<Type>-<id>-S")`, base64, CBOR; nil when the key is absent.
  No caching here; `shared.lua` owns the cache.
- `readField(id, f)`: constants as today; scalars via `scalarRow(id)[f]`, nil when absent so
  `shared.lua` applies defaults and existence gating; tables decoded fresh from the key, nil
  when the row's `p` bit is clear or the row is absent. `GetRaw` is the caller and stays
  uncached and simple.
- `tableChunk(id, f)` takes the already-decoded row as a third argument so it can consult
  `p` without a second row read: nil when the bit is clear; otherwise a producer closing over
  the decoded base64 bytes returning `DeserializeCBOR(bytes)`. Rename to `tableProducer` and
  update the single caller and the comment in `shared.lua`; do not keep both names.
- Remove the `codec.chunkCount` pattern match from the hot path in `getStored`: check the
  first byte for `~` before consulting it.

### 5. Shared read path

`src/read/shared.lua`, `get` and the cache only:

- On a cache miss for an id in Baked mode, ask `backend.scalarRow(id)`; the decoded row
  becomes the cache row for that id (the `p` slot is harmless under a string key, or copy the
  scalars into a fresh cache row if you prefer the cache to own its tables; pick one and say
  why in the comment). Every scalar of that entity is now cached in one step.
- Table reads go through `backend.tableProducer(id, f, row)` and are cached as producers, as
  today. Absent tables cache `NIL` or the never-nil default producer, as today, but without a
  client call.
- Overlay probe, l10n hook, defaults and existence gating are unchanged and sit above all of
  this. An l10n-translated value overwrites the scalar in the cache row, as today.
- Unknown ids create no cache entry: an absent row plus `unionMap[id] ~= true` returns nil
  before anything is stored.
- Source mode is untouched. If `get` needs to know, make the backend declare
  `backend.hasScalarRows = true` rather than testing `LibQuestieDB.mode`.
- Update the header comment and the cache comment to describe the new policy in one place.

### 6. Codec cleanup

`src/meta/codec.lua`: remove `compileTable`, `decodeTable`, `decodeIdList`, `decodeIdMap`
and the `table` decoder if nothing calls them after steps 4 and 5. `overlay.lua` still uses
`decodeTable` for translated list fields; if it is the only caller, move that function next
to its caller. Do not leave dead code with an "in case" comment.

### 7. Verifier and gates

- `verify.lua`: expected to pass unchanged. It reads every field through `entity.GetRaw`
  and compares against normalized expectations with `lib.deepEqual`, and its id-list check
  already goes through `entity.backend.getAllIds()`. Keep its raw-artifact scan for the two
  client parser constraints. If it fails, the defect is in step 4.
- `equivalence.lua`: should pass unchanged. If it does not, the bug is in steps 4 or 5.
- `tools/differential/golden.py check Vanilla` must pass without a refresh. Composed reads
  did not change, only their storage. A golden diff here is a defect.
- `tools/differential/compiler_diff.py`: the baseline counts must not move.
- `tools/check.sh all` green on every flavour, then `tools/check.sh determinism` green.
- `lua5.1 test.lua` green, `lua5.1 test.lua lua-types` green, and
  `lua-language-server --check=src/types --checklevel=Warning` clean. No public type changes
  are expected.

### 8. Live acceptance in the client

Use the `wow-lua-bridge` skill. A `/reload` re-reads TOC metadata on build 69547, so no
client restart is needed after regenerating.

- Generate Vanilla, reload, confirm `LibQuestieDB.readMode == "baked"` and
  `C_AddOns.GetAddOnMetadata("QuestieTDB", "X-Contract-Version") == "2"`.
- Run the harness in `docs/read-performance.md` §8 and record the results as a dated section
  of that document, extending the existing 2026-09-03 findings rather than duplicating them:
  cold and warm `Quest.name`, `Quest.requiredLevel`, `Quest.objectives`, `Npc.spawns`; the
  36-field `GetAll` row on 500 quests; the three-scalar sweep over all quests; the quest-log
  workload, three passes with garbage; `GetAddOnMemoryUsage` at rest and after the sweep.
- Acceptance thresholds, from the prototype on Vanilla: a full quest row under 45 µs first
  touch; the three-scalar sweep under 22 ms first pass and under 5 ms warm; scalar reads
  after first touch under 0.5 µs; warm `Npc.spawns` within 20% of today's 1.8 to 2.1 µs;
  heap growth from the sweep under 3.5 MB; resting memory within 1 MB of today's.
- Generate Mists and load it in whichever client is available. Even on the Era client the
  headers decode, so measure the four `IDS` decodes: under 30 ms in total.
- Non-enUS check: `LibQuestieDB.l10n.SetLocale("deDE")`, read `QuestDB.name(2)` and
  `QuestDB.objectivesText(2)`, expect German and a table, then back to `enUS`.
- Dynamic correction check: register a runtime correction that changes `requiredLevel` of
  quest 2 and adds a new quest id, confirm the read, `Exists` and `GetAllIds` see it,
  withdraw it, confirm it is gone. This proves the overlay still sits above the rows.

### 9. Documentation

- `docs/storage-format.md`: replace the value-encoding, tilde-marker and ID-list sections
  with the format above; keep the line-limit, chunking, whitespace, localization and build
  metadata sections; update the nil-and-empty table where the mechanism changed but not the
  result.
- `docs/api.md`: the cache section, the `GetRaw` note, and the `Get(id, index)` remark.
- `docs/read-performance.md`: the dated section from step 8, plus a short pointer at the top
  saying which sections describe the retired literal format.
- `docs/adr/0010-cbor-rows-and-tables.md`: flip status to accepted, date it.
- `AGENTS.md` read-first list and `DESIGN.md` where they describe per-field literal storage.
- `CONTEXT.md`: add Scalar row and Presence mask.
- `README.md` if it mentions the value encoding.
- `src/types/`: expected unchanged; run the LuaLS check to prove it.

### 10. Remove the prototype

Delete `tools/prototype-cbor/` once step 8 passes. Its verdict lives in the ADR and the
numbers in `read-performance.md`. Restore `tools/probe-addon/TDBProbe.toc` with
`git checkout`; `proto.lua` and `proto_meta.lua` in that folder are untracked and should be
deleted.

## Order of checks, cheapest first

1. `lua5.1 test.lua` after each step.
2. `lua5.1 generate.lua Vanilla` then `lua5.1 verify.lua Vanilla` and
   `lua5.1 equivalence.lua Vanilla`.
3. `python3 tools/differential/golden.py check Vanilla`.
4. `tools/check.sh --flavors=Vanilla` then `tools/check.sh all` then
   `tools/check.sh determinism`.
5. Live acceptance.

## Out of scope

- Paged columns for Quest. Measured, deferred in the ADR, which records the shape and the
  numbers. Nothing of it is kept in code.
- Localization storage. It is 8.9 MB of the 20.8 MB Vanilla artifact and the next target,
  but it has its own encoding and its own id list and must not be mixed into this change.
- Scaled-integer coordinates. Rejected in the ADR.
- The copy-per-read contract (ADR 0003 D10). Unchanged; CBOR decode is the copy.
- Any change to Source mode, the correction registry, derived passes or the compiler
  differential adapter.
- A per-consumer warmer or zone index. Measure first after this lands.

## Risks and how to handle them

- **Non-deterministic CBOR bytes.** Map key order from `pairs` is not guaranteed across
  interpreters. Step 1's sorted encoding and the determinism gate cover it; do not skip the
  gate.
- **Chunk boundary inside base64.** Base64 has no line structure, so splitting anywhere is
  safe; `lib.writeMetadata` already handles it and rejects case-folded key collisions.
- **Row memory on a full sweep.** A row holds every scalar of the entity, so a sweep over all
  quests materializes 2.75 MB on Vanilla and 10.8 MB on Mists. That is the ADR's accepted
  trade; if a profile on Mists says otherwise, the deferred paged-column layout for Quest is
  the answer, not a smaller row.
- **Generation time.** The prototype took 8 s for Vanilla and about 70 s for Mists in plain
  Lua, most of it in the pure-Lua CBOR encoder and base64 over the tables. Acceptable for CI.
  Only the id header goes through zlib.
