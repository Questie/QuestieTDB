# TOC Storage Format

The on-disk contract for the TOC metadata store, extracted from the validated `Getters` and
`toc-database` prototypes.

**This document exists so the prototypes can be deleted.** They are the only other place this
format is written down; `DESIGN.md` phase 11 removes them. Treat this file as the spec, not
the generated `.toc` files.

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
| `number` | decimal literal | `## X-2-4: 20` |
| `string` | raw text, unquoted | `## X-2-1: Sharptalon's Claw` |
| `table` | **Lua table source**, decoded by `loadstring("return " .. value)` | `## X-2-2: {{12676},nil,{16305}}` |

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

A reader distinguishes a chunk header from an ordinary value by matching `^~(%d+)~$`. Ordinary
values that would match this pattern cannot occur, because every stored value is either a
number, a Lua table literal (starting `{`), or a name — and a name that would collide is
written in `~Q~` form instead, below.

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

Because segments are only extracted on access, unused locales cost no Lua memory — see
`DESIGN.md`, Localization.

## Build metadata

Every generated `.toc` carries provenance:

```toc
## X-BUILD-COMMIT: <sha or 40 zeros>
## X-BUILD-TIME: <ISO 8601 UTC>
```

`X-BUILD-COMMIT` is `git rev-parse HEAD`, or forty zeros when git is unavailable.

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
| pair `{0, 0}` | `nil` | Questie's documented hack for coordinate-style pairs |
| unknown entity ID | `nil` | No pointer exists |

Two consequences for implementation:

- **Numeric getters must default to `0`, never `nil`.** An absent metadata key means the field
  was nil at source, and Questie returns `0` there. Note `0` is truthy in Lua, so consumers
  already test `~= 0` rather than truthiness — returning `nil` instead would change behaviour.
- **Table getters must return `nil`, never an empty table.** The prototypes' `EMPTY` sentinel
  (`{"startedBy", "table", EMPTY}`) contradicts this and must be removed. It is independently
  disqualified anyway: a frozen table carrying `__newindex` redirects writes instead of
  failing — see `docs/table.freeze.md`.

Empty strings need an explicit representation, since an absent key already means `nil`.
Questie's compiler solves this with a literal `"nil"` sentinel in the opposite direction —
`writers["u8string"]` emits `value or "nil"` and `readers["u8string"]` maps `"nil"` back to
nil, which means a genuine string `"nil"` is lost. QuestieTDB instead marks the empty string
explicitly with `~E~`, so nothing needs to be inferred from a survey and no legitimate value
is unrepresentable.

### Field-level, not nested

The table above governs a *field's* value. Content nested inside a stored table is preserved
verbatim. Questie's compiler additionally normalized some nested values — dropping a spawn
phase of `0`, turning a nil objective text into `""`, quantizing coordinates — and a text
store has no reason to. Those are enumerated in the buildout progress log; each is QuestieTDB
being more faithful to the source, never less.

## Round-trip requirement

For every entity, every field: decoding the stored value must reproduce the source value under
the semantics above. This is verification layer 2 in `DESIGN.md` and is a required CI gate, not
a smoke test.
