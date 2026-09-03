# 10. CBOR scalar rows and CBOR tables

Date: 2026-09-03. Status: accepted 2026-09-03.

## Context

Every Baked-mode read today is a per-field metadata key holding a Lua literal. A cold scalar
read costs 3.5 µs, of which 1.3 µs is the decoded-field cache filling itself, and a cold table
read costs 5 to 15 µs, of which about two thirds is `loadstring` lexing, parsing and
compiling the literal. The cache makes a second read of the same field cheap, but Questie's
dominant read shapes do not repeat: `GetQuest` reads all 36 fields of a quest once and caches
the object itself, and the availability calculation reads two or three scalars across every
quest. Measured on Classic Era 1.15.9 build 69547 against the Vanilla artifact, a full quest
row costs 85 to 110 µs and a three-scalar sweep over all 4,257 quests costs 30 to 35 ms,
both cold. Twelve of the row's 36 reads are client misses on absent table fields.

The client ships `C_EncodingUtil`: native CBOR, zlib and base64. Live probes
(`docs/client-metadata-probes.md` §10, `docs/read-performance.md`) established that every
value shape the database uses round-trips through CBOR exactly, that base64 survives a TOC
line byte for byte, that native decode is three to four times faster than `loadstring` and
level with re-executing a compiled chunk, and that the offline encoder Questie already owns
(`BlizzardCBOR.lua`) agrees with the client codec on the whole Classic quest table.

Three layouts were prototyped (`tools/prototype-cbor/`) from QuestieTDB's own composition
pipeline and verified in the client against every field of every Vanilla entity with zero
differences:

| Layout, scalars | Vanilla sweep, first | Vanilla heap | Mists sweep, first | Mists heap held |
| --- | ---: | ---: | ---: | ---: |
| Whole-type columns, decoded at load | 2.9 ms | 10.5 MB fixed | 151 ms at load | **51 MB fixed** |
| Columns paged by 1,024 ids | ≈8 ms | ∝ pages | 29 ms | 4.5 MB quests, **16 MB for 300 sparse items** |
| One CBOR row per entity | 19 ms | ∝ entities | 99 ms | 10.8 MB quests, 0.2 MB for 300 items |

Whole-type columns are the fastest reads and are ruled out by Mists: 80,049 items alone hold
23 MB from load. Paging fixes quests, where access is a sweep, and fails items, where access
is sparse across the whole id range, so 300 items touched 79 of 79 pages. Rows are the only
layout whose memory follows what a session touches for every type, which is the property the
current cache has and a replacement must keep.

## Decisions

### 1. Scalars are stored as one CBOR row per entity

`X-<Type>-<id>-S` holds base64 CBOR of a map from field index to scalar value for every
number- and string-typed field that `encode.hasStoredValue` says to store, plus `p`, a
presence bitmask over the entity's stored table fields (bit `fieldIndex - 1`). An entity with
nothing to store has no row key. Constant fields are never stored.

The row is decoded on the first field read of that entity and cached as the decoded table.
Every later scalar read of that entity is a table index. There is no load-time decode
and memory is proportional to entities touched, as today, at roughly 300 to 600 bytes per
entity rather than a cache row plus a slot per field.

### 2. Table fields are stored as CBOR, one key per field, decoded natively

`X-<Type>-<id>-<fieldIndex>` keeps its key; its value becomes base64 CBOR of the normalized
table. A read decodes it with `C_EncodingUtil.DeserializeCBOR`, which produces a fresh tree
per call. That is the fresh-per-read mechanism of ADR 0003 Decision 10, unchanged. The
decoded-field cache keeps a producer per table field as today, closing over the decoded
base64 bytes rather than a compiled chunk; a warm table read is one native decode, measured
level with re-executing a compiled chunk.

### 3. The presence mask settles absent table fields without a client call

A read of a table field consults the row's `p` first. A clear bit answers nil, or the
never-nil `{}` default, at 0.36 µs instead of a 2.4 µs client miss. This is where most of the
`GetQuest` saving comes from. The generator refuses a schema with more than 52 fields.

### 4. The id list is one compressed blob per type

`X-<Type>-IDS` holds zlib-compressed, base64 CBOR of the ascending id array, replacing
`IDS-LIST`. The existence map is built from it in a loop. Decoding four headers costs 5 ms
on Vanilla and 26 ms on Mists, at addon load, replacing the `gsub` plus `loadstring` decode
that cost 30 ms on Vanilla. Compression is used only here; rows and tables are base64 only,
since they are small and read one at a time.

### 5. Scalars in the decoded-field cache become the row

In Baked mode the cache row for an id is the decoded scalar row itself, or a table built
from it. Table producers, table defaults and l10n-translated values are cached on that same
row as today. Unknown ids create no cache entry.

### 6. Contract version 2

The storage format changes observably for anything reading raw metadata keys, so
`X-Contract-Version` becomes 2. The public read API does not change; `minSupportedContract`
stays at 1.

### 7. The offline toolchain stays plain Lua 5.1

`BlizzardCBOR.lua`, Questie's encoder already verified byte-compatible with the client, and
`LibDeflate.lua`, zlib-licensed pure Lua, are vendored under `generator/vendor/`. The emulator
installs `C_EncodingUtil` stand-ins built on them. Map encoding must be deterministic, so the
generator sorts map keys; the determinism gate proves it.

## Deferred, not rejected

**Paged columns for Quest only.** Quest access at login is a sweep over every id, and paged
columns serve it in 29 ms and 4.5 MB on Mists against 99 ms and 10.8 MB for rows. That is a
second scalar read path for one type. It is not in this change because the sweep runs once per
login inside Questie's yielding init, where 70 ms is invisible, and because one mechanism is
worth more than 6 MB on the largest flavour until a profile says otherwise. If it is ever
needed, the measured shape was: a header blob with the id list and the page size, one
zlib base64 CBOR blob per 1,024 positions holding that slice of every column plus its
presence masks, decoded on first touch of any id in the page.

## Rejected

- **Whole-type columns decoded at load.** 51 MB of Lua heap on Mists, 151 ms at load.
- **Whole-table blobs including table fields.** All NPC fields as one blob decode in 46 ms,
  atomically, into 19 MB.
- **Dense columns with placeholders.** 11.8 MB against 6.7 MB with nil holes on Vanilla.
- **Batching literals into one `loadstring`.** 2.8 µs per small table against 2.0
  individually; compile cost is linear in bytes.
- **Scaled-integer coordinates.** ADR 0006 fixed raw coordinates; the win is 8% after
  compression.
- **Hex instead of base64.** Base64 survives a TOC line; hex doubles the bytes.
- **SavedVariables as a warm cache.** Cannot hold functions and loads slower than metadata.
- **Deferring decode work to `C_Timer`.** There is no longer any load-time work worth
  deferring; four id headers cost 5 to 26 ms on the loading screen.

## Consequences

- Vanilla acceptance measured a full 36-field quest row at 44.88 µs first touch against 85
  to 110, and the three-scalar sweep at 21.46 ms cold against 30 to 35. The warm sweep took
  4.53 ms, warm scalars reached 0.30 µs, and warm `Npc.spawns` took 2.18 µs.
- Questie's integrated profiler measured `CalculateAndDrawAll` at 92 to 97 ms instead of 150
  to 165 ms. Its `IsDoable` portion fell from 57 to 60 ms to 31 to 33 ms.
- The three-scalar sweep retained 2.48 MB of row cache, below the accepted 3.5 MB limit. A
  controlled reload attributed 2.82 MB more fixed memory to QuestieTDB because native-decoded
  ID arrays and loop-built existence maps now belong to the addon. Those structures are
  retained for the session and create no recurring garbage. The fixed cost is accepted and
  will be revisited only if client-wide memory profiles show pressure.
- The four Mists ID headers decode in 10.36 ms on the Era client, below the 30 ms limit.
- Vanilla entity data in the artifact shrinks from 8.7 MB to about 6.5 MB. Localization is
  untouched and remains the largest section.
- `codec.lua` loses `compileTable`, `decodeTable`, `decodeIdList`, `decodeIdMap` and the entity
  decoder table. Localization keeps its local list-literal decoder and `~N~` chunking remains
  unchanged.
- Source mode, the Correction registry, derived passes, localization storage and the compiler
  differential adapter are unchanged.
