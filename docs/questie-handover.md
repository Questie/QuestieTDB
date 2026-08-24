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

Current counts use the full `QuestieInit` pre-compile sequence from the Questie commit in
`QUESTIE_COMMIT`. Totals compared: 397,395 / 659,210 / 980,653 / 1,588,480 / 1,982,795
fields.

Remaining divergences: **43 / 76 / 401 / 776 / 417**. Re-porting the pinned Corrections
resolved the stale `questFlags` and `reputationReward` classes and reduced `requiredRaces`.
Matching Questie's inherited-Correction creation rule removed every phantom entity. Preserving
Questie's WotLK `LoadAutomatics`-then-`Load` order removed another 20 NPC-spawn divergences from
each later flavor. Entity-id sets now agree exactly across all five flavors.

The same counts, with a reason per row, are committed under
`tools/differential/compiler-baseline/`. The gate fails on anything new or grown and prints
what is still owed on every run, so a known defect cannot quietly become permanent.

## Confirmed in a live client, 2026-08-19

The offline differential compares two Lua processes. This run compared the shipped artifact
against a running Questie inside the game, which is the only way to prove the client's real
metadata reader behaves like the offline emulator.

**Client:** Classic Era 1.15.9, enUS, Alliance. **Artifact:** `QuestieTDB_Vanilla.toc`, baked
mode, producer `build-7169b67`. **Compared against:** Questie 11.36.1 as loaded.
**Scope:** every field of every entity, 4,257 quests, 10,122 NPCs, 14,899 items, 6,666
objects. **590,128 field comparisons, 54 divergences.**

Entity id sets matched exactly on all four types, zero ids on either side alone.

The four baselined Vanilla classes reproduced **to the row**: `Object.spawns` absent-vs-value
24, `Npc.spawns` value 9, `Object.spawns` value 9, `Quest.requiredRaces` value 7. Forty-nine,
the recorded baseline.

The five extra rows are all upstream data drift between 11.33.2, which
`tools/port-corrections.lua` was last run against, and the 11.36.1 in the client. Each was
confirmed at the source line, so all five should disappear on the next re-sync and none of
them is a QuestieTDB defect:

| Entity | Field(s) | 11.33.2 (ours) | 11.36.1 (client) |
| --- | --- | --- | --- |
| Quest 1271 | `preQuestGroup`, `preQuestSingle` | `preQuestGroup = {1204,1222}` | `preQuestSingle = {1222}`, `preQuestGroup = {}` |
| Quest 4144 | `specialFlags` | `specialFlags.REPEATABLE` | correction removed upstream |
| Quest 5151 | `extraObjectives` | `Questie.ICON_TYPE_INTERACT` (17) | `Questie.ICON_TYPE_OBJECT` (4) |
| Object 188135 | `name` | not set | `objectKeys.name = "Ice Stone"` |

Quest 5151 doubles as an independent check on the constants pipeline: 17 and 4 are exactly
what the live `Questie.ICON_TYPE_*` globals hold and what
`src/corrections/enum/constants.lua` records, so the symbolic constants resolved correctly on
both sides and only the source file changed.

Two further sweeps ran clean in the same session:

* **Storage contract**, 1,050,268 reads across all four types: zero numeric nils, zero empty
  tables leaking through, zero never-nil violations, zero wrong types.
* **Correction Overlay**: `Apply()` 1.45 ms, withdrawal 1.22 ms. A `{}` correction cleared a
  field without touching its siblings, an added entity was readable and enumerable with
  `Exists` true, `GetRaw` still returned base data, `GetProvenance` named the registrar for
  touched fields and `QuestieTDB` for untouched ones, and withdrawal restored the original
  coordinates exactly. This is the mechanism the gathering-node POLICY row depends on,
  verified end to end.

All ten locale variants resolved, CJK and Cyrillic included, with `esMX` distinct from
`esES`.

Read cost and memory from the same session are in
[`read-performance.md`](./read-performance.md).

## Divergence register

`FIX` = we intend to match Questie. `POLICY` = permanent and correct, the consumer closes it.
`UNTRIAGED` = nobody has looked yet.

| Class | Vanilla | TBC | Wrath | Cata | Mists | Status | Disposition |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `Object.spawns` absent-vs-value | 24 | 24 | 24 | 24 | 24 | **POLICY** | Gathering nodes. QuestieTDB keeps all 17,191 spawn points; Questie suppresses them with a registered Dynamic Correction. Permanent and correct. |
| `Npc.spawns` value | 9 | 11 | 25 | 41 | 59 | **OPEN** ([#3](https://github.com/Questie/QuestieTDB/issues/3)) | Correction Overlay coordinates. `QuerySingle` returns override values verbatim, bypassing the 40.90 grid; QuestieTDB normalizes them. Matching means reproducing an inconsistency. Undecided. |
| `Object.spawns` value | 9 | 11 | 13 | 18 | 19 | **OPEN** ([#3](https://github.com/Questie/QuestieTDB/issues/3)) | Same cause. |
| `Quest.requiredRaces` value | 1 | 27 | 339 | 693 | 315 | **OPEN** ([#1](https://github.com/Questie/QuestieTDB/issues/1)) | Derived faction inference. Materialize into explicit corrections, do not port the loop. See `TASK-derived-requiredRaces.md`. |
| TBC prerequisite fields absent-vs-value | – | 3 | – | – | – | **POLICY** | `LoadContentPhaseFixes` supplies `preQuestGroup` for quest 10944 and `preQuestSingle` for quests 10944/11007 inside Questie. Content phases remain consumer policy in QuestieTDB. |

Entity **id sets match exactly** on all five flavours and all four types — zero
`ID_ONLY_IN_*` rows. Storage, generation and enumeration are not implicated in anything above.

## Closed

| Class | Was | Closed by |
| --- | ---: | --- |
| `Quest.objectives` absent-vs-`{}` | 1,654 / 2,708 / 3,574 / 5,947 / 6,868 | Never-nil structures. `readers["objectives"]` and `readers["questgivers"]` always construct a table, so the field reads `{}` for an entity that exists. `normalize.default` is the single definition; Source mode reaches it through `normalize.field`, Baked mode caches it per entity type, and `encode` still omits the line — no stored bytes. |
| `Quest.startedBy` absent-vs-`{}` | 84 / 372 / 557 / 4,596 / 5,090 | Same. |
| `Quest.finishedBy` absent-vs-`{}` | 76 / 366 / 527 / 470 / 1,175 | Same. |
| `Quest.objectives` value | 2,495 / 3,690 / 5,200 / 8,158 / 9,451 | Element-level nil→0. Questie's tuple writers emit `value or 0` and its readers read every slot, so `objective[3]`, `spellObjective[3]` and `killCredit[4]` come back as `0`. Padded in `normalize`, so both modes agree by construction. |
| `Quest.extraObjectives` value | 7 / 25 / 54 / 99 / 116 | Same rule, row slot `[4]` (objectiveIndex). |
| `Npc.waypoints` value | 454 / 808 / 1,095 / 1,153 / 1,158 | `src/derived/waypoints.lua`, the first Derived Pass. Verified at **zero** on all five flavours, with `verify`, `equivalence`, `reconstruct` and determinism all green. |
| `Object.waypoints` value | – / – / – / 3 / 3 | Same pass. |
| Phantom entities from inherited Corrections | 0 / 0 / 1 / 4 / 99 ids, plus inherited fields | The Correction registry derives each file's source expansion and applies Questie's `noNewEntries` rule when a later flavor inherits it. Older Corrections can update surviving rows, but only a field-1/name Correction may create a missing entity. |
| `Quest.questFlags` value | – / – / 2 / 72 / 72 | Resolved by the pinned Correction re-port. |
| `Quest.reputationReward` absent-vs-value | – / – / 1 / 1 / 1 | Resolved by the pinned Correction re-port. |
| WotLK NPC Static Correction order | – / – / 20 / 20 / 20 | The generated manifest now follows Questie: `LoadAutomatics()` first, then hand-authored `Load()`. This removed 16 wrong-value and four absent-vs-value spawn divergences per affected flavor. A real overlap on NPC 30208 guards the order. |

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

## Tracked on GitHub

Work is tracked at [`Questie/QuestieTDB`](https://github.com/Questie/QuestieTDB/issues).
This ledger records the implementation status even when the corresponding GitHub issue has not
yet been closed.

| Issue | Work | Status here |
| --- | --- | --- |
| [#1](https://github.com/Questie/QuestieTDB/issues/1) | Materialize the derived `requiredRaces` patch | Open |
| [#2](https://github.com/Questie/QuestieTDB/issues/2) | Triage the three unexplained divergence classes | Resolved by the pinned re-port and WotLK order fix |
| [#3](https://github.com/Questie/QuestieTDB/issues/3) | Decide whether the overlay quantizes coordinates | Open |
| [#4](https://github.com/Questie/QuestieTDB/issues/4) | Validator baseline is stale, 78 new findings | Reviewed and refreshed in `validator-baseline-review.md` |
| [#5](https://github.com/Questie/QuestieTDB/issues/5) | Baked artifacts ship static correction bodies | Implemented by package-time stripping; live-client acceptance remains with #6 |
| [#6](https://github.com/Questie/QuestieTDB/issues/6) | Mists in-client acceptance at 112 MiB | Open |
| [#7](https://github.com/Questie/QuestieTDB/issues/7) | Differential missing from `release.yml` | Resolved; release publication depends on the matrix |
| [#8](https://github.com/Questie/QuestieTDB/issues/8) | Pin the Questie input checkout | Resolved by `QUESTIE_COMMIT` and shared workflow checkout |
| [#9](https://github.com/Questie/QuestieTDB/issues/9) | Decide where corrections are authored after phase 13 | Open |
| [#10](https://github.com/Questie/QuestieTDB/issues/10) | Institutionalize the live-client probe ritual | Open |
| [#11](https://github.com/Questie/QuestieTDB/issues/11) | Decide the decoded-cache budget | Open |
| [#12](https://github.com/Questie/QuestieTDB/issues/12) | Distribution polish: flavor table, wrong-flavor no-op, `builtAt` | Open |

## Open questions

1. **Overlay coordinate quantization** — now the largest remaining class after
   `requiredRaces`. Match Questie (return correction coordinates
   verbatim, accepting that the same field is quantized from base data and unquantized from
   the overlay), or keep QuestieTDB's uniform treatment and baseline the difference?
