# 8. Name index

Date: 2026-09-01. Status: accepted.

## Context

Questie shows quest objective lines on a hovered world object. The client identifies a hovered
object by its displayed name only — there is no object id in the tooltip — so a name has to be
turned into ids before any entity read can happen. Questie's legacy answer was one reverse map,
built in `l10n:PostBoot` by iterating every object in the compiled database, and used for two
different questions: which objects carry quest tooltip data, and — behind the off-by-default
`enableTooltipsObjectID` setting — which ids in the database share the hovered name, the line
contributors use to find ids for Corrections.

Under QuestieTDB every read is a client metadata call and nothing materializes until accessed,
so "scan every object at boot" is the pattern the store exists to avoid: 6,666 (Vanilla) to
20,326 (Mists) reads on every boot, for a map most sessions barely touch. A consumer-owned map
also cannot be kept correct from the consumer side alone: `ApplyRegisteredCorrections` by a
third-party owner swaps the composed view after the consumer has built its map, and nothing
tells it.

Alternatives weighed:

1. A consumer-owned rebuild after init plus a new `Corrections.onApplied` hook. Correct only
   while every consumer remembers every event, and it keeps entity truth on the wrong side of
   the boundary.
2. A provider-owned index whose invalidation rides the existing cache invalidation. Cannot be
   stale by construction and needs no hook.
3. Per-name directives baked into the store (`X-Object-NAME-<hash>` per locale): O(1) hovers
   with no build at all, plus an overlay delta computed at recomposition. The most store-native
   answer, but a new directive family, a third backend function, and generator and gate work —
   for a feature behind a debug setting.
4. Deriving the quest-line lookup from the consumer's own tooltip registrations instead of the
   database. The registry is already exactly the set of ids the hover needs.

## Decisions

### 1. The quest-line lookup is not a database concern

Which objects have quest tooltip data is consumer bookkeeping. Questie indexes the ids it
registers `o_` tooltips for by their name at registration time, append-only, and never scans
the database for it. QuestieTDB takes no part in that path. The consumer-side shape is written
up in `QUESTIE-OBJECT-NAME-INDEX.md` at the repo root.

The Context's objection to consumer-owned maps applies here in one narrow form, and it is
accepted: a Dynamic Correction applied *after* a registration that renames that object leaves
its quest lines filed under the old name until the tooltip is registered again. Locale is not
in that exposure — an effective locale change reloads the UI — and no Correction renames an
object at runtime today. The registration set answers "what did Questie register, under the
name it saw"; the Name index (D2) is the one that answers over the composed view.

### 2. QuestieTDB owns the reverse of `name` as a Name index

"Which ids carry this name" is entity truth, so the database answers it. Every Entity global
with a `name` field exposes `IdsByName(name)`: the ascending composed ids whose **current** name
equals `name` exactly, or nil. Current means what `Entity.name(id)` returns now — the active
locale, a Correction outranking a translation, an overlay-added entity present, a withdrawn one
absent — because the index is built from those reads and from nothing else.

### 3. Rebuilt, never patched

The index is built lazily on the first lookup and dropped by `InvalidateCache` — every apply,
every locale change, every explicit invalidation — then rebuilt from scratch on the next lookup.
This mirrors recomposition's idempotent-by-construction rule and makes a stale name or a
duplicate id impossible rather than merely tested for. No incremental maintenance, no hook.

### 4. The consumer owns the timing

`BuildNameIndex()` does the full pass on demand and is a no-op when the index exists. The pass
is one cold read per id: 23 ms for Vanilla's 6,666 objects in a live client, 3.5 µs per id,
with about 2.2 MB of heap kept for the warmed name cache and the index
(`docs/client-metadata-probes.md` §9); Mists, at three times the ids, is unmeasured. The provider neither schedules it nor knows why a consumer wants it: a consumer with
a debug setting warms in its own init and on toggle, where a stall is invisible. After an
invalidation the next `IdsByName` call pays the pass again; a consumer that finds that hitch
unacceptable re-warms on `l10n.onLocaleChanged` and after its own apply. Nothing more is built
until someone needs it.

### 5. Not stored in the artifact

The baked per-name directive (alternative 3) is deferred, not rejected. `IdsByName` is the same
surface either way: the shared layer builds by iteration, and a Baked backend may later answer
from a directive instead — exactly the `GetAllIds` / `X-IDS-LIST` shape. The generator would
emit it by reading through the public getters in the emulator under each locale, so the stored
index equals the reads by construction. Build it when the pass cost matters to someone.

### 6. Additive, contract 1

Two functions are added to every Entity global; nothing existing changes shape. The contract
version stays at 1 (ADR 0007 D4: nothing has shipped).

## Consequences

- Questie's boot no longer scans objects; the debug setting pays for its own index.
- `IdsByName` is a public read form: the equivalence sweep compares every bucket between
  Source and Baked modes, and the unit suite proves the index equals the reads, follows
  Corrections and locale, and drops on invalidation.
- Live on Classic Era build 69547 the index equals Questie's legacy `l10n.objectNameLookup`
  for all 2,490 Vanilla object names, id for id — the scan it replaces answered the same
  question, only eagerly (`docs/client-metadata-probes.md` §9).
- The seam between the read modes stays two functions wide.
- The shared, read-only return mirrors `GetAllIds`; a consumer must not mutate a bucket.
- A hovered name Questie's data does not know — a corrected name that differs from the
  client's, or an English fallback on a localized client — matches nothing, as before. The
  index is keyed by the composed read and by nothing else.
