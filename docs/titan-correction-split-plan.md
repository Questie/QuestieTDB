# Titan Correction split status and remaining plan

## Status

Implementation is complete. Full all-flavor validation is still pending.

Questie PR [#7784](https://github.com/Questie/Questie/pull/7784) merged as:

```text
b1a6dc8c50a92ab88723a11556421d6462cdea49
```

QuestieTDB is pinned to that commit. The worktree is intentionally uncommitted so the remaining
validation can review the complete change before it is committed.

## Permanent design

These decisions are implemented and should not be reopened during validation unless evidence
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
- [x] Marked issue #16 as implemented with full validation pending in
  `docs/questie-handover.md`.
- [x] Marked the old per-function gate discussion in `CLAUDE_REVIEW_FINDINGS.md` as historical.

### Reviewed data changes

- [x] Refreshed the Wrath Golden snapshot after reviewing:
  - 60 Titan-only entities removed from plain Wrath.
  - 30 inherited entities with changed composed hashes.
- [x] Removed the obsolete Wrath validator baseline entry for Titan quest `96211`.
- [x] Confirmed the resulting Wrath Golden and validator gates are clean.

## Validation already completed

The following checks passed against a clean Questie project directory at the pinned commit:

- [x] `git diff --check`.
- [x] TOC suite: 159 checks, 0 failed.
- [x] Correction fidelity: 284 checks, 0 failed.
- [x] Source and Baked personas: 61 checks, 0 failed.
- [x] Read contract: 62 checks, 0 failed.
- [x] Reconstruction negative control with a localized Vanilla artifact: 3 checks, 0 failed.
- [x] Wrath round-trip verification: 88,640 entities, 1,454,521 fields, 0 errors.
- [x] Wrath Source/Baked equivalence.
- [x] Wrath validators: no new or stale accepted findings after the reviewed baseline change.
- [x] Wrath Golden composed reads: no differences after the reviewed refresh.
- [x] Mechanical Correction fidelity for every manifest file.
- [x] Four Titan files byte-identical to the pinned Questie sources.
- [x] Fresh focused review with no findings.

Temporary generated flavor TOCs were removed after validation.

## Remaining work

### 1. Prepare a clean Questie project directory

On the validation computer, set a shell variable to a clean Questie checkout:

```sh
QUESTIE_DIR="<a clean Questie project directory>"
```

The checkout must have no local changes and must be at the exact commit in `QUESTIE_COMMIT`.
Verify without changing the checkout:

```sh
git -C "$QUESTIE_DIR" status --short
git -C "$QUESTIE_DIR" rev-parse HEAD
cat QUESTIE_COMMIT
```

If the checkout is not clean or is used for active Questie development, create a separate clean
Questie project directory instead of changing it in place.

### 2. Re-run the mechanical drift gates

From the QuestieTDB project directory:

```sh
lua5.1 generate.lua meta --questie="$QUESTIE_DIR"
lua5.1 tools/port-corrections.lua "$QUESTIE_DIR"
lua5.1 generate.lua toc
```

Review the worktree afterward. These commands should reproduce the already reviewed files. They
must not restore content-phase functions, old embedded Titan providers, or consumer policy.

Expected permanent output:

- Four files under `src/corrections/Titan/`.
- Four Titan manifest entries.
- Eight Titan Dynamic providers.
- No `LoadTitanReforgedFixes` implementation.
- No per-function variant gate in the generated manifest.
- No copied `LoadContentPhaseFixes` bodies.
- `QuestieTDB.toc` lists all four Titan files.

### 3. Run the complete all-flavor matrix

This is the main remaining task:

```sh
./questietdb all --questie="$QUESTIE_DIR"
```

This should cover Generation, unit tests, round-trip verification, Source/Baked equivalence,
reconstruction, validators, Golden snapshots, and the Questie compiler differential for all
five base flavors.

Do not treat a failure as a request to refresh a baseline automatically. The pin advance also
ported unrelated upstream Correction changes, especially in TBC, Wrath, Cata, and Mists.
Classify every changed entity first.

### 4. Review any non-Wrath changes

The focused pass reviewed Wrath. The complete matrix may expose intentional upstream changes in
other flavors.

For each failure:

1. Compare the entity and field against the pinned Questie source.
2. Decide whether it came from the mechanical Correction re-port, schema drift, runtime gating,
   or an actual QuestieTDB regression.
3. Confirm Titan-only IDs never appear in plain Wrath or another flavor.
4. Confirm TBC and MoP content-phase exclusions did not return.
5. Confirm no Titan tags, blacklists, or calendar policy entered the entity files.
6. Update an accepted record only after the change is understood.

If a Golden change is intentional:

```sh
uv run python tools/differential/golden.py refresh <Flavor> --lua=lua5.1
```

If validator findings intentionally changed:

```sh
lua5.1 validators/run.lua <Flavor> --update-baseline
```

If a compiler differential baseline intentionally changed:

```sh
uv run python tools/differential/compiler_diff.py <Flavor> \
  --questie="$QUESTIE_DIR" --update-baseline
```

Review each baseline diff directly, then rerun the failing gate before continuing.

### 5. Re-run the full matrix after accepted-record changes

If any Golden, validator, or compiler baseline changes were needed, run the complete matrix again:

```sh
./questietdb all --questie="$QUESTIE_DIR"
```

The final run must pass without unreviewed output changes.

### 6. Final review and issue status

After the full matrix passes:

- [ ] Run `git diff --check` again.
- [ ] Confirm no generated flavor TOCs or validation scratch files are staged.
- [ ] Review the complete diff, including unrelated upstream Correction changes from the pin.
- [ ] Ask for one final focused review if validation changed any accepted records.
- [ ] Update `docs/questie-handover.md` from “full validation pending” to resolved.
- [ ] Close GitHub issue #16 with the gate matrix and validation evidence.
- [ ] Prepare the final commit or pull request. Do not commit before the reviewed matrix is green.

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
tools/differential/golden/Wrath.tsv
validators/baseline/Wrath.txt
```

Additional flavor baselines belong in the change only when the remaining all-flavor review
proves they are intentional.

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
- [ ] The complete all-flavor matrix passes.
- [ ] Any non-Wrath Golden, validator, or compiler baseline changes are reviewed.
- [ ] Issue #16 and its status documentation are finalized.
- [ ] The final diff is reviewed and ready to commit.
