# Titan Correction split completion record

## Status

Implementation and full all-flavor validation are complete. The GitHub issue remains open until
the validation evidence is posted.

Questie PR [#7784](https://github.com/Questie/Questie/pull/7784) merged as:

```text
b1a6dc8c50a92ab88723a11556421d6462cdea49
```

QuestieTDB is pinned to that commit. The reviewed accepted-record updates from the full matrix
were committed as `d2ac61d` (`test(corrections): refresh Titan split baselines`).

## Permanent design

These decisions are implemented and validated. They should not be reopened unless evidence
shows a defect:

1. Titan Reforged is a Dynamic Correction set over the Wrath database, like SoD over Era.
2. QuestieTDB continues to ship one Wrath TOC metadata store. It does not add a separate Titan
   artifact.
3. Every provider from the four Titan entity files is Dynamic in QuestieTDB.
4. The complete Titan set registers only when the active flavor is Wrath and the active season
   ID is `109`.
5. All four Titan source files are mandatory. Missing files are a hard port failure.
6. WotLK Correction files contain no Titan providers.
7. Titan quest tags and availability blacklists stay in Questie as consumer policy.
8. TBC and MoP content-phase functions stay excluded under ADR 0007.
9. No old-layout fallback, layout detection, compatibility shim, or conditional compatibility
   test remains.
10. `contractVersion` remains `1` because no released consumer depended on the old arrangement.

## Completed work

### Upstream pin and mechanical port

- [x] Advanced `QUESTIE_COMMIT` from
  `7615c03bd4294b046f3db66c2a2e97a3b49c39ef` to
  `b1a6dc8c50a92ab88723a11556421d6462cdea49`.
- [x] Verified the selected Questie commit contains the merged four-file Titan split.
- [x] Regenerated the schema against a clean Questie project directory. No committed schema
  changes were required.
- [x] Mechanically re-ported all Questie Correction files from the selected commit.
- [x] Regenerated `QuestieTDB.toc`.
- [x] Added these committed provider files:
  - `src/corrections/Titan/titanReforgedQuestFixes.lua`
  - `src/corrections/Titan/titanReforgedNPCFixes.lua`
  - `src/corrections/Titan/titanReforgedItemFixes.lua`
  - `src/corrections/Titan/titanReforgedObjectFixes.lua`
- [x] Refreshed Correction files for the other expansions as required by the new Questie pin.
- [x] Kept the copied `src/derived/RamerDouglasPeucker.lua` faithful to the pin.

### Compatibility removal

- [x] Deleted the transitional `generator/correction-layout.lua` module.
- [x] Removed split-layout detection and partial-layout handling.
- [x] Removed old WotLK-embedded Titan provider support.
- [x] Removed per-function variant-gate machinery from runtime registration and manifest
  generation.
- [x] Removed conditional legacy-versus-split tests and counts.
- [x] Made the four Titan file declarations unconditional in `tools/port-corrections.lua`.
- [x] Confirmed no implementation reference to `LoadTitanReforgedFixes` remains.

### Permanent provider manifest

The generated manifest now declares exactly these providers in this order:

| File | Datatype | Dynamic providers |
| --- | --- | --- |
| `Titan/titanReforgedQuestFixes.lua` | Quest | `LoadQuests`, `LoadQuestOverrides` |
| `Titan/titanReforgedNPCFixes.lua` | Npc | `LoadNPCs`, `LoadNPCOverrides`, `LoadFactionNPCOverrides` |
| `Titan/titanReforgedItemFixes.lua` | Item | `LoadItems`, `LoadItemOverrides` |
| `Titan/titanReforgedObjectFixes.lua` | Object | `LoadObjects` |

All four entries use exact expansion membership:

```lua
expansions = { Wotlk = true }
```

This prevents season `109` from admitting Titan Corrections on Cata or Mists.

### Runtime behavior

- [x] Added file-level `Titan/` recognition in `src/corrections/register.lua`.
- [x] Required both Wrath and season `109`.
- [x] Kept the gate closed when flavor or `C_Seasons` information is unavailable.
- [x] Added a dedicated Titan load-order window after WotLK.
- [x] Registered all eight providers only after the complete file-level gate succeeds.
- [x] Preserved provider order so base rows load before overrides and faction overrides run last.
- [x] Kept SoD and Titan as independent gated Dynamic sets.

The permanent registration matrix is:

| Flavor | Season | Titan registers |
| --- | --- | --- |
| Wrath | 109 | yes |
| Wrath | none | no |
| Wrath | SoD | no |
| Vanilla | 109 | no |
| TBC | 109 | no |
| Cata | 109 | no |
| Mists | 109 | no |
| Wrath | missing seasons API | no |

### ADR 0007 ownership cleanup

- [x] Removed and excluded `QuestieTBCQuestFixes:LoadContentPhaseFixes`.
- [x] Removed and excluded `MopQuestFixes:LoadContentPhaseFixes`.
- [x] Removed and excluded `MopNpcFixes:LoadContentPhaseFixes`.
- [x] Removed and excluded `MopObjectFixes:LoadContentPhaseFixes`.
- [x] Kept existing Darkmoon ownership exclusions.
- [x] Updated the port exclusion helper to handle the ordinary comments attached to the
  upstream content-phase functions.
- [x] Kept Titan quest tags and availability blacklists out of QuestieTDB.

### Tests

- [x] Assert exactly four Titan manifest files.
- [x] Assert the exact four paths, datatypes, expansion gates, and provider lists.
- [x] Assert exactly eight Titan Dynamic providers.
- [x] Assert the exact provider registration order and numeric load order.
- [x] Assert WotLK files expose only their ordinary faction providers.
- [x] Assert the retired per-function manifest field is absent.
- [x] Assert Source mode includes all four Titan files.
- [x] Assert only the Wrath Baked file list includes them.
- [x] Cover the complete registration matrix, including Cata and Mists season-109 rejection.
- [x] Cover representative public reads for all eight providers.
- [x] Assert representative Titan-only entities return true from `Exists`.
- [x] Assert representative Titan-only entities appear in composed enumeration.
- [x] Run those entity assertions in both Source and Baked mode.
- [x] Assert representative Titan-only entities remain absent from plain Wrath.
- [x] Keep Correction fidelity exclusions aligned with ADR 0007 ownership.

Representative provider probes currently cover:

| Provider | Assertion |
| --- | --- |
| `LoadQuests` | Quest `93950` is `"A Message From The Stars"` |
| `LoadQuestOverrides` | Quest `6823` has level and required level `80` |
| `LoadNPCs` | NPC `257012` is `"Algalon the Observer"` |
| `LoadNPCOverrides` | NPC `14834` has minimum level `83` |
| `LoadFactionNPCOverrides` | Horde NPC `257012` uses Durotar |
| `LoadItems` | Item `264272` is `"Celestial Missive"` |
| `LoadItemOverrides` | Item `22734` drops from NPC `15172` |
| `LoadObjects` | Object `420002` is `"Blood Ritual Altar"` |

### CI and documentation

- [x] Added a Source TOC drift check before flavor Generation can mask it.
- [x] Added a Wrath runtime fixture so Baked Titan persona tests cannot silently skip in CI.
- [x] Updated the README re-sync process to include Source TOC regeneration.
- [x] Updated `CONTEXT.md` from a per-function gate term to a gated Dynamic set.
- [x] Kept issue #16's implementation and validation status synchronized in
  `docs/questie-handover.md`.
- [x] Marked the old per-function gate discussion in `CLAUDE_REVIEW_FINDINGS.md` as historical.

### Reviewed data changes

- [x] Refreshed the Wrath Golden snapshot after reviewing:
  - 60 Titan-only entities removed from plain Wrath.
  - 30 inherited entities with changed composed hashes.
- [x] Removed the obsolete Wrath validator baseline entry for Titan quest `96211`.
- [x] Refreshed the remaining Golden snapshots after reviewing every changed entity:
  - Vanilla: 5 upstream Correction changes.
  - TBC: 26 upstream Correction changes.
  - Cata: 60 Titan-only entities removed and 32 inherited hashes changed.
  - Mists: 60 Titan-only entities removed and 31 inherited hashes changed.
- [x] Removed 67 Titan-derived accepted validator findings from both Cata and Mists.
- [x] Refreshed compiler baselines only for reviewed reductions:
  - TBC: 3 prerequisite-field divergences resolved by the active phase advancing to 3.
  - Wrath, Cata, and Mists: 11 health-field divergences removed with six Titan-only NPCs.
- [x] Confirmed all resulting Golden, validator, and compiler gates are clean.

## Validation

The following checks passed against a clean Questie project directory at the pinned commit:

- [x] Mechanical schema, Correction, and Source TOC regeneration produced no tracked changes.
- [x] Full all-flavor matrix: 31 jobs passed.
- [x] Test suite: 1,613 checks, 0 failed.
- [x] TOC suite: 159 checks, 0 failed.
- [x] Correction fidelity: 284 checks, 0 failed.
- [x] Source and Baked personas: 61 checks, 0 failed.
- [x] Read contract: 62 checks, 0 failed.
- [x] Reconstruction negative control with a localized Vanilla artifact: 3 checks, 0 failed.
- [x] Round-trip verification, Source/Baked equivalence, reconstruction, validators, Golden
  snapshots, and compiler differentials passed for all five base flavors.
- [x] Wrath round-trip verification: 88,640 entities, 1,454,521 fields, 0 errors.
- [x] No Titan-only entity leaked into Vanilla, TBC, plain Wrath, Cata, or Mists.
- [x] Four Titan files are byte-identical to the pinned Questie sources.
- [x] `git diff --check` passed.
- [x] Two fresh focused reviews completed with no findings.
- [x] Generated flavor TOCs and validation scratch files remained ignored and unstaged.

## Remaining work

- [ ] Close GitHub issue #16 with the pin, gate matrix, accepted-record review, and final validation
  evidence.
- [ ] Commit this completion record and the matching handover-ledger update.

## Expected final file groups

The completed change should contain:

### Hand-written implementation and tooling

```text
.github/workflows/ci.yml
CONTEXT.md
README.md
src/corrections/register.lua
src/corrections/registry.lua
test.lua
tools/port-corrections.lua
```

### Mechanically generated or ported data

```text
QUESTIE_COMMIT
QuestieTDB.toc
src/corrections/manifest.lua
src/corrections/Titan/*.lua
src/corrections/Era/*.lua
src/corrections/Tbc/*.lua
src/corrections/Wotlk/*.lua
src/corrections/Cata/*.lua
src/corrections/MoP/*.lua
src/corrections/Sod/*.lua
```

Only files actually changed by the selected Questie pin should appear in the final diff.

### Reviewed accepted records

```text
tools/differential/golden/{Vanilla,TBC,Wrath,Cata,Mists}.tsv
tools/differential/compiler-baseline/{TBC,Wrath,Cata,Mists}.tsv
validators/baseline/{Wrath,Cata,Mists}.txt
```

### Status and historical documentation

```text
CLAUDE_REVIEW_FINDINGS.md
docs/questie-handover.md
docs/titan-correction-split-plan.md
```

## Completion criteria

This work is fully complete only when:

- [x] No legacy/split compatibility implementation remains.
- [x] Four Titan files are mechanically ported.
- [x] Eight Titan Dynamic providers are declared in the required order.
- [x] Titan applies only on Wrath season `109`.
- [x] Plain Wrath excludes representative Titan-only entities.
- [x] Source and Baked representative reads cover all eight providers.
- [x] TBC and MoP content-phase functions remain excluded.
- [x] Correction fidelity passes against the pinned Questie commit.
- [x] The committed Source TOC matches configuration.
- [x] Focused implementation review has no findings.
- [x] The complete all-flavor matrix passes.
- [x] Non-Wrath Golden, validator, and compiler baseline changes are reviewed.
- [x] Reviewed accepted-record changes are committed.
- [x] Status documentation records the completed validation.
- [ ] GitHub issue #16 is closed with the validation evidence.
- [ ] The status documentation is committed.
