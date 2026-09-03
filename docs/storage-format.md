# TOC Storage Format

The on-disk contract for the TOC metadata store, extracted from the validated `Getters` and
`toc-database` prototypes.

**This document exists so the prototypes can be deleted.** They are the only other place this
format is written down; `DESIGN.md` phase 11 removes them. Treat this file as the spec, not
the generated `.toc` files.

One property of the store shapes everything below: the client indexes metadata by key, and
**lookup cost does not vary with artifact size.** The same 25 MB artifact answers a lookup in
0.26 µs for a constant key and 1.35 µs for one built per call, and a 21 MB artifact measured
no faster than the 25 MB one. What costs is building the key and marshalling the value back,
not how many keys sit beside it: the client call proper is 0.26 µs.
Storage volume is a disk and client-memory question, never a read-latency one, so the format
can afford to be verbose where that buys clarity.
Measurements in [`read-performance.md`](./read-performance.md).

## Entity metadata keys

Each entity type owns one key prefix and three key shapes:

```toc
## X-<Type>-IDS: <base64 zlib CBOR id array>
## X-<Type>-<id>-S: <base64 CBOR scalar row>
## X-<Type>-<id>-<fieldIndex>: <base64 CBOR table>
```

`<fieldIndex>` is the 1-based position in the entity's Database Key Enum. The four canonical
prefixes are `X-Quest-`, `X-Npc-`, `X-Item-` and `X-Object-`.

A schema field may declare a constant placeholder. It keeps its name and positional index for
compatibility, but Generation stores no value for it. Source mode normalizes obsolete source
data to the placeholder. Baked mode ignores even a stale scalar-row slot and reconstructs the
same missing-storage default. NPC `minLevelHealth` and `maxLevelHealth` use this rule and
return `0` and `1` for known NPCs.

## Scalar rows

`X-<Type>-<id>-S` holds one CBOR map:

```lua
{
  [fieldIndex] = scalar,
  p = tablePresenceMask,
}
```

Generation stores every number or string for which `encode.hasStoredValue` returns true:
nonzero numbers and all non-nil strings, including `""`. It never stores constants. The `p`
slot is the sum of `2 ^ (fieldIndex - 1)` for every stored table field and is omitted when no
table is present. Generation rejects schemas wider than 52 fields so every mask bit remains
exact in a Lua double.

An entity with no stored scalar and no stored table has no `-S` key. It still exists through
the type's `IDS` header. On the first Baked read of an entity, the reader decodes this row and
uses it as that entity's scalar cache.

## Table fields

A normalized, non-empty table is stored under its existing field key as base64 CBOR. The
presence bit and metadata key either both exist or both do not. Baked reads consult `p` first,
so an absent table needs no metadata call. A present table's producer retains decoded CBOR
bytes and calls `C_EncodingUtil.DeserializeCBOR` for each read. The resulting tree is the
fresh mutable value promised by ADR 0003 Decision 10.

**Coordinates preserve their raw authored or Derived Pass values** (ADR 0006). CBOR encodes
the Lua numbers directly, including every significant bit of a calculated coordinate. Tuple
shape stays canonical: explicit `{-1,-1}` instance sentinels have two elements, spawn phase
`0` is omitted, nonzero phases survive, and waypoint rows never carry a third element.
`{0,0}` and sub-grid pairs remain real coordinates rather than compiler sentinels.

Sparse arrays keep their positions because CBOR null items preserve nil holes. Maps are
encoded with sorted encoded keys at every nesting level. That deterministic ordering is part
of the generation contract: identical input must produce byte-identical artifacts.

## Chunked values

TOC metadata values have a practical length ceiling. Values longer than **1000 bytes** are
split:

```toc
## X-Quest-2-8: ~3~
## X-Quest-2-8-1: <first part>
## X-Quest-2-8-2: <next part>
## X-Quest-2-8-3: <remainder>
```

- The base key holds `~<partCount>~` — a tilde-delimited decimal count, and nothing else.
- Parts are numbered from 1 and reassembled by concatenation in order, with no separator.
- **Splits must not fall inside a UTF-8 sequence.** Back the split point up while the next
  byte is a continuation byte (`0x80`–`0xBF`). Current binary payloads are base64, but the
  shared writer keeps this invariant for any future raw-text metadata.
- **No part may begin or end with a byte the client trims** — space, tab, CR, LF. Measured on
  Classic Era 1.15.9 (`docs/client-metadata-probes.md` §1): `GetAddOnMetadata` strips a
  value's edge whitespace, so a split landing beside a space silently loses that byte during
  reassembly. The split point backs up past any such boundary, exactly like the UTF-8 rule,
  and `verify.lua` scans every emitted value for the invariant.

A reader distinguishes a chunk header from an ordinary value by matching `^~(%d+)~$`. Entity
values and localization blocks use base64, whose alphabet cannot begin with `~`.

## Line length limit

**A TOC line may not exceed 1023 bytes**, counting the whole line — `## `, the key, `: `, and
the value. Measured on Classic Era 1.15.9: past that, `C_AddOns.GetAddOnMetadata` returns a
silently truncated value and reports nothing.

```
key `X-Object-IDS-1`        line 1024 -> value came back 999 bytes of 1000
key `X-Npc-5797-8-1`        line 1019 -> value came back intact
```

A 1024-byte buffer including its terminator.

The consequence is that **the chunk threshold is a budget on the line, not on the value**. The
key counts against the same limit, and it is not a constant: the per-type prefixes this format
uses (`X-Object-`, `X-l10n-ruRU-Quest`) are long, and a chunk part's key grows as the part count
gains digits. `generator/lib.lua` therefore sizes parts from the key and then checks every line
it is about to write, rather than trusting the arithmetic.

Budgeting the value alone is exactly the bug this rule exists to prevent: it truncated 17 IDs
out of a 43-part ID list, across 27,690 over-long lines in the five artifacts, with no error
anywhere. `verify.lua` now fails on any line over the limit — the metadata emulator reads the
file directly and never truncates, so nothing else offline can see the problem.

## Edge whitespace and key case

Two more client parser behaviors, both measured on Classic Era 1.15.9
(`docs/client-metadata-probes.md`):

- **The client trims a value's edges.** Leading and trailing space/tab/CR/LF never survive a
  read. Base64 entity values contain none of those bytes. Translations are trimmed at
  extraction, and chunk parts obey the split rule above. `generator/lib.lua` refuses unsafe
  writes and `verify.lua` scans the raw file.
- **Keys are case-insensitive.** `x-quest-2-1` and `X-Quest-2-1` are the same key to
  `GetAddOnMetadata`, so two keys differing only in case would silently shadow one another.
  Generation asserts case-folded uniqueness across every key it writes. Canonical spellings
  (`X-Quest-`, `X-l10n-deDE-Quest`) differ by more than case.

## Tilde marker

`~<N>~` is the format's only marker. It means the base key has N numbered chunk parts. CBOR
represents empty strings and control bytes without sentinels.

## ID header

Each entity type stores its complete ascending ID array under `X-<Type>-IDS`. Generation
serializes the array as deterministic CBOR, compresses it with zlib level 9, then base64
encodes the compressed bytes. Chunking applies to the base64 text.

Baked mode decodes all four headers at addon load through `DecodeBase64`,
`DecompressString(bytes, 1)` and `DeserializeCBOR`. It retains the decoded lists and builds
`[id] = true` existence maps in a loop. Rows remain lazy; this is the only eager entity decode.

## Localization blocks

`X-l10n-Version: 1` declares the localization store. Each non-enUS locale has one compressed
CBOR block per entity type:

```toc
## X-l10n-deDE-Quest: <base64 zlib CBOR field columns>
## X-l10n-deDE-Npc: <base64 zlib CBOR field columns>
## X-l10n-deDE-Item: <base64 zlib CBOR field columns>
## X-l10n-deDE-Object: <base64 zlib CBOR field columns>
```

A block is an array of compact localization field columns. Each column uses positions from the
entity type's ascending `X-<Type>-IDS` array:

```lua
{
  [1] = { [entityPosition] = translatedName },
  [2] = { [entityPosition] = translatedObjectivesOrSubName },
}
```

Quest columns are `name`, `objectivesText`; NPC columns are `name`, `subName`; Item and Object
have only `name`. A nil hole means no translation, so the reader falls back to the base entity
field. List-valued quest objectives are CBOR tables and retain the locale's own element count.

The locale precedes the entity type because the client reserves a final `-deDE`-style suffix
for localized TOC directives; such a key disappears when another locale is active. Generation
trims scalar translation edges and removes control characters before encoding, matching the
display-text cleanup applied by the earlier store. It emits deterministic CBOR,
zlib level 9, then base64. The full base ID list is not repeated in localization.

**enUS has no blocks.** A client using enUS decodes no localization data. A non-enUS client
decodes its four available type blocks during addon load and retains those columns for the
session. Lookups use the backend ID list, with a sequential-position fast path and binary-search
fallback. Locale changes replace all four active blocks before invalidating entity caches.
Corrections still outrank translations, and translated tables still return fresh mutable copies.
See ADR 0011.

## Build metadata

Every generated `.toc` carries provenance:

```toc
## X-BUILD-COMMIT: <sha or 40 zeros>
## X-BUILD-TIME: <ISO 8601 UTC>
## X-QUESTIE-COMMIT: <sha or 40 zeros>
```

`X-BUILD-COMMIT` is `git rev-parse HEAD`, or forty zeros when git is unavailable.

`X-QUESTIE-COMMIT` is the same for the Questie checkout Generation reads (`--questie=`,
default `QUESTIE_PATH` or `../Questie`). It is provenance, not decoration: the localization
blocks are built from lookups in that checkout rather than committed here, so an artifact is
reproducible only from the *pair* of commits. `QUESTIE_COMMIT` pins the reviewed input;
Generation, Reconstruction, the compiler differential, and the Correction port reject a
different commit, and both workflows read that pin through the shared checkout action.
`tools/package.sh` copies
the commit into `release.json` and refuses to package artifacts that disagree about it.

## Nil and empty semantics

**The rule: match Questie's current compiler exactly.** Consumers have been written against
these semantics for years, and any deviation is a silent behaviour change across ~290 call
sites.

| Source value | Read back as | Note |
| --- | --- | --- |
| constant field | schema placeholder | Raw values are obsolete and no scalar-row slot is stored |
| number `nil` | **`0`** | Lossy, and deliberate — Questie's writers emit `value or 0` |
| number `n` | `n` | |
| string `nil` | `nil` | |
| string `""` | `""` | Empty is **distinct** from nil and must survive |
| table `nil` | `nil` | |
| table `{}` | **`nil`** | Empty tables never come back; both collapse to nil |
| `questgivers` / `objectives` structure | **`{}`** | These two readers build a table unconditionally, so `startedBy`, `finishedBy` and `objectives` are never nil for an entity that exists (ADR 0005). Absence still encodes it — the reader reconstitutes `{}` from the structure, so no bytes are stored |
| pair `{0, 0}` | `nil` | Questie's documented hack for coordinate-style pairs |
| unknown entity ID | `nil` | No pointer exists |

Two consequences for implementation:

- **Numeric getters must default to `0`, never `nil`.** An absent scalar-row slot means the
  field was nil or zero at source, and Questie returns `0` there. Note `0` is truthy in Lua,
  so consumers already test `~= 0` rather than truthiness; returning `nil` would change
  behaviour.
- **Ordinary table getters return `nil`, never an empty table.** The three never-nil structures
  above are explicit exceptions. The prototypes' `EMPTY` sentinel (`{"startedBy", "table",
  EMPTY}`) contradicts the general rule and must be removed. It is independently disqualified
  anyway: a frozen table carrying `__newindex` redirects writes instead of failing — see
  `docs/table.freeze.md`.

CBOR represents an empty string directly, so `""` occupies a scalar-row slot while nil has
no slot. Questie's compiler instead uses a literal `"nil"` sentinel and cannot represent a
genuine string with that value. QuestieTDB needs no inference or sentinel on the entity path.

### Element-level, not field-level

**This section previously claimed the table above governs a *field's* value, and that nested
content is preserved verbatim with coordinates as the sole exception. That was wrong**, and
the reference differential (`tools/differential/compiler_diff.py`) proved it: coordinates were
not the exception, they were the one nested case anyone had checked. Questie's `nil number ->
0` rule applies **element-wise inside structured values too** — its tuple writers emit
`value or 0` and its readers read back every slot they wrote:

| Structure | Slot | Reads back as |
| --- | --- | --- |
| `objective` (creature/object/item) | `[3]` icon | `0` |
| `spellobjective` | `[3]` item | `0` |
| killcredit rows inside `objectives` | `[4]` icon override | `0` |
| `extraobjectives` rows | `[4]` objectiveIndex | `0` |

String slots are **not** padded: they are written `value or ""` and read back as nil for `""`.

Coordinate tuple shape remains a deliberate nested normalization, but `x` and `y` retain raw
precision (ADR 0006). The compiler's remaining nested behaviours — turning a nil objective text
into `""` and the like — stay unreproduced and are measured rather than assumed harmless. The
migration differential accounts for every remaining divergence; current counts live in
[`questie-handover.md`](./questie-handover.md). The tool-only Compiler comparison adapter
reproduces the old 40.90 grid where the compiler oracle requires it without imposing that loss
on production storage or reads.

## Round-trip requirement

For every entity, every field: decoding the stored value must reproduce the source value under
the semantics above. Coordinate-bearing structures reproduce raw authored or Derived Pass
values exactly; legacy grid projection belongs only to the compiler differential. This is
verification layer 2 in `DESIGN.md` and is a required CI gate, not a smoke test.
