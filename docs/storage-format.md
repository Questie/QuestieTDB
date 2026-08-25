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

## Metadata line

Every stored value is one TOC metadata directive:

```toc
## X-<id>-<fieldIndex>: <encoded value>
```

- `<id>` — entity ID, decimal.
- `<fieldIndex>` — 1-based position in the entity's schema, per the **Database Key Enum**.
- Values are raw text. No quoting, no escaping beyond what Lua source itself requires.

Fields whose value is absent produce **no line at all**. Absence is the encoding for `nil`.

### Combined-addon prefix

When several entity databases share one addon, keys carry a per-type prefix:

```toc
## X-<prefix><id>-<fieldIndex>: <encoded value>
```

The decoder is generated with `META_PREFIX` baked in, so split and combined addons expose an
identical runtime API and differ only in key spelling.

## Value encoding

| Schema type | Encoding | Example |
| --- | --- | --- |
| `number` | decimal literal — the shortest spelling that reads back as exactly the same double (`tostring`, then `%.15g` → `%.17g`, first that round-trips) | `## X-2-4: 20` |
| `string` | raw text, unquoted | `## X-2-1: Sharptalon's Claw` |
| `table` | **Lua table source**, decoded by `loadstring("return " .. value)` | `## X-2-2: {{12676},nil,{16305}}` |

**Coordinates are stored on Questie's compiler grid** (ADR 0003, Decision 1): every spawn and
waypoint coordinate is quantized `floor(c * 40.90) / 40.90` by the shared normalizer before
serialization, with the compiler's sentinel rules — `{-1,-1}` round-trips through the zero
pair, a pair quantizing to zero collapses to `{-1,-1}`, a spawn's phase survives only beside a
non-zero pair, and waypoint rows never carry a third element. "Match Questie exactly" means
matching compiled reads, not source literals; the long decimals this produces are spelling,
not precision loss.

Table values are Lua source, so the serializer *is* the storage format. Two properties are
load-bearing rather than cosmetic:

- **Compactness** — no whitespace, no trailing separators. This directly determines artifact size.
- **Determinism** — identical input must produce byte-identical output, or every regeneration
  produces a spurious diff and checksums stop meaning anything.

Sparse arrays keep their holes (`{{12676},nil,{16305}}`); the decoder relies on Lua's own
table constructor semantics.

## Chunked values

TOC metadata values have a practical length ceiling. Values longer than **1000 bytes** are
split:

```toc
## X-2-8: ~3~
## X-2-8-1: <first 1000 bytes>
## X-2-8-2: <next 1000 bytes>
## X-2-8-3: <remainder>
```

- The base key holds `~<partCount>~` — a tilde-delimited decimal count, and nothing else.
- Parts are numbered from 1 and reassembled by concatenation in order, with no separator.
- **Splits must not fall inside a UTF-8 sequence.** Back the split point up while the next
  byte is a continuation byte (`0x80`–`0xBF`). Localized names make this reachable in practice,
  not theoretical.
- **No part may begin or end with a byte the client trims** — space, tab, CR, LF. Measured on
  Classic Era 1.15.9 (`docs/client-metadata-probes.md` §1): `GetAddOnMetadata` strips a
  value's edge whitespace, so a split landing beside a space silently loses that byte during
  reassembly. The split point backs up past any such boundary, exactly like the UTF-8 rule,
  and `verify.lua` scans every emitted value for the invariant.

A reader distinguishes a chunk header from an ordinary value by matching `^~(%d+)~$`. Ordinary
values that would match this pattern cannot occur, because every stored value is either a
number, a Lua table literal (starting `{`), or a name — and a name that would collide is
written in `~Q~` form instead, below.

## Line length limit

**A TOC line may not exceed 1023 bytes**, counting the whole line — `## `, the key, `: `, and
the value. Measured on Classic Era 1.15.9: past that, `C_AddOns.GetAddOnMetadata` returns a
silently truncated value and reports nothing.

```
key `X-Object-IDS-LIST-1`   line 1024 -> value came back 999 bytes of 1000
key `X-Npc-5797-8-1`        line 1019 -> value came back intact
```

A 1024-byte buffer including its terminator.

The consequence is that **the chunk threshold is a budget on the line, not on the value**. The
key counts against the same limit, and it is not a constant: the per-type prefixes this format
uses (`X-Object-`, `X-l10n-Quest-`) are long, and a chunk part's key grows as the part count
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
  read. Therefore no stored value may begin or end with such a byte: an entity string with an
  edge space is written in `~Q~` quoted form (the quotes become the value's edges),
  translations are trimmed at extraction, and chunk parts obey the split rule above.
  `generator/lib.lua` refuses at write time and `verify.lua` scans the raw file.
- **Keys are case-insensitive.** `x-quest-2-1` and `X-Quest-2-1` are the same key to
  `GetAddOnMetadata`, so two keys differing only in case would silently shadow one another.
  Generation asserts case-folded uniqueness across every key it writes. Canonical spellings
  (`X-Quest-`, `X-l10n-Quest-`) are unchanged — they differ by more than case.

## Tilde markers

Three markers share the `~…~` space, checked before a value is interpreted as its declared
type:

| Marker | Meaning |
| --- | --- |
| `~<N>~` | Chunked metadata value with N parts |
| `~E~` | The empty string |
| `~Q~<lua literal>` | A Lua string literal, for a value the line format cannot carry raw |

`~E~` exists because an absent key already means nil, so `""` has no other way to distinguish
itself. `~Q~` covers the two remaining cases: a string containing a control character or line
break, which a line-oriented format cannot carry at all, and a string that would otherwise be
mistaken for a marker. The encoder rewrites any raw string matching a marker into `~Q~` form,
so collision is impossible by construction rather than by survey.

## ID list

Each entity type stores the full set of IDs it contains under a reserved key:

```toc
## X-IDS-LIST: 2,5,7,12,13,...
```

Comma-separated decimal IDs, ascending. Chunking applies here too — this value is large.

Consumers build either form from it:

- **list** — `loadstring("return {" .. value .. "}")()`
- **hashmap** — same, with `(%d+)` replaced by `[%1]=true`

## Localization

Localized values are stored under their own prefixed keys:

```toc
## X-l10n-<Type>-<id>-<fieldIndex>: <locale1>‡<locale2>‡...
```

The `l10n-` prefix is load-bearing in the combined case, which is what QuestieTDB ships:
without it `X-Quest-2-1` would be ambiguous between quest 2's name and Quest l10n id 2
field 1.

- The separator is **`‡`** (U+2021, UTF-8 `\226\128\161`).
- Locale order is fixed and declared by the generator; the decoder captures the Nth segment.
- **enUS is not stored.** Base entity data is already English, so the l10n store carries only
  translations — currently `deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN, zhTW`.
- An empty segment means "no translation for this locale"; the reader falls back to the base
  entity value.
- **A list-valued field's segments are Lua table literals** (ADR 0003, Decision 3): quest
  `objectivesText` stores each locale's list as `{'…','…'}`, decoded with the same
  `loadstring("return " .. segment)` codec entity fields use. Structure travels in the value,
  so the field stays a table in every locale. Element counts follow the upstream lookup and
  may differ, notably where zhCN or zhTW combines objectives. There is no second,
  element-level separator.
- Scalar segments are raw text, trimmed at extraction — the client trims value edges, and
  which segment sits at a value's edge depends on which other locales are present, so
  untrimmed translations would vary by position. Control characters are stripped at
  extraction as display-text defects (observed in the wild: a leading DEL byte on a zhTW
  NPC name); list elements need no stripping because the quoted literal form escapes them.
- Generation fails on a segment containing `‡` or a control character, and on a joined value
  that would collide with the `~<N>~` chunk-header marker.

Because segments are only extracted on access, unused locales cost no Lua memory — see
`DESIGN.md`, Localization.

## Build metadata

Every generated `.toc` carries provenance:

```toc
## X-BUILD-COMMIT: <sha or 40 zeros>
## X-BUILD-TIME: <ISO 8601 UTC>
## X-QUESTIE-COMMIT: <sha or 40 zeros>
```

`X-BUILD-COMMIT` is `git rev-parse HEAD`, or forty zeros when git is unavailable.

`X-QUESTIE-COMMIT` is the same for the Questie checkout Generation reads (`--questie=`,
default `QUESTIE_PATH` or `../Questie`). It is provenance, not decoration: the l10n lookups —
~72% of the artifact — are read from that checkout rather than committed here, so an artifact
is reproducible only from the *pair* of commits. `QUESTIE_COMMIT` pins the reviewed input;
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

- **Numeric getters must default to `0`, never `nil`.** An absent metadata key means the field
  was nil at source, and Questie returns `0` there. Note `0` is truthy in Lua, so consumers
  already test `~= 0` rather than truthiness — returning `nil` instead would change behaviour.
- **Ordinary table getters return `nil`, never an empty table.** The three never-nil structures
  above are explicit exceptions. The prototypes' `EMPTY` sentinel (`{"startedBy", "table",
  EMPTY}`) contradicts the general rule and must be removed. It is independently disqualified
  anyway: a frozen table carrying `__newindex` redirects writes instead of failing — see
  `docs/table.freeze.md`.

Empty strings need an explicit representation, since an absent key already means `nil`.
Questie's compiler solves this with a literal `"nil"` sentinel in the opposite direction —
`writers["u8string"]` emits `value or "nil"` and `readers["u8string"]` maps `"nil"` back to
nil, which means a genuine string `"nil"` is lost. QuestieTDB instead marks the empty string
explicitly with `~E~`, so nothing needs to be inferred from a survey and no legitimate value
is unrepresentable.

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

Coordinates remain a separate, deliberate nested normalization (ADR 0003 D1). The compiler's
remaining nested behaviours — turning a nil objective text into `""` and the like — stay
unreproduced, and are now *measured* as unreproduced rather than assumed harmless. The
differential accounts for every remaining divergence; current counts live in
[`questie-handover.md`](./questie-handover.md). ADR 0003 Decision 1 resolved the
tension this section used to carry — the consumer contract is what Questie's ~290 call sites
observe, which is *compiled* reads, so spawn and waypoint coordinates reproduce the
compiler's 40.90 quantization and its sentinel rules (see Value encoding above). The
compiler's other nested normalizations — turning a nil objective text into `""` and the like
— remain unreproduced: no call-site-visible behavior depends on them the way availability
math depends on coordinates, and there a text store is deliberately more faithful to the
source.

## Round-trip requirement

For every entity, every field: decoding the stored value must reproduce the source value under
the semantics above — for coordinate-bearing structures, the *quantized* source value, since
quantization is part of normalization. This is verification layer 2 in `DESIGN.md` and is a
required CI gate, not a smoke test.
