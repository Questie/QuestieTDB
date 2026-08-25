# 6. Raw coordinate storage

Date: 2026-08-25. Status: accepted.

## Context

ADR 0003 Decision 1 made QuestieTDB reproduce Questie's compiled coordinate reads:
`floor(coord * 40.90) / 40.90`. That was useful while the binary compiler was treated as the
permanent read contract, but TOC metadata does not share its 12-bit storage constraint. The
result discarded source precision and then spelled the divided value as a 15–19 digit decimal,
which enlarged artifacts without compactly storing the legacy representation.

The compiler differential remains valuable during migration, but the compiler itself is due to
be removed. A temporary oracle should not define QuestieTDB's permanent data precision.

## Decisions

### 1. Production preserves raw coordinates

Generation, Source mode, Baked mode, and Dynamic Corrections return authored or Derived Pass
`x` and `y` values without compiler-grid quantization. The generic shortest-exact number
serializer remains unchanged: short authored values stay short, while calculated values retain
as many digits as exact Lua-number reconstruction requires.

This does not introduce fixed-decimal rounding or a second production mode.

### 2. Coordinate tuple shape remains canonical

The precision change does not broaden the public tuple shapes:

- explicit `{-1,-1}` instance sentinels remain two-element tuples;
- spawn phase `0` is omitted and nonzero phases survive;
- waypoint third elements are omitted;
- `{0,0}` and sub-grid coordinates remain real raw values rather than becoming compiler
  sentinels.

### 3. Compiler loss belongs to the migration differential

A tool-only adapter projects QuestieTDB base values onto the legacy grid immediately before
comparison with Questie's compiled reads. It runs exactly once on QuestieTDB's raw side; the
already-compiled side is never transformed because compiler quantization is not idempotent.

Questie's Dynamic Correction values bypassed compilation and were returned verbatim, so
Correction Overlay values also bypass the adapter. The adapter is deleted with the compiler
differential.

### 4. Verification owns exact raw precision

Verification, Source/Baked equivalence, reconstruction, and Golden snapshots validate exact raw
QuestieTDB values. The compiler differential validates only what its legacy oracle can observe:
that base coordinates map to the same compiler-grid result and overlay coordinates remain raw.

### 5. Contract version remains 1

QuestieTDB is still in heavy pre-release development. Coordinate values retain the same numeric
shapes and meaning for consumers, so this correction does not advance `contractVersion` or
`minSupportedContract`.

## Consequences

- Authored coordinates commonly serialize in two to six characters instead of 15–19.
- All-flavor regeneration measured 297,290,054 raw TOC bytes, a reduction of 44,528,384 bytes
  (13.03%) from the 341,818,438-byte post-ADR-0003 baseline. The combined package is
  79,909,948 bytes; per-flavor measurements live in `DESIGN.md`.
- Consumers receive more accurate coordinates and no longer inherit the compiler's downward
  grid bias.
- Golden snapshots change for coordinate-bearing NPC, Object, and Quest fields.
- The compiler differential cannot detect two raw values that fall in the same legacy grid
  cell; QuestieTDB's own exact-value gates cover that precision.

This ADR supersedes ADR 0003 Decision 1 and ADR 0004 Decision 3's statements that production
normalization places coordinates on the 40.90 grid after Derived Passes. Derived Pass ordering
and every other decision in ADRs 0003 and 0004 remain current; their original text is retained
as the historical record.
