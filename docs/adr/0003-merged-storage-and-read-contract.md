# 3. Merged storage and read contract

Date: 2026-08-18. Status: accepted.

## Context

Two sibling implementations of this design exist — this tree (A) and `Questie-toc-pi` (B)
— built independently from the same locked spec. A comparative review found their
artifacts non-equivalent and their read semantics divergent on points the spec never
decided. This tree is the merge base; B is the donor and remains alive as a read-value
oracle until acceptance. This ADR locks every contract the two trees answered
differently, so none of these decisions is smuggled in as a refactor. Live-client
evidence is in [`../client-metadata-probes.md`](../client-metadata-probes.md).

## Decisions

### 1. Coordinates carry Questie's compiled-read semantics

Spawn and waypoint coordinates are quantized at generation exactly as Questie's compiler
quantizes them: `floor(coord * 40.90) / 40.90`. "Match Questie exactly" means matching
what the ~290 existing call sites observe — compiled reads — not the source literals.
(B implemented this; A preserved source literals, which deviates.)

Spelling is separate from semantics: emit the **shortest decimal that round-trips to the
same double** (try `%.15g`, `%.16g`, `%.17g`; take the first that survives
`tonumber`-round-trip). Never bake `%.17g` unconditionally.

### 2. Absence encodes nil; zero-valued numerics are omitted

Unchanged from A: no directive is written for a nil field, and a numeric field whose
value is `0` is also omitted, because the read contract already defines absent-numeric
as `0` **for an entity that exists**. (B wrote 47k explicit zeros into Vanilla alone;
that is pure size.) The existence gate is Decision 6.

### 3. Localized table fields keep their table shape

A localized field whose base type is `table` (quest `objectivesText`) is serialized as a
Lua table literal **per locale segment**, decoded with the same codec as entity fields.
The `‖` list-joiner is retired; structure travels in the value, and the need for a second
separator guard disappears. Generation asserts no serialized segment contains the locale
separator `‡`.

*Scope, corrected after the widened equivalence gate ran:* the contract is **type
stability** — a table-typed field decodes as a table in every locale, never a joined
string — plus byte-faithful extraction. It is NOT count stability: upstream zhCN/zhTW
lookups legitimately combine multiple objectives into one string (1,486 Vanilla reads,
174 Wrath), and reproducing the lookup's own shape is what Questie ships those users
today. What the joiner retirement removed is the *accidental* count variance A's `‖`
splitting invented (155 Vanilla quests); the equivalence gate counts legitimate variance
as informational ("locale-shaped") and enforces type stability and decode success as hard
divergences.

### 4. Chunk parts never begin or end with trimmable bytes

**Measured:** the client trims leading and trailing whitespace from metadata values.
`splitValue` must move a split point (in either direction, like the existing UTF-8
continuation-byte backup) so no part starts or ends with space, tab, CR, or LF.
`verify.lua` scans every part of every artifact for edge whitespace, next to its
line-length scan. The 1,023-byte whole-line budget is unchanged and re-validated on
build 69109 from the safe side.

### 5. Key identity is case-insensitive

**Measured:** `GetAddOnMetadata` folds key case. Generation asserts case-folded
uniqueness across every emitted key. Canonical spellings do not change.

### 6. Reads gate on existence before defaults

The numeric-default-to-`0` rule applies only when the entity exists in the composed view.
An unknown id returns `nil` for every field, `Exists(id) == false`, and `GetAll` returns
`nil`. Getters validate the id argument (`nil`/non-number returns `nil`, never an error
from the cache internals).

### 7. Enumeration and existence are composed

`GetAllIds` and `Exists` answer over the **union** of the backend and entities added by
the Correction Overlay. An entity a Dynamic Correction adds (the SoD model depends on
this) is readable, enumerable, and exists — or none of the three. (B implemented this;
A's overlay-added ids were readable but invisible to enumeration.)

### 8. Corrections win over localization

The Correction Overlay outranks the l10n overlay: when provenance records that a
correction supplied a localizable field, the lookup translation is skipped — a copied
lookup must not replace corrected text with stale text, and `GetProvenance` must never
name an owner for a value it did not supply. (B's rule; A had the inverse, with
provenance misreporting.)

### 9. Seasonal corrections gate on the season

SoD correction sets register only when the client reports the season active
(`C_Seasons`), never on expansion alone. Parameterized corrections (Darkmoon Faire) are
never applied automatically: they are exposed through an explicit
`Corrections` API taking the runtime fact (the Faire location) as an argument, because
selecting it requires game state that QuestieTDB does not own.

### 10. Table reads return a fresh mutable copy per read, via cached compiled chunks

*Revised same day, before implementation, after live measurement — the original text of
this decision mandated frozen shared values.*

Every table-field read executes a **cached compiled chunk** and returns a fresh, deeply
independent, mutable table the caller owns. Baked mode already holds the serialized
literal: it caches `loadstring(text)` once per field and re-executes per read. Source
mode and overlay-composed values serialize once through the shared serializer, compile
once, and re-execute identically — the two modes stay equivalent by construction.

**Measured (Era build 69109, `GetTimePreciseSec`):** chunk re-execution costs 0.13 µs for
a one-id table, 0.26 µs for three ids, 1.7 µs for six coordinate pairs, 19 µs for a
64-pair spawn table — at or near the 0.25 µs decoded-cache hit for the shapes hot loops
actually touch. `C_EncodingUtil.DeserializeCBOR` measures within ~15% of chunk execution
at every size (0.42–20.7 µs) and `CopyTable` is 4–5× slower than either.

Why this replaces freezing: DESIGN.md rejected fresh-per-read *solely* for the
`loadstring`-per-read parse cost, which chunk caching removes — and fresh-per-read is the
**exact** semantics Questie's ~290 call sites were compiled against, so the consumer-side
mutation audit disappears entirely. Scalar fields keep the plain decoded cache (strings
and numbers are immutable). `table.freeze` remains in use only for QuestieTDB-internal
shared structures (schema meta, ID maps), where addon ownership makes it work; the
taint-ownership findings and the validated in-chunk/loadstring-helper freeze patterns
stay recorded in `client-metadata-probes.md` for any future return to shared values.

**CBOR as a storage format is rejected with numbers:** base64(CBOR) is ~38% smaller than
the Lua literal pre-zip and chunk-edge-safe by construction, but it makes artifacts
undiffable — deterministic, reviewable artifacts are a core design value — and its decode
chain (23.5 µs) beats nothing that matters.

### 11. Bulk reads are unpack-safe

`GetAll` returns a packed table carrying `n` (`values.n == #requestedKeys`), documented
as `unpack(values, 1, values.n)`. Positional arrays with nil holes are never returned.

### 12. The contract check is a range, not an equality

`RequireContract(required)` succeeds when
`minSupportedContract <= required <= contractVersion`. Additive releases must not break
consumers built against an older contract.

### 13. Cache invalidation canonicalizes its datatype argument

`InvalidateCache` accepts the same case-insensitive datatype names the corrections API
accepts.

## Consequences

- All five artifacts regenerate; sizes shift (smaller from serializer reuse, larger from
  quantized-decimal spelling — measured after regeneration, recorded in DESIGN.md).
- The equivalence gate widens: both read forms (`Get`/`GetRaw`), name and index access,
  out-of-range indices, provenance, and l10n parity across all nine locales — B's
  methodology, rebuilt against this format.
- B's read values become directly comparable: after this ADR, a cross-implementation
  differential against B should agree everywhere except B's known wire defects.
- The compiled/TOC differential's golden reference must be re-derived where Decision 1
  changes stored values (coordinates previously stored at source precision).
