# SoD requiredRaces audit before #13

This is historical evidence, not a baseline or a runtime correction list.

- QuestieTDB before the fix: `e196726`.
- Pinned Questie: `92ab8206f8fa24fdbf772a0d2330abddbc78396a`.
- Inventory: [`sod-required-races-before.tsv`](sod-required-races-before.tsv).
- Active SoD: 25 differing quests among 5,534, identical for Alliance Human Warrior and Horde Orc Warrior.
- Direction: all 25 return explicit `0` in QuestieTDB. Questie returns 20 `ALL_ALLIANCE` (`77`) and five `ALL_HORDE` (`178`) masks.
- All 25 are SoD-added quests: 16 generated base entries and nine correction-added entries.
- Plain Vanilla: zero differences among 4,257 quests for the default Alliance persona.

## Reproduce the focused comparison

Run from an isolated QuestieTDB copy; dumps are written under `.out/differential/`.
Pass the absolute path to the pinned Questie checkout if its sibling location differs.

```sh
uv run tools/differential/compiler_diff.py Vanilla --season=SoD --only=Quest.requiredRaces --questie=../Questie --self-check
uv run tools/differential/compiler_diff.py Vanilla --season=SoD --faction=Horde --only=Quest.requiredRaces --questie=../Questie --self-check
uv run tools/differential/compiler_diff.py Vanilla --only=Quest.requiredRaces --questie=../Questie --self-check
uv run tools/differential/compiler_diff.test.py
```

The seasonal runs failed with 25 differences before the fix. Their self-checks detected exactly one additional difference. The plain Vanilla run passed, including its self-check.

`--only=Quest.requiredRaces` is strict: it accepts no baseline differences, includes explicit nil fields, compares entity presence, and rejects an empty comparison. Query errors abort the focused dumper. Both sides run with the same faction and season. These commands compare Source-mode composed reads with Questie's actual initialization, compilation, and public `QueryQuestSingle` reads. Source/Baked equality is a separate check.

## Inference-stage evidence

The TSV includes the inputs immediately before Questie's inference, not a reconstruction from final faction-adjusted starters. The initial audit captured `QuestieCorrections:Initialize` immediately before its inference loop and immediately before `MinimalInit`. Its independently calculated masks matched the actual post-inference rows. All 25 final values were then reconfirmed through the repaired compiler differential.

For example, 13 shipment quests infer Alliance from starter NPC `214101:A`. Horde's later `MinimalInit` changes their starters to Horde NPCs without recomputing races. A derivation over the final corrected starters would therefore disagree with Questie's returned values. Preserving those values is the migration contract; changing their gameplay meaning is a separate upstream task.

The inventory is complete for this pinned input. Future fidelity checks must compare all current quests rather than restrict themselves to these 25 IDs.
