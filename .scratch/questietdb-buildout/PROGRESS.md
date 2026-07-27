# QuestieTDB buildout — progress log

Autonomous overnight run. One section per ticket: what was built, what verification passed,
decisions taken, what was skipped and why.

Commands worth knowing:

```
lua5.1 generate.lua meta ../Questie   # materialize src/meta/*Meta.lua from Questie's schema
lua5.1 generate.lua all               # every flavor
lua5.1 verify.lua                     # round-trip verification, exits non-zero on mismatch
lua5.1 test.lua                       # decoder, equivalence and negative-control tests
```

---

## Cross-cutting decisions

Recorded once here rather than repeated per ticket.

### D1 — Raw entity data was copied into `QuestieTDB/data/`, not read from Questie

`DESIGN.md` lists raw entity data as moving into QuestieTDB, and source mode cannot work
without it in-repo. All 20 files (5 expansions × 4 entity types, 78 MB) were copied from
`Questie/Database/<Exp>/`. Nothing was deleted from Questie — removing Questie's copy is
its phase 13 and out of scope here.

### D2 — l10n metadata keys carry an `l10n-` prefix

`docs/storage-format.md` shows localized values at `## X-<Type>-<id>-<fieldIndex>`. In a
single combined addon that collides with entity data at `## X-<prefix><id>-<fieldIndex>` —
`X-Quest-2-1` would be ambiguous between quest 2's name and Quest l10n id 2 field 1. Keys are
therefore written as `X-l10n-Quest-<id>-<fieldIndex>`, matching what the `toc-database`
prototype did for its combined addon. **The storage-format document under-specified the
combined case rather than contradicting this**; the document was updated to say so.

### D3 — Two new markers in the storage format: `~E~` and `~Q~`

`docs/storage-format.md` left the empty-string representation open: *"Verify against real data
whether any entity field is genuinely an empty string before choosing a marker."* Rather than
depend on that survey holding forever, both cases are now representable:

* `~E~` — the empty string. Absence already means nil, so `""` needs its own spelling.
* `~Q~<lua literal>` — for a string a line-oriented format cannot carry (control character or
  line break), or one that would otherwise collide with a marker.

Collision is impossible by construction: numbers are digits, table literals start with `{`, and
the encoder rewrites any raw string matching a marker into `~Q~` form. Document updated.

### D4 — One generic serializer, not the prototype's domain-specific dumpers

`DESIGN.md` says to take `dumpCoordinatesV2` / `dumpTriggerEndV2` / `dumpExtraObjectivesV2`
from `GetterDB` for "domain-specific compaction". Measured against a generic serializer that
handles mixed array and hash parts, those functions produce **byte-identical output** — their
real purpose in `GetterDB` was working around `dumpAsArray` being array-only, which silently
dropped `[zoneId]=` keys. They also iterate with `pairs()`, whose order is not stable, which
alone violates the determinism requirement.

`generator/serialize.lua` therefore implements one generic serializer with sorted hash keys.
It honours the intent (compact, deterministic output for the coordinate-heavy fields that
dominate artifact size) while rejecting the specific implementations. Sparse-array nil holes,
compact number formatting and the no-trailing-separator discipline are ported as-is.

### D5 — QuestieTDB is lossless where Questie's compiler was lossy

Nil and empty semantics match Questie exactly, per `docs/storage-format.md`. Reading
`Questie/Database/compiler.lua` turned up several places where the *binary* format additionally
lost or altered information that a text store simply keeps. Enumerated here because each is a
place a consumer could observe a difference, and all of them are QuestieTDB being more
accurate, never less:

| Compiler behaviour | QuestieTDB |
| --- | --- |
| `spawnlist`/`waypointlist` coordinates quantized through `floor(x * 40.90)` then `/40.90` | exact source coordinates |
| a genuine `{0, 0}` coordinate reads back as `{-1, -1}` | preserved as `{0, 0}` |
| a spawn phase of `0` is dropped, so `{x, y, 0}` reads back as `{x, y}` | preserved as `{x, y, 0}` |
| a string equal to `"nil"` reads back as nil (`readers["u8string"]`) | preserved as `"nil"` |
| sparse ID arrays collapse — writers count `pairs()` and readers refill densely | holes preserved |
| `extraObjectives[n][4]` nil reads back as `0`; `objective[2]` nil reads back as `""` | preserved as nil |

Field-level nil/empty semantics are reproduced exactly; nested content is preserved verbatim.
`docs/storage-format.md` specifies the field level only, so this is the reading that follows
the document.

**Two of these need a decision from you.** The coordinate quantization means QuestieTDB
returns coordinates that differ from today's by up to ~0.024, and the phase-`0` case changes a
returned table's length. Neither is a nil semantic, and both are strictly more faithful to the
source data, but both are observable at a call site that compares against a hardcoded value.

### D6 — `## X-Quest-<id>-<field>`, not `## X-<id>-<field>`

Ticket 01's wording says `## X-<id>-1: <name>`. QuestieTDB is one addon holding four entity
databases, which is the combined case in `docs/storage-format.md`, so keys carry the per-type
prefix from the start rather than being renamed at ticket 04.

### D7 — Numeric zeros are not written

A numeric read with no stored metadata returns `0`, so writing `0` explicitly costs bytes and
says nothing. Absence therefore encodes both nil and zero for numeric fields. This is exactly
the documented read-back semantics, and the round-trip verifier proves it holds.

---

## 01 — Tracer bullet: quest name end to end ✅

**Built**

* `src/config.lua` — flavors, entity types, l10n contract, addon file lists. Dual-mode: the
  client loads it as an addon file, the generator `dofile`s it.
* `generator/loader.lua` — mocked-environment loader. Raw data files turn out to be
  self-contained (each defines its own `*Keys` *and* its `*Data` payload), so the only mock
  they need is `QuestieLoader:ImportModule`.
* `generator/lib.lua` — chunked metadata emission with UTF-8-safe splitting, file helpers,
  build provenance, deep comparison. Ported from `toc-database/src/lib.lua`.
* `generator/serialize.lua` — the deterministic compact serializer. See D4.
* `generator/schema.lua` — schema derivation from Questie's `*Keys` + `*CompilerTypes`, the
  compiler-type map, and materialization into `src/meta/*Meta.lua`.
* `generator/encode.lua`, `src/meta/codec.lua` — the two halves of the on-disk contract.
* `src/meta/normalize.lua` — the single definition of nil/empty semantics, shared by
  Generation, both read modes and the verifier.
* `src/read/shared.lua`, `src/read/baked.lua`, `src/api.lua` — the runtime.
* `generate.lua`, `verify.lua`, `emulator/metadata.lua`.
* `src/meta/{quest,npc,item,object}Meta.lua` — generated and committed.

**Verification passed**

```
$ lua5.1 generate.lua Vanilla --types=Quest --fields=name
  Quest     4244 entities      4244 fields
Generated QuestieTDB_Vanilla.toc — 4244 entities, 4244 fields, 0.2 MB, 0.1s

$ lua5.1 verify.lua Vanilla --types=Quest --fields=name
[PASS] Vanilla: 4244 entities, 4244 fields, 1 chunked values, 0 errors

$ grep -m1 '^## X-Quest-2-1:' QuestieTDB_Vanilla.toc
## X-Quest-2-1: Sharptalon's Claw

# through the emulator, running the shipped src/ files:
QuestDB.name(2)          = Sharptalon's Claw
QuestDB.Get(2, 'name')   = Sharptalon's Claw
QuestDB.Get(2, 1)        = Sharptalon's Claw
#GetAllIds()             = 4244
unknown id 999999 name   = nil
unknown id requiredLevel = 0        (numeric default, not nil)
```

Determinism: two consecutive generations with `SOURCE_DATE_EPOCH` set produce identical
md5 (`dd0717756d3f68b5f820c420e1d8a53f`). `X-BUILD-TIME` is the only volatile line and honours
`SOURCE_DATE_EPOCH`, which is how CI gets byte-reproducible artifacts.

No `lfs`, no C dependency — runs on stock `lua5.1`.

**Schema drift caught by the derivation, as designed**

Materialization found two real divergences between Questie's canonical key enum and the data
files that carry their own copy:

* `itemKeys.teachesSpell` (field 16) is in `Database/itemDB.lua` but absent from **all five**
  item data files.
* `objectKeys.waypoints` (field 7) is absent from MoP's object data file.

Both are *trailing omissions*, not disagreements, and no row in those files carries data at
the missing index — `schema.assertNoDataBeyondKeys` proves that mechanically rather than
assuming it. A disagreement on any shared field still fails the build.

**NEEDS YOU**

* The in-client `/dump QuestDB.name(2)` check. Verified through the emulator instead, running
  the same `src/` files a client loads. The live-client read is unproven.

---

## 02 — Metadata emulator and round-trip verification ✅

**Built**

* `emulator/metadata.lua` — parses a generated `.toc` into a key/value map, installs
  `C_AddOns.GetAddOnMetadata`, and executes the Lua files the TOC lists inside a mocked addon
  environment. Usable as a library; Questie's harness will consume the same file.
* `verify.lua` — round-trip verification against the raw entity data, exiting non-zero on any
  mismatch.
* `test.lua` — dependency-free suite (plain Lua 5.1, no busted, no luarocks) covering the
  serializer, codec, chunking, nil/empty semantics, the emulator, and the negative controls.

**Decision — reassembly lives in the reader, not the emulator**

Ticket 02 asks the emulator to reassemble Chunked metadata values transparently. It does
expose that (`emulator.getValue`), but `emulator.install` deliberately returns exactly what is
on the line, because that is what a live client returns. An emulator that silently joined
chunks would hide the single code path most likely to be wrong. Reassembly is
`src/read/baked.lua`'s job and is exercised through it — including a negative control that
removes a chunk part and asserts the reader raises rather than returning a short string.

**Verification passed**

```
$ lua5.1 test.lua
[PASS] serialize          40 checks, 0 failed
[PASS] codec              23 checks, 0 failed
[PASS] chunking           11 checks, 0 failed
[PASS] semantics          27 checks, 0 failed
[PASS] negative-controls   7 checks, 0 failed
[PASS] emulator            9 checks, 0 failed
117 checks, 0 failed
```

The check is proven able to fail. Four independent corruptions of a generated artifact each
make verification exit non-zero: a changed value, a deleted line, a truncated ID list, and a
missing chunk part.

**A real bug the suite caught immediately**

The first serializer treated every positive integer key as an array index, so
`{[1335]={{36.43,55.89}}}` — the shape of every spawn and coordinate table in the database —
serialized as a 1335-element array of `nil` holes. `generator/serialize.lua` now picks the
array/hash split by cost: 4 bytes per hole against `#tostring(k) + 3` per absorbed key,
minimised in one pass over the sorted integer keys, ties going to the longer array prefix so
`{{12676},nil,{16305}}` keeps the spelling `docs/storage-format.md` uses.

---

## 03 — Full Quest schema in baked mode ✅
## 04 — Npc, Item, and Object entity types ✅

Landed together: once the schema derivation and the shared getter layer were in place, the
generator and reader are entity-agnostic, so widening from one field to 36 and from one type
to four required no new code beyond dropping the tracer-bullet filters.

**Verification passed — Vanilla, all four types, all fields**

```
$ lua5.1 generate.lua Vanilla
  Quest     4244 entities     46851 fields
  Npc      10119 entities     93356 fields
  Item     14889 entities     78162 fields
  Object    6645 entities     16877 fields
Generated QuestieTDB_Vanilla.toc — 35897 entities, 235246 fields, 9.0 MB, 2.2s

$ lua5.1 verify.lua Vanilla
[PASS] Vanilla: 35897 entities, 589308 fields, 556 chunked values, 0 errors, 4.9s
```

Every one of those 589,308 comparisons checks three things: the generic getter against the
expected read-back value, the named getter against the generic getter, and — separately, per
field — that an unknown entity ID returns the field's default rather than a stray value.

**Empty strings are real, and the marker was necessary**

`docs/storage-format.md` left this open: *"Verify against real data whether any entity field is
genuinely an empty string."* They exist — 81 in Vanilla, 94 in TBC, 877 in Wrath, 959 in Cata,
961 in Mists. Absence-means-nil would have silently turned every one of them into nil. The
`~E~` marker carries them. The `~Q~` marker is unused across all five flavors (no entity string
contains a control character), and is kept as insurance since collision-freedom is then
structural rather than dependent on that survey staying true.

**Adding a fifth entity type needs no change to the shared getter layer** — `src/read/shared.lua`
is driven entirely by `meta`, and `src/config.lua` is where a new type would be declared.

**Note for later tickets**

Quest fields 27–36, item fields 15–16, and object field 7 never appear in *raw* data — they are
populated only by Questie's corrections. Their round-trip currently passes trivially. Ticket 09
is what puts real values behind them, and re-running verification then is what actually
exercises those fields.

---

## 05 — All five client flavors ✅ (one criterion needs a client)

**Verification passed — every flavor, every type, every field**

```
$ lua5.1 generate.lua all          # 31s total
Generated QuestieTDB_Vanilla.toc — 35897 entities,  235246 fields,  9.0 MB, 2.2s
Generated QuestieTDB_TBC.toc     — 59101 entities,  390524 fields, 14.7 MB, 3.8s
Generated QuestieTDB_Wrath.toc   — 88398 entities,  593745 fields, 21.1 MB, 5.3s
Generated QuestieTDB_Cata.toc    — 140812 entities, 950079 fields, 34.3 MB, 8.4s
Generated QuestieTDB_Mists.toc   — 177724 entities, 1149311 fields, 41.2 MB, 10.6s

$ lua5.1 verify.lua                # 73s total
[PASS] Vanilla: 35897 entities,  589308 fields,  556 chunked, 0 errors
[PASS] TBC:     59101 entities,  975840 fields,  808 chunked, 0 errors
[PASS] Wrath:   88398 entities, 1449856 fields,  898 chunked, 0 errors
[PASS] Cata:   140812 entities, 2350178 fields, 1668 chunked, 0 errors
[PASS] Mists:  177724 entities, 2953767 fields, 1907 chunked, 0 errors
```

**502,000 entities and 8.3 million field comparisons, zero mismatches.**

Determinism holds across all five: regenerating with `SOURCE_DATE_EPOCH` set reproduces every
artifact byte-identically (`md5sum -c`, 5/5 OK).

Interface versions are taken from Questie's own per-flavor TOCs rather than recalled:
`_Vanilla` 11508,11509 · `_TBC` 20506 · `_Wrath` 38000,38001 · `_Cata` 40402 ·
`_Mists` 50503,50504. `_Wrath` at 38000 is the Titan Reforged / anniversary Wrath range, which
is what Questie ships today, so one artifact serves both as intended.

Modern underscore suffixes throughout — no `-BCC`, no `-WOTLKC`. All five are gitignored.

Total raw artifact size 121 MB across the five, against `DESIGN.md`'s recorded 251 MB — the
difference is that l10n is not in yet (ticket 14), which `DESIGN.md` sizes at ~72%.

**NEEDS YOU**

* *"Each client loads its own suffixed TOC, and a client with no matching suffix falls back to
  the base TOC in source mode."* The suffix-precedence half of this is the client's own rule
  and cannot be exercised offline. The base TOC exists and works (ticket 06) and the suffixed
  TOCs carry correct Interface lines, but which one a given client picks is unverified here.

---
