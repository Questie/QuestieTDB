# Questie handover ledger

**Every known difference between QuestieTDB's reads and Questie's compiled database, what we
decided to do about it, and whether it is done yet.**

This file exists so the migration cannot lose track of an edge case. It is the register the
reference-implementation differential feeds, and the checklist to execute when Questie
switches over. If a divergence is not in here, either the differential has not been re-run or
we found something new — both are reasons to update this file, never to ignore the row.

Decisions live in [`adr/0004-derived-passes.md`](./adr/0004-derived-passes.md) (mechanism) and
[`../../Questie/docs/adr/0002-what-survives-the-compiler.md`](../../Questie/docs/adr/0002-what-survives-the-compiler.md)
(the Questie-side obligations). This file is status, not rationale.

## Regenerating the evidence

```sh
cd QuestieTDB
python3 tools/differential/compiler_diff.py all --questie=../Questie   # ~2 min, all five flavours
python3 tools/differential/compiler_diff.py Vanilla --self-check       # prove the gate is live
```

Counts below were measured 2026-08-19 against the full `QuestieInit` pre-compile sequence.
Totals compared: 395,581 / 655,697 / 975,912 / 1,577,449 / 1,971,578 fields.

The same counts, with a reason per row, are committed under
`tools/differential/compiler-baseline/`. The gate fails on anything new or grown and prints
what is still owed on every run, so a known defect cannot quietly become permanent.

## Divergence register

`FIX` = we intend to match Questie. `POLICY` = permanent and correct, the consumer closes it.
`UNTRIAGED` = nobody has looked yet.

| Class | Vanilla | TBC | Wrath | Cata | Mists | Status | Disposition |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `Quest.objectives` absent-vs-`{}` | 1,654 | 2,708 | 3,574 | 5,947 | 6,868 | **FIX** | `readers["objectives"]` always builds a table, so the field is structurally never nil upstream. Read-side default keyed on compiler type; costs nothing on the wire. |
| `Quest.startedBy` absent-vs-`{}` | 84 | 372 | 557 | 4,596 | 5,090 | **FIX** | Same — `readers["questgivers"]`. |
| `Quest.finishedBy` absent-vs-`{}` | 76 | 366 | 527 | 470 | 1,175 | **FIX** | Same. |
| `Quest.objectives` value | 2,495 | 3,690 | 5,200 | 8,158 | 9,451 | **FIX** | Tuple readers always read every numeric slot and the writers emit `value or 0`, so `objective[3]` is `0`, not nil. Questie's nil→0 rule is element-level, not field-level. |
| `Quest.extraObjectives` value | 7 | 25 | 54 | 99 | 116 | **FIX** | Same rule, `[4]` (objectiveIndex). |
| `Object.spawns` absent-vs-value | 24 | 24 | 24 | 24 | 24 | **POLICY** | Gathering nodes. QuestieTDB keeps all 17,191 spawn points; Questie suppresses them with a registered Dynamic Correction. Permanent and correct. |
| `Npc.spawns` value | 9 | 11 | 41 | 57 | 75 | **OPEN** | Correction Overlay coordinates. `QuerySingle` returns override values verbatim, bypassing the 40.90 grid; QuestieTDB normalizes them. Matching means reproducing an inconsistency. Undecided. |
| `Object.spawns` value | 9 | 11 | 13 | 18 | 19 | **OPEN** | Same cause. |
| `Quest.requiredRaces` value | 7 | 38 | 344 | 696 | 319 | **OPEN** | Derived faction inference. Materialize into explicit corrections, do not port the loop. See `TASK-derived-requiredRaces.md`. |
| `Npc.spawns` absent-vs-value | – | – | 4 | 4 | 4 | **UNTRIAGED** | Never investigated. |
| `Quest.questFlags` value | – | – | 2 | 72 | 72 | **UNTRIAGED** | Never investigated. Vanilla samples showed TDB `8` vs compiler `0` on quests 5640/5678. |
| `Quest.reputationReward` absent-vs-value | – | – | 1 | 1 | 1 | **UNTRIAGED** | Never investigated. Quest 7670: TDB has a value, compiler has none. |

Entity **id sets match exactly** on all five flavours and all four types — zero
`ID_ONLY_IN_*` rows. Storage, generation and enumeration are not implicated in anything above.

## Closed

| Class | Was | Closed by |
| --- | ---: | --- |
| `Npc.waypoints` value | 454 / 808 / 1,095 / 1,153 / 1,158 | `src/derived/waypoints.lua`, the first Derived Pass. Verified at **zero** on all five flavours, with `verify`, `equivalence`, `reconstruct` and determinism all green. |
| `Object.waypoints` value | – / – / – / 3 / 3 | Same pass. |

## Deliberately not reproduced

| Upstream behaviour | Why not |
| --- | --- |
| `l10n:Initialize` writing translations into the entity tables | Replaced by the l10n overlay, which is what removes the `dbCompiledLang` recompile. Verified inert at enUS, so it does not affect the differential. |
| `Townsfolk.Initialize()` | Not entity data. |

## Questie-side checklist

Execute when Questie switches to QuestieTDB. Each item is a thing that would otherwise be
lost by deleting the compiler and its neighbours.

- [ ] **Register the gathering-node Dynamic Correction.** 24 object ids, `spawns` cleared with
      the `{}` idiom, owner `Questie`. Without this, 17,191 gathering-node spawn points start
      rendering. Shape and measured behaviour in ADR 0004 §5a.
- [ ] **Delete `l10n:Initialize`'s writes into `questData`/`npcData`/`itemData`/`objectData`**
      — the six localized fields only. UI translations, zone and category lookups stay.
- [x] **QuestieTDB's waypoint pass is verified at zero divergences** on all five flavours, so
      `QuestieCorrections:PreCompile()` and `OptimizeWaypoints` can be deleted from Questie at
      switch-over. `Modules/Libs/RamerDouglasPeucker.lua` is byte-copied into QuestieTDB
      (`src/derived/RamerDouglasPeucker.lua`) and re-diffed by `tools/port-corrections.lua`, so
      it goes too — but note QuestieTDB *transcribes* `OptimizeWaypoints` itself, and the
      reference differential is the only thing guarding that transcription.
- [ ] **Do not delete the derived `requiredRaces` patch** until it is replaced by explicit
      correction data. It decides a field that gates quest availability.
- [ ] **Audit `QuestieCorrections.lua` rather than deleting it.** It is the file where derived
      logic hid; the port copies correction *files* only, so anything in the orchestrator was
      never carried across. This ledger is the audit's output so far — re-read the file before
      removing it.
- [ ] **Check `QuestieInit.lua:118-134` for anything added since 2026-08-19.** A new pre-compile
      transform would be invisible to every gate we have except this differential.

## Open questions

1. **Overlay coordinate quantization** — match Questie (return correction coordinates
   verbatim, accepting that the same field is quantized from base data and unquantized from
   the overlay), or keep QuestieTDB's uniform treatment and baseline the difference?
2. **The three untriaged classes** above. Small counts, unknown causes.
3. **The validator baseline is stale.** `validators/run.lua` fails on Wrath, Cata and Mists
   with both new *and* fixed findings (Wrath 1 new / 89 fixed; Cata 16 / 52; Mists 61 / 91),
   which is the signature of a baseline recorded against an older data sync rather than a
   regression. Confirmed unrelated to the derived pass: the counts are identical with the pass
   disabled, and no validator reads `waypoints`. Needs a deliberate re-record and review.

4. **The differential runs in CI** (`.github/workflows/ci.yml`, job `differential`, all five
   flavours, part of the terminal `gates` job). It is deliberately a separate job: Questie's
   mocks need `bit32`, and the toolchain that provides it installs `lua` rather than the
   `lua5.1` the other jobs use. It is **not** yet in `release.yml`'s quality bar — adding it
   there means resolving the same interpreter clash in a job that already uses apt's `lua5.1`,
   which is worth doing deliberately rather than blind.
