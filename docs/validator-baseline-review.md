# Validator baseline review

This document records the review behind the validator baseline refresh. The baseline is an
acceptance ledger for known findings, not evidence that every row is correct.

## Why the baseline changed

The previous fingerprint format stored printed reason lines without their owner. A nested line
such as `quest 27021 is missing in questStarts` did not identify NPC 3061, while owner headings
were inconsistently counted as separate findings. The new format is:

```text
<check>|<EntityType>:<id>|<reason>
```

Owner headings establish context but are not findings. Repeated identical reasons remain a
multiset, so a second occurrence still fails unless separately baselined.

## Review of issue #4

Before this change, Wrath, Cata and Mists had 78 new fingerprints and 232 fingerprints that no
longer occurred.

Of the 78 new fingerprints:

- 27 were relations involving quests removed by Questie's blacklist or other consumer policy.
- 43 were partial Mists quest rows created by inherited Static Corrections. Those quests were
  absent from raw Mists data, actively blacklisted, and lacked `requiredRaces`.
- 2 described objectives on blacklisted quest 503.
- 6 exposed three real inherited relation defects, repeated in Cata and Mists:
  - NPC 3061 is missing quest 27021 from `questStarts`.
  - NPC 7406 is missing quest 25476 from `questEnds`.
  - NPC 7944 is missing quest 29477 from `questEnds`.

Those three defects also exist in the pinned Questie Correction sources. They remain in the
baseline to preserve exact upstream fidelity outside explicitly declared provider/consumer
ownership exclusions. They should be fixed upstream and then removed here by re-porting.

The inherited-Correction application bug was fixed after this first classification. Older
expansion Corrections may now update a surviving entity but cannot create an absent one unless
the row supplies field 1, matching Questie's `_LoadCorrections`. Removing those phantom rows
made previously hidden references visible:

- Cata gained one objective on blacklisted quest 2359 pointing to blacklisted item 7923.
- Mists gained 101 relations to 90 absent quests. Every one is in Questie's active Mists
  blacklist, plus the same quest 2359/item 7923 objective.
- 96 Mists baseline rows disappeared. Most were `requiredRaces` findings on the phantom rows;
  the remainder were relations attached to them.

These 103 new owner-aware findings are consumer-policy fallout, not playable-data regressions,
and are accepted deliberately in the final baseline.

The original 232 removed fingerprints were also mixed:

- 24 `requiredSourceItems` findings were genuine data cleanup.
- 39 Mists `questEnd ... is not in the database` findings moved to the synthetic-quest
  `requiredRaces` category. The consumer-policy condition did not disappear.
- Most remaining relation changes involved blacklisted quests and were policy churn rather
  than changes to playable data.

## Refreshed baseline

After owner-aware fingerprinting, the accepted finding counts are:

| Flavor | Findings |
| --- | ---: |
| Vanilla | 0 |
| TBC | 1 |
| Wrath | 6 |
| Cata | 263 |
| Mists | 1,473 |

Any new owner/reason pair fails validation. Update these files only after classifying the new
rows as consumer policy, a data defect, or a validator defect.
