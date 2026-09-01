# `-pi` idea: release transactions and byte-provenance

The merge ported the *shape* of `-pi`'s CI discipline (publication gated on the full
quality bar, a terminal gates job). These pieces were not ported and remain worth
stealing, ranked by recommendation.

## 1. Byte-provenance for copied upstream files — adopt soonest

`-pi` pinned every copied Questie file byte-exact and made drift detectable:

- `.gitattributes` `-text` pinning with per-file whitespace exceptions, each documented
  (`.gitattributes:4`: "Preserve byte-identical Questie provenance; exact intentional
  lines are documented nearby" — two upstream files intentionally end lines in a tab and
  a space, and the exceptions are scoped to exactly those paths).
- `PROVENANCE.tsv` manifests recording source path, byte count, and SHA-256 per copied
  file (`support/PROVENANCE.tsv`, `data/localization/PROVENANCE.tsv`), pinned to a named
  upstream commit.
- A test byte-comparing the copies against the sibling checkout
  (`test/remaining_corrections.lua:146+` — explicit copied-file map, hard-fails on
  drift).

**This repo today:** `QUESTIE_COMMIT` records the global pinned upstream Questie commit, and
the `correction-fidelity` test detects byte drift against that pinned checkout outside
`tools/port-corrections.lua`'s explicitly declared provider/consumer ownership exclusions.
What remains missing from the retired design is finer-grained, per-file provenance: no manifest
records each copied source path, byte count, and SHA-256. Recommended follow-up: emit a
`PROVENANCE.tsv` from `port-corrections.lua` and byte-verify it in CI.

## 2. Draft-transaction publication

`tools/publish_release.py` published as a transaction: create draft → upload exactly N
assets → remotely validate each → verify the tag target commit → publish → never mutate a
published release. GitHub's repository-level **Immutable releases** setting treated as
preflighted external infrastructure — checked via its API before any transaction begins,
never configured by the workflow (`tools/publish_release.py:208-213`).

**This repo today:** `release.yml` gates publication on the quality job and separates the
write token from build code, but `gh release create` is a single non-transactional step.
Adopt the draft→validate→publish sequence if release asset counts grow or partial-upload
failures ever appear.

## 3. Commit-only CI matrices under the platform ceiling

`-pi`'s workflow matrixed per-commit (not commit × target) specifically to stay under
GitHub's 256-jobs-per-matrix platform limit, with an explicit guard
(`.github/workflows/ci-release.yml:93-96`: "GitHub permits at most 256 jobs in one
matrix; split this push"). Only relevant if this repo ever builds per-commit prereleases
for every commit in a push. File under "known ceiling, known dodge."

## 4. Bootstrap verify-backup-rollback

`bootstrap.sh` verified the checksum file's exact shape before touching anything
(`bootstrap.sh:149-156`: exactly five SHA256SUMS lines, exactly one entry per asset),
backed up all prior installed state, and rolled back on partial failure; PowerShell twin
with the same contract. **This repo's** `tools/bootstrap.{sh,ps1}` verify checksums but
are lighter on backup/rollback — worth porting the prior-state backup if bootstrap
becomes a contributor-facing daily tool.

Status: **follow-ups** — item 1 recommended now; 2 and 4 on growth triggers; 3 is a
reference note.
