# 4. Derived passes, and what "match Questie" includes

Date: 2026-08-19. Status: accepted.

## Context

`docs/storage-format.md` has always said the read contract is "match Questie's current
compiler exactly". That was believed satisfied. The reference-implementation differential
(`tools/differential/compiler_diff.py`) showed it was not, and showed why: the sentence was
underspecified. It was read as *corrected data, stored faithfully*, when what ~290 consumer
call sites actually observe is **the compiled binary as it ships in-game** — corrected data
plus a sequence of derived transforms that run between corrections and compilation.

Those transforms live in `Questie/Modules/QuestieInit.lua:118-134`:

```
QuestieCorrections:Initialize()            -- correction files, then a derived requiredRaces patch
Townsfolk.Initialize()                     -- not entity data
l10n:Initialize()                          -- writes lookup translations into the entity tables
QuestieDB.private:DeleteGatheringNodes()   -- strips spawns from 24 gathering objects
QuestieCorrections:PreCompile()            -- waypoint simplification, every NPC and object
→ compile
```

None of them are correction *files*, so `tools/port-corrections.lua` — which byte-copies
`*Fixes.lua` and makes drift a build failure — never saw them. Two of them are not called by
`cli/validate-*.lua` either, so neither Questie's own CI nor the first version of this
differential executed them; both sides skipped them and they cancelled out.

## Decisions

### 1. "Match Questie" means the compiled binary as it ships

The contract is what a consumer observes from a real client, not what the corrected source
tables contain. Any transform upstream applies before compiling is part of the contract and
must be accounted for — reproduced, deliberately declined, or reassigned to the consumer.
Silence is not an option, because silence is what produced this defect class.

### 2. A Derived Pass is a first-class concept, distinct from a Correction

A **Derived Pass** is a deterministic transform over corrected entity data, run before
storage, in both Generation and Source mode. A Correction is *data* (`id → fieldIndex →
value`); a Derived Pass is *code*. The two need different machinery: corrections are
declared per entity type and merge literals, while a pass may read one entity type and write
another.

Passes are **declared, not inferred** — the same rule the correction manifest follows, and
for the same reason (`Sod/static/…` registering dynamic proved folder names are not a
category signal). A pass declares the type it writes, the types it reads, and its order, and receives a context
carrying `entities(type)`, `meta(type)`, `support(module)` and `flavor` — `support` because a
pass may need shipped reference data (the waypoint pass reads `ZoneDB.zoneIDs` for its zone
scales rather than hardcoding six ids).

The name is deliberately not "PreCompile": `CONTEXT.md` retires compile vocabulary, and
there is no compilation step here to be "pre" to.

### 3. Passes run at one seam per mode, and before normalization

| | Insertion point |
| --- | --- |
| Generation, `verify.lua`, `reconstruct.lua` | `generator/flavor.lua`, after `corrections.applyStatic` |
| Source mode | `src/read/source.lua` `materialize()`, after `ApplyStaticToEntities`, before `Freeze` |
| Baked mode | nothing — Generation already applied them, exactly as with Static Corrections |

This mirrors `registry.ApplyStaticToEntities`, which both modes already share; it is that
seam widened, not a new one. Routing the offline side through `flavorLoader.load` means
`generate.lua`, `verify.lua` and `reconstruct.lua` cannot drift apart.

**Order is load-bearing:**

```
raw data → Static Corrections → Derived Passes → normalize (40.90 grid) → encode
```

Passes operate on corrected *raw* values, before quantization. Questie simplifies raw float
coordinates and its compiler quantizes afterwards; because quantization is deliberately
non-idempotent (ADR 0003 D1), quantize-then-transform is unrecoverable — RDP keeps different
points and interpolated midpoints are computed from grid values. Source mode normalizes at
read time, after `materialize`, so it inherits this ordering for free.

A pass that reads a type it does not write pulls that type through the same accessor, which
resolves to the loaded table offline and to `materialize()` in Source mode. Source mode's
existing re-entrancy guard makes that safe, but a genuine cycle would silently read a
half-built table, so **cycles are rejected at registration**, not discovered at runtime.

### 4. Port a derivation when the derivation is the answer; materialize it when the derivation covers for missing data

Waypoint simplification and the `requiredRaces` patch are structurally identical — derived
static passes over corrected data — and get opposite treatments, so the rule separating them
is recorded rather than left to taste.

* **Waypoint simplification is a transform.** There is no authored value it stands in for; it
  is computed from the data by definition, and re-computing it is the correct representation.
  **Port it.**
* **The `requiredRaces` patch is a guess filling a hole.** The right representation is
  explicit data. Porting the loop preserves the hole and hides it behind machinery.
  **Materialize it into corrections instead.**

### 5. Disposition of each pass

| Pass | Disposition | Rationale |
| --- | --- | --- |
| Derived `requiredRaces` | **Open.** Materialize into explicit corrections, preferably upstream. Not ported. | Decision 4. Tracked in `TASK-derived-requiredRaces.md`; the pass slot is deliberately left empty. |
| `l10n:Initialize` data writes | **Deleted.** The l10n overlay replaces it. | Writing translations into entity tables is what made the compiled database locale-specific and forced `dbCompiledLang`. Verified inert at enUS, so the differential is unaffected. |
| `DeleteGatheringNodes` | **Reassigned to the consumer** as a Questie-owned Dynamic Correction. Not a pass, and QuestieTDB keeps the data. | Object 1617 genuinely has spawns; declining to render 17,191 gathering-node spawn points is policy. The boundary rule and the `hiddenQuests` precedent both put it in Questie. |
| `PreCompile` waypoint simplification | **Ported** as a Derived Pass. | Decision 4. |

### 5a. Gathering nodes, concretely

QuestieTDB **retains** the 17,191 gathering-node spawn points — in `data/`, in all five
generated artifacts, and in both read modes. Nothing is stripped at any stage of Generation.

Questie suppresses them at query time through the ordinary Dynamic Correction path, the same
mechanism its faction fixes already use, with `{}` as the documented delete idiom:

```lua
local registrar = LibQuestieDB.GetRegistrar("Questie")
registrar.RegisterRuntimeCorrection("Object", "gathering-nodes", function()
    local objectKeys = LibQuestieDB.Meta.ObjectMeta.objectKeys
    return {
        [1617] = { [objectKeys.spawns] = {} },   -- Peacebloom
        ...                                       -- 24 ids total
    }
end, <loadOrder>)
registrar.Apply()
```

Measured against the real registry, no new machinery required: spawns go 24/24 → 0/24; the
entities still exist and their names still read; `GetProvenance` names `Questie`; `GetRaw`
still returns the base data; and withdrawing the correction restores all 24, because
recomposition rebuilds from the registry rather than accumulating.

That last property is the point of putting it here rather than in the database: the spawns
are *not returned*, not *not present*. A consumer that wants gathering-node locations —
a gathering-route addon, a map overlay — still has them.

### 6. The oracle must run what ships

`tools/differential/dump_compiler.lua` runs the full `QuestieInit` pre-compile sequence, not
the shorter `cli/validate-*.lua` one. A gate that compares against a database no user
receives cannot certify a drop-in replacement. `l10n:Initialize` is the single omission, and
it is justified in a comment at the call site rather than by silence.

## Consequences

- All five artifacts regenerate. Waypoint subdivision *adds* points, so they grow slightly;
  `tools/differential/golden/` needs refreshing and the diff reviewing.
- `RamerDouglasPeucker.lua` joins the byte-identical port set, so `port-corrections.lua`
  carries it and CI fails on drift — the same treatment the correction files get.
- The generator gains a support-data dependency: `ZONE_SCALES` needs `ZoneDB.zoneIDs`, loaded
  from the committed `support/Zones/zoneIds.lua` through the existing mocked-environment
  loader rather than hardcoded, so the constants stay derived.
- Adding the two passes to the oracle *raises* the divergence count before any fix lands
  (Vanilla: +24 `Object.spawns`, +454 `Npc.waypoints`). That is the measurement becoming
  honest, not a regression.
- Gathering-node divergences are permanent and expected. They are recorded in the
  differential baseline as `POLICY` so they can never be mistaken for a defect, and so a
  future contributor cannot "fix" them by adding a pass.
