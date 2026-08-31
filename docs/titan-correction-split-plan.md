# Titan Correction split plan

## Purpose

Finish the Titan Reforged Correction split after Questie PR
[#7784](https://github.com/Questie/Questie/pull/7784), merged as
`b1a6dc8c50a92ab88723a11556421d6462cdea49` on 2026-08-31.

The current QuestieTDB worktree prepares both Questie's old embedded layout and its new split
layout. That transition support is unnecessary. QuestieTDB is unreleased, Titan files now
always exist upstream, and no consumer needs compatibility with the old arrangement.

The final implementation must support only the split layout.

## Safety constraint

Do not access, inspect, modify, check out, reset, clean, fetch, or otherwise touch:

```text
/home/david/private/qu-tdb/questie
```

That is David's active Questie worktree. Use a separate clean disposable checkout for the
mechanical re-port and all Questie-backed validation.

## Locked decisions

1. Titan Reforged is a Dynamic Correction set over the Wrath database, like SoD over Era.
2. QuestieTDB continues to ship one Wrath TOC metadata store. It does not add a Titan TOC.
3. Every function in the four Titan entity files is Dynamic in QuestieTDB, even when Questie
   calls that function before compiling its separate Titan cache.
4. The complete Titan set registers only for Wrath with active season `109`.
5. The four Titan source files are mandatory. A missing file is a normal hard port failure.
6. WotLK Correction files contain no Titan providers.
7. Titan quest tags and availability blacklists stay in Questie. They are consumer semantics
   and policy, not QuestieTDB entity data.
8. TBC and MoP content-phase functions stay excluded under ADR 0007.
9. No old-layout fallback, layout detection, compatibility shim, or conditional test remains.
10. `contractVersion` remains `1`. No released consumer depends on the old arrangement.

## Current worktree

Branch: `ownership`

Current Questie pin:

```text
7615c03bd4294b046f3db66c2a2e97a3b49c39ef
```

That pin predates the split and must advance atomically with the re-port.

The worktree currently has uncommitted changes in:

```text
.github/workflows/ci.yml
README.md
src/corrections/MoP/mopNPCFixes.lua
src/corrections/MoP/mopObjectFixes.lua
src/corrections/MoP/mopQuestFixes.lua
src/corrections/Tbc/tbcQuestFixes.lua
src/corrections/manifest.lua
src/corrections/register.lua
src/corrections/registry.lua
test.lua
tools/port-corrections.lua
```

It also has the untracked transitional file:

```text
generator/correction-layout.lua
```

Do not discard the whole worktree. It contains useful ownership, runtime, test, documentation,
and CI work. Remove only the transition machinery identified below.

## Keep from the current changes

### Runtime behavior

Keep these parts of `src/corrections/register.lua`:

- `Titan/` file recognition.
- File-level Titan gating.
- The exact predicate requiring both Wrath and season `109`.
- Fail-closed behavior when `C_Seasons` or the flavor is absent.

Keep the dedicated Titan load-order window in `src/corrections/registry.lua`. Titan must apply
after inherited WotLK Dynamic Corrections.

Titan manifest entries must use:

```lua
expansions = { Wotlk = true }
```

Do not use `minExpansionOrder = 3`. That also admits Cata and Mists.

### ADR 0007 ownership cleanup

Keep the port exclusions and copied-file removals for:

- `QuestieTBCQuestFixes:LoadContentPhaseFixes`
- `MopQuestFixes:LoadContentPhaseFixes`
- `MopNpcFixes:LoadContentPhaseFixes`
- `MopObjectFixes:LoadContentPhaseFixes`

Keep the existing Darkmoon exclusions.

Keep the updated exclusion helper that accepts an attached ordinary `--` comment as well as a
LuaDoc `---` block. The upstream content-phase functions use ordinary comments.

### Tests and CI

Keep:

- The exact `QuestieTDB.toc` versus `config.sourceFileList()` assertion.
- The CI Source TOC drift gate before flavor Generation can rewrite the file.
- The CI no-localization Wrath runtime fixture.
- Source and Baked Titan persona coverage.
- Exact Titan file-list assertions.
- Representative public reads for all eight Titan providers.
- Plain Wrath isolation assertions.

### Documentation

Keep the README instruction to run:

```sh
lua5.1 generate.lua toc
```

after the Correction port.

## Remove the compatibility design

### Delete the layout module

Delete:

```text
generator/correction-layout.lua
```

Remove its import and the `correction-layout` suite from `test.lua`.

### Simplify `tools/port-corrections.lua`

Remove:

- `correctionLayout` import.
- Split-file counting and detection.
- `HAS_SPLIT_TITAN_CORRECTIONS`.
- `WOTLK_DYNAMIC` and `WOTLK_DYNAMIC_GATES`.
- `requiresSplitTitan`.
- `SELECTED_FILES` and conditional file selection.
- Transitional comments about legacy and split layouts.
- `gatedDynamic` serialization.

Every loop should use the one unconditional `FILES` list.

The WotLK entries should declare only their ordinary Dynamic function:

```lua
dynamic = { "LoadFactionFixes" }
```

They must not mention `LoadTitanReforgedFixes`.

### Simplify `src/corrections/register.lua`

Remove:

- `register.variantActive`.
- Per-function `gatedDynamic` lookup.
- Legacy gate invocation.
- Comments about embedded WotLK Titan functions.

Once a manifest entry passes its expansion and file-level variant checks, register every
function listed in `spec.dynamic` directly.

Keep independent file-level gates:

- `Sod/` requires the active SoD season.
- `Titan/` requires Wrath and season `109`.

### Simplify tests

Remove:

- `FakeLegacyTitan`.
- Legacy provider counts.
- `usesSplitTitan`.
- Three-versus-eight expected count branches.
- Conditional split assertions.
- All wording about old pins, old layouts, or transitions.

The permanent assertions should expect exactly four Titan files and eight Dynamic provider
functions.

## Permanent port declarations

Declare these four files unconditionally in `tools/port-corrections.lua`.

### Quest

```lua
{
  src = "titanReforgedQuestFixes.lua",
  dst = "Titan/titanReforgedQuestFixes.lua",
  datatype = "Quest",
  expansions = { Wotlk = true },
  module = "TitanReforgedQuestFixes",
  dynamic = { "LoadQuests", "LoadQuestOverrides" },
}
```

### NPC

```lua
{
  src = "titanReforgedNPCFixes.lua",
  dst = "Titan/titanReforgedNPCFixes.lua",
  datatype = "Npc",
  expansions = { Wotlk = true },
  module = "TitanReforgedNpcFixes",
  dynamic = { "LoadNPCs", "LoadNPCOverrides", "LoadFactionNPCOverrides" },
}
```

### Item

```lua
{
  src = "titanReforgedItemFixes.lua",
  dst = "Titan/titanReforgedItemFixes.lua",
  datatype = "Item",
  expansions = { Wotlk = true },
  module = "TitanReforgedItemFixes",
  dynamic = { "LoadItems", "LoadItemOverrides" },
}
```

### Object

```lua
{
  src = "titanReforgedObjectFixes.lua",
  dst = "Titan/titanReforgedObjectFixes.lua",
  datatype = "Object",
  expansions = { Wotlk = true },
  module = "TitanReforgedObjectFixes",
  dynamic = { "LoadObjects" },
}
```

Provider order is load-bearing:

1. Add Titan rows.
2. Modify inherited Wrath rows.
3. Apply faction-specific Titan values.

The copied Titan functions use dot-call definitions. The existing wrapper passes an extra
receiver, which Lua ignores. No adapter is needed.

## Atomic Questie re-sync

### 1. Choose the target Questie commit

PR #7784 merged as:

```text
b1a6dc8c50a92ab88723a11556421d6462cdea49
```

At execution time, select one exact Questie `master` commit that contains this merge and the
latest Corrections intended for the re-sync. Record the full lowercase SHA. Do not pin the old
PR head.

Verify the selected commit is a descendant of the merge commit.

### 2. Create a disposable clean checkout

Use a path outside the protected Questie worktree, for example:

```sh
SYNC_DIR="/tmp/questie-tdb-titan-sync"
git clone https://github.com/Questie/Questie.git "$SYNC_DIR"
git -C "$SYNC_DIR" checkout --detach "<selected-sha>"
```

Before using it:

```sh
git -C "$SYNC_DIR" status --short
git -C "$SYNC_DIR" rev-parse HEAD
```

The status must be empty and HEAD must equal the selected SHA.

### 3. Advance the pin

Write the selected SHA to:

```text
QUESTIE_COMMIT
```

The pin, tooling simplification, and re-port belong in one atomic change.

### 4. Finish split-only code changes

Apply the removals and unconditional declarations above before running the port. It is fine for
the working tree to refer briefly to Titan files not yet copied into `src/corrections/`.

### 5. Re-materialize from the clean checkout

Run:

```sh
lua5.1 generate.lua meta --questie="$SYNC_DIR"
lua5.1 tools/port-corrections.lua "$SYNC_DIR"
lua5.1 generate.lua toc
```

The port must fail normally if any Titan source file is absent.

### 6. Review the mechanical output

Review:

```text
QUESTIE_COMMIT
src/meta/
src/corrections/
src/derived/RamerDouglasPeucker.lua
QuestieTDB.toc
```

Expected results:

- Four new files under `src/corrections/Titan/`.
- Titan-only rows removed from the copied WotLK files.
- No `LoadTitanReforgedFixes` definition or manifest entry.
- Four `Titan/` manifest entries.
- Eight Titan Dynamic functions.
- No `gatedDynamic` anywhere.
- No `LoadContentPhaseFixes` registration or copied function body.
- Existing Darkmoon functions remain excluded.
- `QuestieTDB.toc` lists all four Titan files.

The pin advance may also bring unrelated Correction, schema, constant, or localization changes.
Review those against the selected Questie commit rather than treating them as Titan work.

## Permanent runtime contract

### Registration matrix

| Flavor | Season | Titan registers |
| --- | --- | --- |
| Wrath | 109 | yes |
| Wrath | none | no |
| Wrath | SoD | no |
| Vanilla | 109 | no |
| TBC | 109 | no |
| Cata | 109 | no |
| Mists | 109 | no |
| Wrath | missing `C_Seasons` | no |

### Source mode

The committed base TOC loads all four Titan files. Registration remains closed unless the
client is Titan Reforged.

### Baked mode

Only the Wrath flavor TOC lists the four Titan files. Vanilla, TBC, Cata, and Mists exclude
them.

The Wrath TOC metadata store contains ordinary Wrath base data. Titan-only rows enter through
the Correction Overlay and Composed enumeration.

## Tests

### Manifest assertions

Assert unconditionally:

- Exactly four manifest paths begin with `Titan/`.
- Exactly eight Dynamic functions are declared across them.
- No WotLK entry declares `LoadTitanReforgedFixes`.
- No manifest entry has `gatedDynamic`.
- Source mode lists all four Titan files.
- Wrath Baked mode lists all four Titan files.
- Every other baked flavor lists none.
- `QuestieTDB.toc` exactly matches `config.sourceFileList()`.

### Provider behavior

Exercise these through public reads in both Source and Baked mode. Confirm the values against
the final merged Questie source before retaining the literals.

| Provider | Representative assertion from the merged PR |
| --- | --- |
| `LoadQuests` | Quest `93950` is `"A Message From The Stars"` |
| `LoadQuestOverrides` | Quest `6823` has level and required level `80` |
| `LoadNPCs` | NPC `257012` is `"Algalon the Observer"` |
| `LoadNPCOverrides` | NPC `14834` has minimum level `83` |
| `LoadFactionNPCOverrides` | Horde NPC `257012` uses Durotar |
| `LoadItems` | Item `264272` is `"Celestial Missive"` |
| `LoadItemOverrides` | Item `22734` drops from NPC `15172` |
| `LoadObjects` | Object `420002` is `"Blood Ritual Altar"` |

Plain Wrath must not contain these Titan-only IDs:

- Quest `93950`
- NPC `257012`
- Item `264272`
- Object `420002`

The Titan persona must read and enumerate each ID, and `Exists` must return true.

### Correction fidelity

Run against the disposable pinned checkout. Require:

- Byte-for-byte comparison for all four Titan files.
- Byte-for-byte comparison for every other manifest file after declared ownership exclusions.
- Every manifest file participates in the fidelity sweep.
- No old WotLK Titan function is expected.

## CI

Keep the current CI preparation:

1. Re-run the mechanical Correction port.
2. Fail on Correction or copied-library drift.
3. Run `generate.lua toc` before flavor Generation.
4. Fail if the committed Source TOC differs.
5. Generate a no-localization Wrath runtime fixture in the unit job.
6. Run mandatory Source and Baked Titan persona assertions.

The Source TOC drift check must remain before ordinary flavor Generation. Flavor Generation also
rewrites the base TOC and would otherwise hide an uncommitted file-list change.

## Documentation

### README

Replace transitional language about accepting both layouts with the permanent rule:

- All four Titan files are required.
- Titan is Dynamic over Wrath.
- Wrath plus season `109` selects the set.
- Quest tags and availability blacklists remain in Questie.
- Re-sync includes `generate.lua toc`.

### CONTEXT.md

The current **Gated Dynamic function** term describes per-function gates and names SoD and Titan.
Replace it with a set-level term such as:

**Gated Dynamic set**: a group of Dynamic Correction functions registered only while its named
runtime condition holds. SoD and Titan Reforged use file-level season gates.

### Current status documents

After validation, update `docs/questie-handover.md` so issue #16 no longer describes Titan's
flavor gate as open. Do not rewrite historical ADR text or `docs/merge-program.md`; those files
record what happened at the time.

## Validation sequence

Set:

```sh
export QUESTIE_PATH="$SYNC_DIR"
```

Run focused checks first:

```sh
git diff --check
lua5.1 test.lua toc
lua5.1 test.lua correction-fidelity
lua5.1 test.lua personas
lua5.1 test.lua lua-types
```

Generate explicit runtime fixtures:

```sh
lua5.1 generate.lua Vanilla Wrath --no-l10n --questie="$SYNC_DIR"
lua5.1 test.lua
```

Remove generated flavor TOCs afterward. A suffixed TOC changes a junctioned addon checkout to
Baked mode.

Then run the full project suite:

```sh
./questietdb all --questie="$SYNC_DIR"
```

Review failures before changing accepted records.

Expected intentional changes may include:

- Wrath Golden changes because Titan-only entities leave plain Wrath.
- Compiler differential changes because Questie also stopped compiling Titan rows into ordinary
  Wrath.
- Validator changes after Titan-only relationships leave the base database.
- Unrelated changes caused by advancing the Questie pin.

Refresh Golden snapshots only after reviewing the public-read changes:

```sh
uv run python tools/differential/golden.py refresh all --lua=lua5.1
```

Update validator or compiler baselines only after classifying each changed row. Never use a
baseline refresh merely to make CI green.

## Review

Use a fresh reviewer after implementation. The review should focus on:

- Titan data absent from plain Wrath.
- Exact Wrath plus season-109 selection.
- All eight providers represented and ordered correctly.
- Source and Baked behavior.
- No Cata or Mists leakage.
- No quest tags, blacklists, or content-phase policy imported.
- Source TOC freshness.
- Correction fidelity.
- Snapshot and baseline review quality.

## Deferred work

Do not add these to the Titan split unless they block validation:

- Long-term Correction authoring ownership, issue #9.
- General Correction registry redesign.
- A Titan quest-tag API.
- A separate Titan artifact.
- Broader side-channel differential coverage.
- Release-cadence decisions.

## Completion criteria

The work is complete when:

- `generator/correction-layout.lua` is gone.
- No legacy/split compatibility branch remains.
- No `LoadTitanReforgedFixes` remains in QuestieTDB.
- No `gatedDynamic` remains.
- Four Titan files are mechanically ported.
- Eight Titan Dynamic providers are declared.
- Titan applies only on Wrath season `109`.
- Plain Wrath has no Titan-only entities.
- Source and Baked representative reads cover all eight providers.
- TBC and MoP content-phase functions remain excluded.
- Correction fidelity runs without skipping.
- The committed Source TOC matches configuration.
- Full validation passes against the new clean pinned Questie checkout.
- Golden and baseline changes were reviewed before refresh.
- `/home/david/private/qu-tdb/questie` was not touched.
