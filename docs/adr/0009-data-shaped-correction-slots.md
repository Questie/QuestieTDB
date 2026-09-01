# 9. Data-shaped Correction slots and scoped recomposition

Date: 2026-09-01. Status: accepted.

## Context

ADR 0007 moved consumer-state Corrections behind the generic owner-scoped registrar: the
consumer captures a table, registers a provider function returning it, and re-applies after
every state change. Building Questie's integration on that shape exposed ceremony and cost:

- Every consumer Correction needed a load-order constant, a captured local, a provider
  closure, a registration line, and a public setter — five artifacts for one table of rows,
  centralized in a module the actual state owners had to reach into.
- `ApplyRegisteredCorrections` re-materialized every dynamic entry of every ranked owner and
  republished all four datatypes. Measured offline in Source mode: 0.26 ms on plain Era, but
  67.6 ms and ~3.4 MB of garbage per apply with SoD active, because the multi-thousand-row
  SoD sets re-materialized on every consumer write. Questie's asynchronous Item-name repair
  applies once per missing Item during quest-log initialization — an apply storm exactly
  where the cost is highest.
- Every apply dropped every datatype's decoded read cache, composed ID map, and Name index,
  even when a single Item row changed.

`loadOrder` earns its keep only inside QuestieTDB's own layer, where SoD must beat Era and
hand-maintained sets must beat generated ones across ~30 ported files. No consumer correction
orders against another; a consumer's real operations are "publish this table", "replace it",
and "withdraw it".

## Decisions

### 1. A data-shaped write-through slot API, additive to Contract 1

`Corrections.Set(owner, datatype, name, rows)`, with `registrar.Set(datatype, name, rows)` and
the `LibQuestieDB.SetCorrection` alias. Each (owner, datatype, name) is one slot: writing
replaces the previous rows in place, `nil` removes the slot so the layers underneath show
through, and `{}` keeps the slot but contributes nothing. Publication is immediate — no
separate `Apply()`. Slots carry no loadOrder; within an owner they take effect in creation
order, before explicitly numbered function entries. Rows flow through the same normalization,
constant-field, and type validation as function results: one recompose path, two entry shapes.

Function-shaped registration stays, for the two users that need it: QuestieTDB's own ported
sets (the port pipeline produces functions, Static Corrections must stay functions for
Generation, and the expansion load-order windows do real cross-file work) and any third party
with a table large enough to want lazy materialization and batch apply. A name already
registered as a function correction — Static or Dynamic — is refused by `Set` in both
directions, write and removal.

### 2. Recomposition and publication are scoped per datatype

A dirty set records which datatypes changed — an owner's apply, a withdrawal, a `Set`.
Recomposition rebuilds exactly those, and `SetOverlay` runs only on their Entity globals: an
Item write no longer drops Quest, Npc, or Object read caches, shared ID maps, or Name indexes.
Registration alone marks nothing — an unapplied entry must not make another owner's write
republish its datatype.

This narrows ADR 0008 D3's "dropped by every apply" for the Name index to applies and writes
that touch the entity's own datatype; locale changes and explicit invalidation still drop it.

### 3. Function materialization is memoized per entry

A provider function runs once and its result is cached on the entry; only the owner's own
`ApplyRegisteredCorrections` clears that owner's memos. This is safe because a provider
function's output may depend only on facts fixed for the session (ADR 0007 D1) or on captured
state whose documented refresh is exactly that owner's re-apply. Offline effect on SoD: a
consumer write against the same datatype drops from 67.6 ms / 3.4 MB to 14.8 ms / 2.0 MB (the
residue is the datatype's compose iteration over the memoized rows), and to sub-millisecond on
flavors without huge dynamic sets. The trade: materialized tables stay resident for the
session instead of being rebuilt per apply.

### 4. Owner rank rules extend unchanged to Set

Rank is fixed at the owner's first apply **or first `Set`**; re-writing never re-ranks. A
Set-only owner is never left "pending", so a no-arg apply after write-through traffic finds
nothing to refresh and drops nothing.

### 5. Rows are retained by reference

The provider stores `rows` as handed over until the slot is rewritten or removed. The
accumulate-and-rewrite pattern — mutate your own table, `Set` it again — is supported and is
how Questie's Item-name repair works; mutating without a `Set` leaves the published view stale
until some other write flushes that datatype. Reads still hand out fresh copies (ADR 0003
D10 revised), so no caller can reach the retained table through the read path.

### 6. Contract version stays 1

Additive surface; nothing has shipped, so ADR 0007 D4's reasoning applies unchanged.

## Consequences

- Questie's integration is one `SetCorrection` seam; its eight-registration captured-state
  module, load-order constants, and per-correction setters are deleted. A consumer write costs
  one datatype's recompose against memoized layers.
- Two public entry shapes exist by design: slots for state-driven tables, functions for large
  lazy sets. docs/api.md carries the decision rule; a mixed owner orders slots (sequence
  fractions) before numbered function entries.
- The `set-corrections` suite pins write-through visibility, replace/withdraw, `{}` semantics,
  cross-owner withdrawal fall-through, rank fixing, per-datatype publish identity for both Set
  and Apply, memoization run counts, side-effect-free registration, the pending rule, and the
  function/Static name refusals — 35 checks against the baked Vanilla artifact.
- `-pi`'s transactional machinery (docs/pi/transactional-corrections.md) remains unported; the
  dirty set is scope bookkeeping, not a transaction log.
- ADR 0008's Name index now survives non-Object correction traffic: only an Object-datatype
  write or a locale change drops it, so a consumer's init-time warm-up is no longer undone by
  Item-repair writes.
