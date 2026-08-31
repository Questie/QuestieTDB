# Review findings — 24 Aug 2026

Scope: `76ba81a..370303c`, seven commits.

| Commit | Subject |
|---|---|
| `029c716` | fix(corrections): preserve Questie correction semantics |
| `83e6378` | fix(validators): preserve finding ownership in baselines |
| `0624484` | ci: pin Questie and align release quality gates |
| `ee74e57` | fix(build): validate pinned generation inputs |
| `612e56d` | docs: document pinned generation workflow |
| `282805d` | fix(validators): reject incomplete baseline refreshes |
| `370303c` | docs(differential): clarify Questie pin validation |

Questie pin under review: `a6e04c4b2efe31b791792a097b314469840b55f6`.

Method: eleven parallel reviewers on separate lenses, plus direct verification. Claims below
are marked VERIFIED where someone executed the check, INFERRED where they read the code and
reasoned. Ground truth for upstream came from `gh api repos/Questie/Questie/contents/<path>?ref=<pin>`.

## Verdict

The substance is good. The corrections re-sync is faithful to upstream and measurably improved
the database against the one independent oracle. Two real defects rode in on it, and several
gates report green more readily than they should.

Not ready for `master` as it stands — mostly for merge-policy reasons rather than code quality.

---

## Blockers

### B1 — `LoadContentPhaseFixes` is never registered, and the resulting defect was marked permanent

`src/corrections/manifest.lua:19` · VERIFIED · found independently by two reviewers

The manifest declares `dynamic = {'LoadFactionFixes'}` for `Tbc/tbcQuestFixes.lua`. Upstream
applies `LoadContentPhaseFixes` as a Quest override at `QuestieCorrections.lua:139`, inside the
same `Expansions.Current >= Expansions.Tbc` block as the faction fixes. The function is ported
and present at `src/corrections/Tbc/tbcQuestFixes.lua:8819`. It is simply never wired up.

It is an oversight, not a policy decision: manifest lines 31, 32 and 34 do declare
`LoadContentPhaseFixes` for the three MoP entries. It is also the only public function added
anywhere in this commit's re-copy — the other three surface changes are removals, all handled
correctly.

Impact on a TBC client with `ContentPhases.activePhases.TBC < 3`:

| Quest | Correct | QuestieTDB serves |
|---|---|---|
| 10944 "The Secret Compromised" | `preQuestGroup={10901,11052}` | `preQuestSingle={10708,11052}` |
| 11007 "Kael'thas and the Verdant Sphere" | `preQuestSingle={10888}` | nil |

The SSC and Tempest Keep attunement chains are wrong. At phase 3+ and on Wrath onward the
function's `or` branch reproduces base data, so impact is confined to TBC at phases 1–2.

The differential caught this. `tools/differential/compiler-baseline/TBC.tsv:12-13` gained
exactly `Quest preQuestGroup EMPTY_VS_ABSENT 1` and `Quest preQuestSingle EMPTY_VS_ABSENT 2` —
matching the function's three field writes over those two quests, on the one flavor where it
acts. Both rows were recorded as `POLICY`. `write_baseline` stamps new rows `UNTRIAGED`, so
`POLICY` was entered by hand, and `compiler_diff.py:283-295` prints POLICY as permanent and
excludes it from the "divergences still owed" total. That file's own header reads: "This is a
to-do list, not an approval. Only POLICY rows are permanent."

Fix needs more than a manifest line. The function reads `ContentPhases.activePhases.TBC`, and
the compat shim's auto-created module has no `activePhases`; registering as-is throws
`attempt to index field 'activePhases' (a nil value)` inside `recompose` (VERIFIED). Needs a
`ContentPhases` stand-in in `src/corrections/compat.lua`, plus a decision on whether to gate it
like TitanReforged or parameterise it like Darkmoon. Note `MopQuestFixes:LoadContentPhaseFixes`
returns `{}`, so the three registered MoP content-phase functions have never exercised this path.

Cheap gate that would have caught it: after copying, diff each file's top-level
`function <Module>[:.]<Name>` definitions against the union of that entry's
static/dynamic/parameterized lists, skipping `_Module:` privates, and fail on an unclassified
public function. Across all 29 ported files that finds exactly one hit — this one.

### B2 — `git bisect` is broken across the largest change of the day

`tools/port-corrections.lua:471` vs `generator/lib.lua:251` · VERIFIED

`port-corrections.lua` calls `lib.assertQuestiePin` from `029c716`, but `generator/lib.lua` does
not define it until `ee74e57`, three commits later.

```
029c716  port-corrections calls: 1   lib defines: 0
83e6378  port-corrections calls: 1   lib defines: 0
0624484  port-corrections calls: 1   lib defines: 0
ee74e57  port-corrections calls: 1   lib defines: 1
```

At the first three commits the tool dies with `attempt to call field 'assertQuestiePin' (a nil
value)`. CI's "Fail on correction drift" step (`ci.yml:45`, `release.yml:56`) is red at three of
seven commits, and any `git bisect` probe landing in `029c716..0624484` returns "bad" for an
unrelated reason — across the window holding the single largest data change of the day.

Fix: land the function definition with its first caller.

### B3 — No branch protection exists

`.github/workflows/ci.yml:3-4`, `:192-198` · VERIFIED

`gh api repos/Questie/QuestieTDB/branches/master/protection` returns 404 "Branch not protected";
`rulesets` is `[]`. Meanwhile `ci.yml:3-4` states the terminal `gates` job "makes every matrix
and unit result mandatory for branch protection" and `:195-197` says "branch protection requires
exactly this one status."

The `gates` job itself is correctly built — `if: always()` plus explicit per-need result checks,
so a skipped or cancelled dependency cannot read as green. It is wired to a policy that does not
exist. Red CI blocks neither merge nor direct push to `master`, and a push to `master` triggers
`release.yml`. Publication stays safe because `needs: [quality, differential]` re-runs the bar,
so this is merge hygiene rather than a ship-broken-database path.

Relevant context: `docs/merge-program.md`'s retirement checklist opens with "Merge this branch;
push first — A and B share the `Questie/QuestieTDB` remote with divergent histories, and
first-to-push owns the truth."

### B4 — The provenance stamp never consults the pin

`generator/lib.lua:270`, `generate.lua:286`, `generate.lua:317` · VERIFIED

`lib.assertQuestiePin` ends `return actual`, returning the validated commit. All six callers
discard it: `generate.lua:292`, `generate.lua:319`, `reconstruct.lua:69`,
`port-corrections.lua:471`, `check.sh:74`, `compiler_diff.py:93`.

Separately, `generate.lua:286` computes `questieCommit = lib.gitCommit(...)` — a different
function with no notion of the pin — before any validation runs, and `generate.lua:146` stamps
that into the artifact.

One fact, two independent code paths: one validates and throws away its answer, one records and
never validates. Both provenance holes below are consequences.

**B4a — `--no-l10n` skips the pin check entirely.** `generate.lua:317` nests `assertQuestiePin`
inside `if not opts.noL10n`, while the stamp at `:286` is unconditional.
`generate.lua Vanilla --no-l10n --questie=<any other git repo>` exits 0 and writes a false
`X-QUESTIE-COMMIT` (VERIFIED). `tools/package.sh:81-86` only checks the five artifacts agree
with each other, never against `QUESTIE_COMMIT`, so five such artifacts package cleanly and
`release.json` publishes the wrong commit. Reconstruct cannot catch it: `X-QUESTIE-COMMIT` is in
`HEADER_KEYS` (`reconstruct.lua:147`) and excluded from comparison. The comment directly above
the check claims `--no-l10n` exists "so an incorrect checkout cannot look successful"; it is the
exact escape hatch that makes one look successful.

Scope limit: `--no-l10n` appears in no workflow, no `check.sh` path and no release step — only
in `generate.lua`'s arg parser and a `test.lua:1627` skip branch. Manual-invocation hazard, not
reachable from CI.

**B4b — A dirty checkout at the correct SHA passes every gate.** Nothing anywhere checks whether
the Questie checkout is dirty; there is no `git status --porcelain` in `generator/lib.lua`,
`generate.lua`, `compiler_diff.py` or `tools/package.sh`. VERIFIED end to end: a reviewer
checked out Questie at the pin, then edited
`Localization/lookups/Classic/lookupQuests/deDE.lua` so it stayed valid Lua but held one quest
instead of 4257 — what a bad merge or truncated rebase produces.

```
assertQuestiePin        -> true, a6e04c4b...
assertInputs            -> true
generate.lua --quiet    -> EXIT 0, stamped X-QUESTIE-COMMIT: a6e04c4b...
verify.lua Vanilla      -> PASS exit 0 ("18000 segments resolved across 9 locales")
reconstruct.lua Vanilla -> PASS, 0 mismatches, exit 0
```

4,256 of 4,257 German quest names lost, in an artifact asserting reviewed provenance.
`stats.locales` still reports 9, so even the weak log signal does not fire. A zero-byte lookup
file gives the same silent outcome by a different route.

Commit `370303c` removed the phrase "dirty-input policy" from `compiler_diff.py`'s docstring
rather than implementing the check. Honest, and CI is unaffected (fresh checkout), but if
neither an ADR nor the check lands, the only record that anyone considered dirty trees is a
deleted comment.

Fix for the whole class: make the stamp be the validation's return value —
`BUILD.questieCommit = lib.assertQuestiePin(questiePath)`. Then a stamp cannot exist without a
passing check, and there is exactly one place to add a dirty-tree check.

---

## High

### H1 — `validators/run.lua --self-check` is invoked by nothing

`validators/run.lua:442`, `tools/check.sh:272`, `ci.yml:123`, `release.yml:99` · VERIFIED

`83e6378` added a self-check. All three call sites run `validators/run.lua <flavor>` bare. Both
sibling gates pass the flag at all six of their call sites (`check.sh:277,282`, `ci.yml:132,190`,
`release.yml:105,149`).

Mutation testing broke the baseline comparator two ways and both passed every shipping gate:

| Mutation | Effect |
|---|---|
| `run.lua:234` `return true` -> `return false` | no baseline regression is ever reported; exits 0 |
| `run.lua:225` drop the decrement | multiset becomes a set; a finding recurring 40x against a baseline of 5 is accepted; exits 0 |

`test.lua` has zero validator tests. `83e6378`'s claim is proven by nothing that runs. Cheapest
fix in the repo: add `--self-check` to those three lines.

Related: `validateFlavor` returns `#regressions + errored`, so `fixed` never fails a run — a
fingerprinting regression reports "0 findings, 1473 fixed" and exits 0.

### H2 — Stale baseline entries never fail, and this already happened

`validators/run.lua:412-415,439` · VERIFIED

A baselined finding that stops firing is counted as `fixed`, which is advisory and feeds neither
`status` nor the return value. Appending one bogus line to `Wrath.txt` yields
`[PASS] Wrath: ... (7 baselined, 0 new, 1 fixed)`, exit 0. Suppression is total: adding a
fingerprint to the baseline makes it vanish from output entirely, not even as a note. Under
`--quiet` the only signal disappears too.

This is not hypothetical. `validators/baseline/*.txt` were written 2026-07-28 (`2a4cb29`) and
untouched until `83e6378` — 27 days. Reconstructing that state from a pristine `76ba81a`
archive running its own committed `run.lua` against its own committed baselines:

```
[PASS] Vanilla: 0 findings    (0 baselined,  0 new,   0 fixed)
[PASS] TBC:     1 findings  (112 baselined,  0 new, 111 fixed)
[FAIL] Wrath:   6 findings   (94 baselined,  1 new,  89 fixed)
[FAIL] Cata:  280 findings  (316 baselined, 16 new,  52 fixed)
[FAIL] Mists: 1498 findings (1528 baselined, 61 new,  91 fixed)
```

TBC read `[PASS]` while 111 of its 112 accepted findings had rotted away.

1+16+61 = 78 new; 89+52+91 = 232 removed — both of `docs/validator-baseline-review.md`'s
headline numbers reproduce to the unit, but they describe the tree *before* the corrections
re-sync. So `83e6378` is also a month-late baseline refresh that absorbed 27 days of drift, and
the doc reads as though the re-sync caused the churn.

### H3 — No gate covers any non-default persona

`tools/differential/dump_a.lua:4-5`, `golden.py`, `compiler_diff.py` · VERIFIED

Every oracle runs one persona: Alliance / Human / Warrior / no active season. `compiler_diff.py`
supports `--season=SoD` but no CI job or `check.sh` gate passes it. There are exactly five
golden, five compiler-baseline and five validator-baseline files.

`029c716` changed 816 lines across the four `Sod/` files and the WotLK Titan Reforged sets.
Measured ungated surface:

| Persona | Entities | Values |
|---|---|---|
| Vanilla Horde | 109 | 121 |
| Vanilla SoD | 10,956 | 125,199 field lines (+31% over the gated default) |
| Wrath TitanReforged | 40 | 113 |

All eight SoD manifest entries are `dynamic`, so they never enter a baked artifact, but they are
live on a SoD client. `test.lua` and `equivalence.lua` cover the plumbing but compare QuestieTDB
to itself. A corrupted `sodQuestFixes` re-sync leaves all three gates green on all five flavors.

Time-to-discovery for a defect in these personas is a user bug report after release, measured in
weeks, and expensive to diagnose because both QuestieTDB modes agree with each other.

### H4 — `check.sh test` is exempt from the pin preflight and self-skips to green

`tools/check.sh:67-69`, `test.lua:193,933-936` · VERIFIED

`needs_questie` lists only `generate|determinism|reconstruct|differential`. `test.lua:24` reads
`QUESTIE_PATH`; `:935` and the reconstruct-control suite skip when no checkout exists; `:193`
asserts the pin only `if gitCommit ~= 40 zeros`.

`tools/check.sh test` with no `../Questie` gives `PASS test  759 checks, 0 failed`, exit 0,
while `.out/checks/test.log` holds `SKIP correction-fidelity: no Questie checkout` and
`SKIP reconstruct-control: no pinned Questie checkout`. Neither SKIP reaches the summary. The
one suite comparing corrections against Questie reports green having never run — in the commit
titled "validate pinned generation inputs".

Under `all` the preflight fires because `generate` is in the set; this is specific to the
standalone gate. Without a checkout, 93 checks including all of `correction-fidelity` vanish and
the suite prints PASS.

### H5 — `check.sh all` is not every gate, and discards a preceding gate

`tools/check.sh:55` · VERIFIED

```
all)  GATES=(generate verify equivalence reconstruct validators differential golden test) ;;
```

It assigns rather than appends, and omits `determinism` and `freeze`. `tools/check.sh
determinism all` never runs determinism, never lists it in the summary, prints "all stages
passed", exit 0. Reversing the words does produce a determinism phase. Both `check.sh:23` and
`README.md:76` document `all` as "every gate".

### H6 — Workflow permissions and script injection

`.github/workflows/*.yml` · VERIFIED

No `permissions:` block on any build job; only `publish` has one (`release.yml:155-156`).
`gh api repos/Questie/QuestieTDB/actions/permissions/workflow` returns
`{"default_workflow_permissions":"write","can_approve_pull_request_reviews":true}`. Every job
that executes upstream Questie code — `port-corrections.lua:471` evaluates Questie's correction
files via `setfenv`/`chunk()`, `compiler_diff.py` runs Questie's compiler — inherits a
read/write token that can also approve PRs, and `actions/checkout@v4` defaults
`persist-credentials: true`.

`release.yml:171,174` interpolate `${{ inputs.tag }}` and `${{ inputs.release }}` straight into
the `run:` block of the only `contents: write` job, contradicting the header claim at
`release.yml:7-9` that the token-bearing job runs no build code. Fix: `env:` indirection plus
`"$TAG"`.

No `pull_request_target` anywhere, and no `${{ github.event.* }}` reaches a `run:` block.

Fix: `permissions: contents: read` at the top of both workflows, `persist-credentials: false` on
build checkouts.

---

## Medium

### M1 — Unpadded decimal escapes silently corrupt strings

`generator/serialize.lua:72,78` · VERIFIED

```
"a\0".."5b"   -> quoted 'a\05b'  -> decodes "ab"     CORRUPT
"a\1".."23b"  -> quoted 'a\123b' -> decodes "a{b"    CORRUPT
"a\10".."b"   -> quoted 'a\nb'   -> round-trips OK
```

Named escapes are safe; only the `format("\\%d", byte)` fallback and the `["\0"]="\\0"` entry
are broken. Fix: `format("\\%03d", byte(char))` and repad the `\0` case.

No committed data triggers it, and `verify.lua`'s decode-and-compare would fail the build for
entity fields. But `docs/storage-format.md`'s localization section rests on the claim that "list
elements need no stripping because the quoted literal form escapes them" — exactly what this
breaks — and l10n lookups come from the Questie checkout, not this repo. `constants.lua`,
`manifest.lua` and `generator/schema.lua` have no round-trip gate at all.

### M2 — `register.lua:150` inheritance propagation is untested, and the consequence is real

`src/corrections/register.lua:150` · VERIFIED by executing the mutation

Deleting `or spec.minExpansionOrder` leaves `entry.sourceExpansionOrder` nil for every
expansion-gated entry, so `registry.lua:301` returns early, `entry.options` is nil, no
`noNewEntries` applies, and `MergeInto` creates freely.

Measured: **Mists +51 quests, Cata +1 item and +2 object fields.** `Tbc/tbcQuestFixes.lua:Load`
supplies quests 253, 504, 510, 511, absent from Mists base data and carrying no field-1 name, so
upstream refuses them and unmutated QuestieTDB refuses them too.

No test catches it. `test.lua:594-596` checks the manifest spec, unchanged by the mutation;
`test.lua:670-691` sets `sourceExpansionOrder` by hand on synthetic entries. Nothing asserts on a
registry entry built from a real manifest spec. One assertion inside the existing manifest loop
closes it.

### M3 — Published bytes are not the bytes the gates read

`tools/package.sh:70,113`, `release.yml:8-9,108-110` · VERIFIED

`strip-static.lua` rewrites the staged correction files to remove Static function bodies, in the
last step before upload, after every gate. Every gate reads `src/corrections/` in the working
tree, which `strip-static.lua:12-14` documents it never touches.

Substantially mitigated: `strip-static.lua:16-27` implements its own layered verification —
exactly-once function match, `loadstring` compile check, every Dynamic/Parameterized function
still defined, full behavioural parity of returned tables and captured direct writes — and
aborts packaging on failure. But `release.yml:8-9`'s claim that everything uploaded "came
through those gates, unmodified" is literally false, and no gate reads the shipped zip.

Otherwise the publish path is clean: `publish` is a fresh checkout plus `download-artifact`,
runs no build code, v4 artifacts are immutable within a run, and `package.sh:24` stamps
`producerCommit` from the quality job's `git rev-parse HEAD`.

### M4 — `docs/api.md:304` contradicts today's own correction

VERIFIED

The consumer-facing API doc still says a translated `objectivesText` keeps "the base field's
exact table shape — element counts never differ per locale". `612e56d` corrected exactly that
claim in `docs/storage-format.md:190`, which now reads "Element counts follow the upstream
lookup and may differ, notably where zhCN or zhTW combines objectives."

Measured in the shipped artifact: of Vanilla quests whose `objectivesText` fits one unchunked
line, 8 have two non-empty locales disagreeing; quests 203, 438 and 792 hold 3 elements in seven
locales and 1 in zhCN/zhTW. A consumer indexing by position on that promise breaks.

Same dead claim in code comments at `equivalence.lua:22,313-314` and `generator/l10n.lua:70-71`.
Already corrected in ADR 0003 and `DESIGN.md:483`.

### M5 — The drift gate is blind to upstream additions

`ci.yml:46`, `release.yml:57`, `tools/port-corrections.lua:380-382,411-423` · VERIFIED

`git diff --exit-code` reports modifications to tracked files only and returns 0 for untracked
files. `port-corrections.lua` iterates a hardcoded `FILES` table rather than enumerating
Questie's Corrections directory. A pin bump to a commit that adds
`Database/Corrections/Cata/cataNewFixes.lua` produces no file, no diff, green gate.

Census against the pinned tree: 62 upstream `.lua` files under `Database/Corrections`, 31
declared. All 31 undeclared are legitimately excluded per DESIGN.md policy (blacklists,
`Holidays/`, `ContentPhases/`, `SeasonOfDiscovery.lua`, `QuestieCorrections.lua`, `.test.lua`).
The exclusion list is correct today — and that is the point: "not declared" already means both
"policy, deliberately Questie's" and "not yet noticed", and the gate cannot tell them apart.

`ee74e57` made removals loud (`copyDeclaredSource` errors on a missing declared source) and left
additions silent. `README.md:129-131` now tells reviewers to bump the pin and review the
re-port — a diff structurally incapable of showing a new upstream corrections file.

Fix: a declared *exclusion* list; fail the port on any `Database/Corrections/*.lua` in neither
list.

### M6 — `validator-baseline-review.md` omits TBC entirely and mislabels Wrath

`docs/validator-baseline-review.md:20` · VERIFIED against upstream blacklists, evaluated not grepped

The doc scopes itself to "Wrath, Cata and Mists". True as written, but that silently drops 111
of the 343 removals. TBC's ledger went 112 -> 1, a 99% collapse, with no written justification.
Of the 63 quests involved, 62 are not blacklisted for TBC and all 63 are still present — playable
data, not consumer policy.

The catch-all "most remaining relation changes involved blacklisted quests and were policy churn
rather than changes to playable data" covers ~165 of the 232 with no numbers. Per flavor:

| Flavor | Relation removals | Distinct quests | Blacklisted upstream |
|---|---:|---:|---|
| Cata | 44 | 36 | 36 / 36 |
| Mists | 83 | 75 | 75 / 75 |
| Wrath | 81 | 45 | **5 / 45** |

Cata and Mists match the description exactly. Wrath does not: 40 of 45 are non-blacklisted and
all 40 are still in the database, so those relations genuinely changed.

192 accepted findings on playable TBC and Wrath data disappeared unreviewed or mislabelled. No
regression — the entities survive, so silently-dropped rows are ruled out. What cannot be ruled
out is which NPC-side relation changed, because the old ownerless format does not say. That
limitation is the strongest argument for `83e6378` that the doc does not make.

Everything else in the doc reproduces exactly: 78, 232, 43, 27, 2, 6, 24, 39, 103, 101, 90, 96.
90/90 quests behind the new Mists relations are fully blacklisted for MoP; quest 2359 is
blacklisted for Cata and MoP; item 7923 is `Expansions.Current >= Expansions.Cata`; 43/43 phantom
quests are blacklisted and absent from raw Mists.

### M7 — `--types` values are never validated, making the new l10n preflight vacuous

`generate.lua:50-52`, `generator/l10n.lua:90` · VERIFIED

Flavor names are validated (`generate.lua:308-310` errors on an unknown flavor); type names are
not. `--types=Quets` populates `typeFilter` with a key nothing matches, so every
`typeFilter[typeName]` is nil, the loop body never runs, `#missing == 0`, and `assertInputs`
returns having verified zero paths. Generation then emits a six-line header-only artifact and
exits 0. `--types=` (empty) does the same.

Knock-on: a typo'd `--types` in the CI invocation makes `l10n.IsAvailable()` false, 27 checks
vanish silently via `test.lua:1627`, and CI stays green. Nothing anywhere asserts the
CI-generated artifact actually contains localization.

### M8 — An l10n content fault leaves a large partial artifact that `verify.lua` passes

`generate.lua:252-268` · VERIFIED twice

The l10n append reopens the TOC in `"ab"`; `l10n.join` can `error()` mid-append with no cleanup.
Triggered with a control char in a German quest name and again with a syntactically broken lookup
file: generation exits 1 (correct) but leaves a 12.9 MB `QuestieTDB_Vanilla.toc` with complete
entity data and zero l10n lines, and `verify.lua Vanilla` then passes with exit 0. Only
reconstruct catches it. `generate.lua:315`'s comment ("must fail before either TOC is opened")
holds for missing files, not content faults. Fix: temp file plus rename, or `os.remove` on failure.

### M9 — Round-trip asymmetry: reconstruct kept the guard generate deleted

`reconstruct.lua:122` · VERIFIED

`ee74e57` added `assertQuestiePin` to reconstruct (`:69`) but not `assertInputs`, and left the
skip-silently directory guard that `generate.lua` removed. The two halves of the gate now
disagree about what a valid input tree is.

With `lookups/Classic` removed, generate hard-fails with a precise file list; reconstruct emits
an l10n-free `expected` and reports 44,859 mismatches with `expected: nil`, pointing the operator
at the artifact when the fault is their local tree. Worse: if only some of the 36 files are
missing, reconstruct silently drops those locales and passes against an artifact that lost the
same locales.

`reconstruct.lua` also has no `--no-l10n`, so a `--no-l10n` artifact can never be reconstructed.

### M10 — `package.sh` skips a missing TOC and exits 0

`tools/package.sh:56-59` · VERIFIED

`if [ ! -f "$TOC" ]; then echo "... skipping" >&2; continue; fi`. `if-no-files-found: error`
(`release.yml:118`) only checks that *some* file exists.

Add a sixth flavor to `src/config.lua`: `generate.lua all` emits six TOCs, package.sh's hardcoded
`FLAVORS=(Vanilla TBC Wrath Cata Mists)` packages five, `entries` lands on exactly 5, the `-eq 5`
branch at `:102` fires, and the combined zip is built and shipped labelled flavor `"All"` while
silently missing the new flavor. `release.yml` hardcodes the same five names in five places.

Pairs with `ci.yml:146-151`, which omits `if-no-files-found` and so defaults to `warn`.

### M11 — Compiler baselines carry no provenance stamp

`tools/differential/compiler-baseline/*.tsv` · VERIFIED

`golden/*.tsv:3` stamps the worktree; the compiler baselines stamp nothing. The old and new
counts were in fact measured against different upstream revisions. "696 -> 693" is not
self-evidencing: a real +5 regression inside a class that also improved by 8 reads as SHRANK,
i.e. as good news. Writing `QUESTIE_COMMIT` into the baseline header closes it.

Both golden snapshots are stamped `+dirty`, so neither is reproducible from a commit.

### M12 — `--season=SoD` scores against the wrong baseline

`tools/differential/compiler_diff.py:98-110` · VERIFIED

The season is passed to the compiler dump only; `dump_a.lua` takes no season argument and
`baseline_path()` ignores it. The usage in the script's own docstring (`:17`) compares
SoD-Questie against non-SoD-QuestieTDB and scores it against the plain Vanilla baseline.
`--season=SoD --update-baseline` would overwrite `compiler-baseline/Vanilla.tsv` with thousands
of bogus `ID_ONLY_IN_COMPILER` counts, destroying the plain Vanilla gate in a diff that looks
like a routine refresh.

### M13 — No ADR for the pinning decision, and the pin value was chosen by default

`docs/adr/` · VERIFIED

`docs/adr/` holds only 0001–0005, all dated 2026-08-20. Nothing added today.
`docs/storage-format.md` previously read "an artifact is reproducible only from the *pair* of
commits"; it now says generation rejects a different commit. That is a new contract statement
plus a standing obligation on every bump.

The pin's value was not decided: `a6e04c4b` is exactly `Questie/Questie@master` as of
2026-08-24 02:04 UTC. Issue #8 (`ready-for-human`) asks three questions; today answered where the
pin lives and the bump procedure, and answered "pin to what?" by fiat, while
`docs/questie-handover.md` declares #8 resolved.

The ADR should carry the residual as a stated limitation: the pin binds the commit, not the
working tree; CI is clean by construction; local builds are trusted.

### M14 — Issue tracker untouched

VERIFIED

All 12 issues still read `created=2026-08-19 updated=2026-08-19`, zero new comments; nothing
created, commented, labelled or closed. Today materially resolved #2, #4, #7 and #8.
`docs/questie-handover.md` now carries a private ledger declaring them resolved, prefaced by
"This ledger records the implementation status even when the corresponding GitHub issue has not
yet been closed", which institutionalises the divergence.

Concrete costs: #2's reproduction steps name `LoadMissingQuests` and `src/corrections/compat.lua`,
which no longer describe the tree; #4's "Reproduce" block no longer reproduces; #8 sits
`ready-for-human` asking a question the code already answered.

Also unfiled: `docs/validator-baseline-review.md` identifies three real upstream defects (NPC
3061 missing quest 27021 in `questStarts`; NPC 7406 missing 25476 in `questEnds`; NPC 7944
missing 29477 in `questEnds`) and says they "should be fixed upstream and then removed here by
re-porting". No upstream issue exists and nothing tracks it.

### M15 — Documentation accuracy

VERIFIED

| Location | Issue |
|---|---|
| `docs/questie-handover.md:54-56` | Predicts five divergence classes "should disappear on the next re-sync". The re-sync is `029c716`; none of the five survives. Should be past-tense fact. |
| `docs/questie-handover.md:50-52` | Cites baseline `requiredRaces` 49; the recorded Vanilla baseline is now 43, stated 45 lines above at `:27` and `:98`. |
| `docs/questie-handover.md:90-91` | Legend defines `FIX` and `UNTRIAGED`; this commit removed the last row using either. `OPEN`, used in three rows, is undefined. |
| `docs/questie-handover.md:98`, `docs/adr/0004-derived-passes.md:103` | Reference `TASK-derived-requiredRaces.md`, which does not exist. |
| `docs/questie-handover.md:23-25` | Rewrite dropped the measurement date; "from the Questie commit in QUESTIE_COMMIT" silently re-points when the pin moves. |
| `README.md:26-27` | "if the checkout or required lookup files do not match" — lookup files are checked for existence, not matched. |
| `README.md:123` vs `ci.yml:34` | README documents `generate.lua meta --questie=../Questie`; both workflows use positional `generate.lua meta ../Questie`. |
| `README.md:118` | "Two things derive from Questie" undercounts; CI also diffs `src/derived/RamerDouglasPeucker.lua`. |
| `README.md:60-79` | Five documented invocations now hard-fail without a checkout at the pin; only `compiler_diff.py` is flagged as needing one. |
| `README.md:171-183`, `AGENTS.md` | `docs/validator-baseline-review.md` is indexed nowhere. |
| `docs/storage-format.md:222-223` | Sentence broken mid-line; edit artifact. |

Negative result: no doc anywhere instructs a manual Questie clone, describes pre-`029c716`
semantics as intended, describes the old validator fingerprint format, claims l10n is optional
when the checkout is absent, or uses a superseded command name.

---

## Low and latent

| ID | Location | Finding |
|---|---|---|
| L1 | `src/corrections/manifest.lua:43`, `register.lua:145` | `itemStartFixes` applies FIRST among Item statics; upstream applies it LAST (`QuestieCorrections.lua:317`). Measured 0 divergences today; wrong by construction. |
| L2 | `registry.lua:300-311` | `Shared/itemStartFixes` gets a stricter `noNewEntries` than upstream, which always carries the `data[1] ~= nil` exception. Latent: all 452 current rows carry only `itemKeys.startQuest`. |
| L3 | `registry.lua:266-273` | `MergeInto` creates an entity for an empty correction row; upstream's create check sits inside the `pairs(data)` loop so `[id] = {}` is a no-op. Real data has such rows (Cata 2, Mists 4), all already in base data. |
| L4 | `register.lua:211-243` | `ApplyParameterized` applies BOTH Darkmoon variants; upstream picks exactly one, with different arities. Measured byte-identical today. |
| L5 | `registry.lua:382`, `src/read/shared.lua:162-178` | An all-dropped overlay row still makes an entity exist; `recompose` bounds `fieldIndex` above but not below. No current data triggers it. |
| L6 | `registry.lua:327,366` | `entry.func()` is called without `pcall` in both apply paths; one throwing third-party function takes down `ApplyRegisteredCorrections` and leaves the stale overlay installed. |
| L7 | `generator/runtime.lua:96` | `FromManifest`'s `skipped` return is discarded, so a manifest entry whose module no longer resolves registers nothing and Generation reports success. |
| L8 | `generator/serialize.lua:45-53` | `inf`/`nan` do not round-trip: `1/0` -> `"inf"` -> `loadstring` returns nil. Unreachable from Questie data. |
| L9 | `generator/lib.lua:258` | A 40-zero `QUESTIE_COMMIT` passes the regex, and `gitCommit` returns 40 zeros on git failure, so on a git-less machine it validates ANY path. `test.lua:206` uses 40 zeros as its "wrong commit" fixture and `test.lua:255` accepts it as valid — the suite treats it as both. |
| L10 | `generator/lib.lua:266` | `assertQuestiePin(nil)` crashes with an internal `bad argument #1 to 'format'` rather than a clear error. |
| L11 | `generator/l10n.lua:128,135` | `stats.missingFiles` is accumulated and never read; the only in-band record that extraction skipped a file. |
| L12 | `tools/check.sh:135-148,167` | `reap_one` returning 1 spins forever; silently requires bash >= 5.1 (`wait -n -p`) and >= 4.0 (`local -A`). Reproduced: 200,001 iterations, no progress, 100% CPU. CI is bash 5.2, unaffected. |
| L13 | `tools/check.sh:288-293` | An empty job list reports success: `check.sh verify --flavors=` and `check.sh freeze --flavors=Cata` both exit 0 having run nothing. |
| L14 | `tools/check.sh:91,95,156` | A non-numeric `--budget-mb` disables the budget instead of rejecting it; `--budget-mb=abc` started all 5 jobs at once. |
| L15 | `tools/check.sh:160` | No cleanup trap; SIGINT to `check.sh all` orphans up to 26 lua/python processes at ~1.7 GB each. |
| L16 | `tools/check.sh:74` | The pin preflight surfaces as a raw Lua traceback with a `lua5.1:` prefix, making the repo's front-door failure look like a crash. Fix: wrap in `pcall`, write to stderr, `os.exit(1)`. |
| L17 | `tools/check.sh:92,235` | `sha256sum` is GNU-only with no fallback, so the determinism gate cannot run on macOS. |
| L18 | `tools/check.sh:102-104` | `printf '%q'` breaks a multi-word `--lua`; `--lua="lua5.1 -W"` exits 127. Paths with spaces now work correctly, which is a genuine improvement. |
| L19 | `compiler_diff.py:259-262` | A flavor with no recorded baseline and an empty dump exits 0 with "No baseline recorded". `--self-check` closes it and all three automated callers pass it. |
| L20 | `compiler_diff.py:113-123` | `load()` silently drops malformed lines with no counter, understating the "compared" total. |
| L21 | `validators/run.lua:149-153` | A display name with an unbalanced `(` defeats `%b()` and leaks the whole name into the fingerprint. Exactly one such name exists: NPC 43040 "Tock Sprysprocket (Goggles". |
| L22 | `validators/run.lua:416-418` | `%d baselined` prints the baseline file's line count, not the number actually matched. |
| L23 | `validators/run.lua:314,375` | `--raw --update-baseline` silently replaces the ledger with uncorrected findings and exits 0 (Wrath: 6 lines -> 393). |
| L24 | `validators/checks.lua:236-251` etc. | Baseline key content is `pairs()`-order dependent for three last-writer-wins checks. A descending-key iterator flipped 9 fingerprints and turned `[PASS]` into `[FAIL]`. Pre-existing, not introduced here, but the new guard is structurally blind to it. |
| L25 | `test.lua:296` | The phase-ordering assertion is vacuous: it runs `check.sh --sequential`, where the concurrency hazard the phase split exists to prevent is impossible by construction. |
| L26 | `test.lua:966` | `equal(compared, #manifest)` is self-referential; both sides shrink together. |
| L27 | `test.lua:234-256` | `workflow-contracts` is five YAML substring matches — a change-detector that catches deletion, not semantic breakage. Reformatting `needs: [quality, differential]` to a block sequence turns it red. Asserts nothing about `ci.yml`. |
| L28 | none | No `concurrency:` on either workflow. Nothing can cancel a publish mid-flight today; two overlapping dispatched releases could leave `latest` pointing at the older build. |
| L29 | `release.yml:161-178` | `publish` does not re-verify the checksums it publishes, though `release.json` carries per-artifact SHA-256. |
| L30 | `leafo/gh-actions-lua@v13.0.0`, `leafo/gh-actions-luarocks@v6.1.0` | Floating tags rather than commit SHAs, newly added to the release path in the commit whose theme is pinning inputs. `luarocks install bit32` is now a hard availability dependency on the publish path. |
| L31 | CI vs release | CI reconstructs two flavors, release reconstructs five; CI never exercises the combined-zip path (`package.sh:102`) that the release depends on. Both asymmetries run release-stricter-than-CI, so CI green does not imply releasable. |
| L32 | `QuestieTDB.toc` | A committed, generated, fully deterministic file with no drift gate, unlike `src/meta/` and `src/corrections/`. CI overwrites it before any reader and never compares. |
| L33 | pin ancestry | `actions/checkout` can fetch a SHA that exists only in a fork or unmerged PR; nothing checks the pin is an ancestor of upstream's default branch. `git merge-base --is-ancestor` closes it. |
| L34 | `README.md:61` | A direct `lua5.1 generate.lua` is not byte-reproducible unless the caller sets `SOURCE_DATE_EPOCH`. Every automated path pins it (`ci.yml:15`, `release.yml:31`, `check.sh:45`); the documented manual form does not. |

---

## Verified clean

Negative results worth recording, so they are not re-investigated.

**Corrections fidelity.** All 30 ported correction files are byte-identical by SHA-256 to
`Questie/Questie@a6e04c4b`. Re-running `port-corrections.lua` and `generate.lua meta` against the
pinned checkout produces zero diff against the committed tree. `port-corrections.lua` performs no
transformation on correction data — `lib.copyFile` is a binary read plus binary write.

**Generated constants.** `src/corrections/enum/constants.lua` is generated by extraction, so
byte-comparison does not apply. Deep-compared against upstream `Database/questDB.lua` at the pin:

```
questKeys    upstream= 36  generated= 36  IDENTICAL
questFlags   upstream= 15  generated= 15  IDENTICAL
factionIDs   upstream=130  generated=130  IDENTICAL
```

`factionIDs` is the table that changed in `029c716`.

**Determinism.** Three consecutive generations byte-identical with CI's
`SOURCE_DATE_EPOCH=1700000000`, across `--quiet` and non-`--quiet` invocations: 35,944 entities,
238,395 fields, 24.3 MB. The only nondeterministic byte in the artifact is `X-BUILD-TIME`.

**The independent oracle moved the right way on every flavor.**

| Divergences vs Questie's compiler | Vanilla | TBC | Wrath | Cata | Mists |
|---|---:|---:|---:|---:|---:|
| before | 49 | 84 | 429 | 872 | 514 |
| after | 43 | 76 | 401 | 776 | 417 |

`Quest.questFlags` (72 rows) and `Quest.reputationReward` eliminated entirely. Totals 1948 ->
1713; non-POLICY debt 1828 -> 1590.

**Static apply order.** Replaying upstream's full static sequence — `_LoadCorrections`, its
`Expansions.Current > Expansions.<X>` `noNewEntries` ladder, and the direct-write path that
bypasses it — against `registry.ApplyStaticToEntities` over the real data: zero divergence,
entity set and every field, 5 flavors x 4 datatypes. Self-proof: clearing `sourceExpansionOrder`
reintroduces 4 Cata divergences; swapping `LoadAutomatics`/`Load` back reintroduces 20.

**The two semantic changes in `029c716` are both correct.**
`static = {'LoadMissingQuests','Load'}` -> `{'Load'}` is faithful: upstream deleted the function,
and all 12 quest ids it created (5640, 5678, 7668-7670, 65593, 65597, 65601-65604, 65610) are
present in the re-synced file. `static = {'Load','LoadAutomatics'}` ->
`{'LoadAutomatics','Load'}` matches upstream `QuestieCorrections.lua:285-286`; the old order was
the defect.

**Manifest vs upstream call order at the reviewed pre-split pin** — every entry matched except
the two recorded above (B1, L1). The now-retired per-function Titan gate covered exactly the
three WotLK files upstream guarded with `Questie.IsTitanReforged` (quest/npc/item, not object).
SoD ordering was correct. `parameterized LoadDarkmoonFixes` was called nowhere in
`QuestieCorrections.lua`, so "never applied automatically" was right.

**The removed direction of the validator churn is clean.** `validators/checks.lua` was not
touched by any of the seven commits, so the 264 removed findings cannot be a blinded checker.
Relation invariants reconstructed independently of `validators/` for both TDB and Questie's own
compiled DB:

```
TBC   questStarts  missing=2   unbacked=45   absent-refs=702   IDENTICAL
TBC   questEnds    missing=0   unbacked=0    absent-refs=370   IDENTICAL
Wrath questStarts  missing=2   unbacked=58   absent-refs=875   IDENTICAL
Wrath questEnds    missing=0   unbacked=26   absent-refs=460   IDENTICAL
Cata  questStarts  missing=99  unbacked=244  absent-refs=1115  IDENTICAL
Cata  questEnds    missing=74  unbacked=43   absent-refs=746   IDENTICAL
```

TDB's relation data is exactly as consistent as Questie's own, on every count, in both
directions.

**The added direction of the validator churn is honest.** Of the newly accepted rows, Cata 13 of
16 and Mists 75 of 78 reference quests on Questie's active blacklist; the only three not
blacklisted are exactly the three the doc names as real upstream defects (27021, 25476, 29477).

**The pin is real, not vacuous.** `assertQuestiePin` compares `git -C <path> rev-parse HEAD`
against `QUESTIE_COMMIT` and fails closed:

| Input | Result |
|---|---|
| wrong commit, complete tree | REJECT, names the actual SHA |
| no `.git` anywhere above | REJECT (`gitCommit` -> 40 zeros) |
| path is a regular file | REJECT |
| empty string as path | REJECT |
| path containing `; echo PWNED` | REJECT, no shell execution (`shellQuote`, `lib.lua:226`) |
| dirty tree, correct SHA | ACCEPT — see B4b |

`compiler_diff.py`'s `run()` propagates the subprocess exit, so its pin check is not decorative.
`package.sh:83-88` adds a second layer refusing to write a manifest whose artifacts disagree on
`X-QUESTIE-COMMIT`.

**`tools/check.sh` failure propagation is sound.** `RESULT[$label]` defaults to 1, so an
unrecorded job is FAIL by construction. Run against zero artifacts: exit 1, 4 FAIL / 2 PASS. A
failing generate job stops phases 2 and 3. No `continue-on-error` or `|| true` anywhere in
`.github/`. No `local x=$(cmd)` masking. The memory budget is never a divisor, so no
divide-by-zero exists; degenerate budgets degrade to sequential, never to zero workers.

**An empty or unparseable differential dump fails rather than reporting "no differences"** —
every baselined row becomes RESOLVED. The only hole is L19.

**`validators/run.lua` fails closed** on: a check throwing (`pcall` at `:336` records the error
and exits 1), an absent baseline file, a CRLF baseline, `--quiet` on a failing run, unknown
flavor or flag, and a check that prints findings but forgets `Validators.failed`. No accidental
O(n^2); all five flavors, 1,744 findings, 3.5s.

**`83e6378`'s parse fidelity is the strongest part of that commit.** `fingerprintCountError` is a
real assertion: deleting `npc` from `ENTITY_TYPE` produces a hard ERROR and exit 1. On real data
it fires zero times across all five flavors, so every structured finding survives into a
fingerprint. Baseline regeneration is idempotent and reproduces the committed files byte-for-byte.

**`validators/baseline/Vanilla.txt` not changing is expected.** It is a single `\n` byte, zero
findings, since creation. A format change over an empty set is a no-op. Consequence: the Vanilla
leg exercises the baseline path with an empty multiset, so it is not a canary for baseline logic.

**l10n nil/empty semantics are right.** Control chars are stripped before ASCII trimming (correct
order); a whitespace-only translation collapses to nil and the reader falls back to base English.
List elements deliberately skip stripping because `serialize.quote` escapes control characters.
Line budget respected: max line exactly 1023 bytes, 0 over, 2,667 chunked values round-tripped.

**Serializer round-trip fuzz** passes on: `false` scalar and inside sparse arrays, nil holes,
negative and fractional keys, negative zero, 2^53, quantized coords, empty string, both quote
chars, backslash, newline/CR/tab, UTF-8, DEL, depth 31, 20k arrays, mixed array/hash. Key
ordering is sorted, so output is deterministic.

**Test wiring is sound.** `test.lua` is the `test` gate at `check.sh:265`, is in the `all` list,
and runs at `ci.yml:63` and `release.yml:78`. The CI unit-test job checks out Questie at the pin,
so `correction-fidelity` and `reconstruct-control` do run on every PR. The gaps are in what the
tests assert, not whether they run. No assertion-free tests among the 295 new lines; no ordering
dependence found.

**Mutation testing: 37 injected bugs, 19 caught, 18 missed.** Caught includes all five semantic
corrections mutations. The NPC 30208 behavioural test at `test.lua:746-754` catches the WotLK
load-order flip independently of the manifest literal, and is the strongest test in the commit.
Missed includes every call-site deletion: removing `assertQuestiePin` from `generate.lua:319`,
`reconstruct.lua:69` or `check.sh:73` passes 855 checks. The new validators are tested as units;
nothing asserts that any caller calls them.

**`282805d` fixes a genuine HIGH defect introduced in `83e6378`.** As committed,
`--update-baseline` returned before computing `errored`, so a check that threw wrote a truncated
baseline and exited 0. Reproduced at `612e56d`: baseline 263 -> 189 lines, exit 0, no ERROR
printed. Fixed at `370303c`: `[FAIL] ... baseline not updated because 1 checks produced invalid
evidence`, exit 1, baseline untouched. Severity nuance: the damage is loss of reviewed judgment,
not an undetected data regression — the comparison path fails loudly in both post-truncation
states.

---

## Commit hygiene

All seven subjects, five with no body. Unrecoverable from the repo alone: why `LoadMissingQuests`
left the manifest (upstream deleted it — nothing says so, and issue #2 still cites it as a live
lead); why the WotLK static order flipped; why three new `POLICY` rows appeared in
`compiler-baseline/TBC.tsv` (which is B1).

`029c716` bundles a mechanical re-port, three deliberate semantic changes, and the re-recording of
both oracle baselines under a message-less subject. The re-port half is verifiable by re-running
the tool; the semantic half is not.

`docs/validator-baseline-review.md` landing in the same commit as the change it explains is the
right pattern and the model to follow.

The day is coherent as a set: re-port at the pin -> validator ledger reconciled to the new data ->
CI reads the pin -> offline tools enforce it -> docs -> fix -> honest doc correction. Dependency
order is right and nothing unrelated is smuggled in.

**On the 11-minute defect.** `0624484` moved the Determinism check to run before any reader, so
"every later gate approves the exact second-generation bytes whose hash matched the first
Generation" — the identical validate-before-you-commit-to-an-output principle that
`validators/run.lua --update-baseline` violated, applied correctly to the artifact pipeline
eleven minutes earlier. When the right principle is demonstrably held and inconsistently applied,
the fix is a review checklist rather than more coverage. A greppable rule: compute every
refuse-to-proceed condition before any branch that can leave the function.

Also worth noting: `--update-baseline` has zero coverage anywhere. `83e6378` added a self-proof
(`selfCheckFingerprints`) and stopped one function short of the only path that mutates the trust
anchor.

---

## Frozen mirror re-frozen in the same commit

`tools/differential/golden/*.tsv` (580 added / 673 removed) and `compiler-baseline/*.tsv` are both
re-recorded inside `029c716`. CONTEXT.md defines the golden snapshot as "the frozen mirror that
catches defects where generator and source mode agree with each other while both diverge from
upstream". All five gates pass at HEAD with self-checks, which proves consistency, not
correctness. Mitigated by the compiler differential moving downward and by the byte-identity
check, but after any later change "was this right before?" is answerable only from git history,
not from a live gate.

The only golden additions anywhere are Quests 95158/95251/95252 (arena rating resets), present in
upstream `tbcQuestFixes.lua` at the pin and in the compiler dump. Legitimate. The 99 removed
Mists entities, 5 Cata and 1 Wrath are phantom rows the compiler never had; removing them is a
fix.

---

## Not verified

- **CI has never run.** `gh api repos/Questie/QuestieTDB/actions/runs --jq .total_count` returns
  0. The local composite-action reference, the `github.action_path` traversal, the brace
  expansion at `release.yml:71`, and the two `leafo/*` actions on the release path have never
  executed on GitHub. The first push to `master` fires CI and Release at once.
- **`compiler_diff.py` could not run locally** (no `bit32` for `lua5.1`), so divergence counts
  come from the committed baselines and the handover reconciliation.
- **The handover's total-comparison figures** (397,395 / 659,210 / 980,653 / 1,588,480 /
  1,982,795) and the attribution sentences at `questie-handover.md:27-31` were not reproduced.

---

## Recommended order of work

1. Register `LoadContentPhaseFixes` (`manifest.lua:19`), add the `ContentPhases` shim to
   `compat.lua`, and retract the three hand-typed `POLICY` rows in `compiler-baseline/TBC.tsv`. (B1)
2. Add `--self-check` to the three `validators/run.lua` call sites. One word, three lines. (H1)
3. Move the `assertQuestiePin` definition into `029c716` so bisect works. (B2)
4. Enable branch protection on `master`, which `ci.yml` already assumes exists. (B3)
5. `BUILD.questieCommit = lib.assertQuestiePin(questiePath)` — closes B4a and B4b at their single
   root cause, and gives the dirty-tree check one place to live. (B4)
6. Then, in any order: `check.sh all` (H5), `permissions:` blocks and `env:` indirection (H6),
   `docs/api.md:304` (M4), the declared-exclusion list (M5), the TBC/Wrath baseline
   classification (M6), and the pin ADR (M13).
