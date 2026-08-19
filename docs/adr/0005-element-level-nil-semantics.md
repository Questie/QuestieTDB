# 5. Element-level nil semantics and never-nil structures

Date: 2026-08-19. Status: accepted. Amends `docs/storage-format.md` and `docs/api.md`.

## Context

`docs/storage-format.md` stated two rules as absolutes:

> table `{}` → **`nil`** — empty tables never come back
>
> **Field-level, mostly not nested.** The table above governs a *field's* value. Content nested
> inside a stored table is preserved verbatim, **with one deliberate exception**: coordinates.

The reference differential (ADR 0004) showed both are wrong against the reference
implementation, and that they were wrong in the same way: **Questie's nil semantics are not
field-level.** Coordinates were not the exception; they were the one nested case anyone had
checked. Between them these two errors accounted for 61,610 of the 65,307 divergences —
94% of everything the differential found.

## Decisions

### 1. Two structures are never nil

`readers["questgivers"]` and `readers["objectives"]` construct a table unconditionally:

```lua
readers["questgivers"] = function(stream)
    return { u8u24arrayReader(stream), u8u24arrayReader(stream), u8u24arrayReader(stream) }
end
```

Every sub-array can be nil, but `ret` is still a table. So `startedBy`, `finishedBy` and
`objectives` read back as `{}` for a quest that has none — never nil. This is
consumer-visible: `if QueryQuestSingle(id, "startedBy") then` is **true** upstream, and was
false here.

The rule is keyed on the field's compiler structure, not hand-listed per field, so a schema
re-derivation that adds a field of either type inherits it.

**Absence still encodes nil on the wire.** `normalize.field` returns `{}`, `encode.field`
omits the line anyway, and the read path reconstitutes the empty table. The correction costs
zero stored bytes. Existence gating is unchanged: an unknown id still reads nil for every field
(ADR 0003 D6), so an empty table never implies existence.

**One definition, two consumers.** The rule for "what does a field with no stored value read
as" lives in `normalize.default` alone — numerics to `0`, never-nil structures to `{}`,
everything else nil. Source mode reaches it through `normalize.field`, which it already applies
per read; Baked mode has no stored key to normalize, so `src/read/shared.lua` resolves the
defaults once per entity type and caches them in the decoded-field cache's own convention (a
plain value for scalars, a producer for tables, so a table default still hands out a fresh copy
per read). The first implementation restated the rule in `shared.lua` and left
`normalize.default` dead except in tests — three copies of one contract, which is precisely
what `normalize.lua` exists to prevent. Consolidating it changed no divergence count on any
flavour.

### 2. Absent numeric slots inside structured values read back as `0`

Questie's tuple writers emit `value or 0` and its readers read every slot they wrote:

| Writer | Slot | Reads back as |
| --- | --- | --- |
| `writers["objective"]` | `entry[3]` (icon) | `0` |
| `writers["spellobjective"]` | `entry[3]` (item) | `0` |
| `writers["objectives"]` killcredit | `entry[4]` (icon override) | `0` |
| `writers["extraobjectives"]` | `row[4]` (objectiveIndex) | `0` |

So the field-level "nil number → 0" rule applies **element-wise inside structures too**. This
matters for the same reason the field-level rule does: `0` is truthy in Lua, so
`if objective[3] then` flips.

String slots are deliberately **not** padded. They are written `value or ""` and read back as
nil for `""`, so a nil string stays nil.

Padding happens in `src/meta/normalize.lua`, which Generation, Source mode, the Correction
Overlay and the verifier all share, so the modes agree by construction rather than by test.
Unlike Decision 1 this *does* change stored bytes, by ~0.1% — measured, not estimated.

### 3. The general rule is unchanged

A table field with no never-nil structure still collapses `{}` to nil, `{0,0}` pairs still
read nil, and empty id arrays still read nil. Decision 1 is an exception keyed on structure,
not a reversal.

## Consequences

- `docs/storage-format.md` and `docs/api.md` are amended; the "Field-level, mostly not nested"
  claim is retired. Consumers must stop assuming a table getter can be used as a presence
  test for these three fields.
- All five artifacts regenerate. Sizes move by ~0.1%: Vanilla +82 KB, TBC +89 KB, Cata +7 KB,
  Mists +60 KB, Wrath −14 KB (waypoint simplification removes more than padding adds there).
- Divergences fall from 4,365 / 7,245 / 10,341 / 20,142 / 23,214 to
  **49 / 84 / 429 / 872 / 514**. No `FIX`-class divergence remains; what is left is one
  `POLICY` class, three `OPEN` and three `UNTRIAGED`.
- The equivalence harness needed a fix, not a workaround: its ownership check scribbled over
  `next(first)`, which raises on a legitimately empty table. It now scribbles a fixed key and
  picks a *populated* field for the copy-semantics check, which is stronger than before.
