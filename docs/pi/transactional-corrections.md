# `-pi` idea: transactional correction lifecycle

`-pi` built substantially more lifecycle machinery around corrections than this repo
carries. None of it was ported — this repo's simpler registry, hardened by the merge
program's fixes (position-stable owner rank, uniform `{}` delete, composed enumeration),
covers today's single-consumer reality — since ADR 0009 with data-shaped slots, per-datatype
recomposition scope, and memoized materialization, still far short of `-pi`'s transactional
machinery. Recorded here because the mechanisms become
relevant the day third-party correction authors exist at scale.

## Two-phase transactional Dynamic apply

`-pi` applied an owner in two phases inside `xpcall`: materialize → compose a candidate →
diff against the published view → freeze → only then commit and invalidate
(`src/corrections/overlay.lua:397+` — candidate compose, per-entity diff into
`changedIds`, then publication). No fallible step could leave a half-applied view.

- **This repo instead:** recompose rebuilds layers in place; a throwing materializer can
  abort mid-recomposition. Source mode contains the blast radius by pcall-ing init and
  never publishing; at runtime a broken consumer materializer is the consumer's bug.
- **Prevents:** a half-composed view visible to readers after a mid-apply error.
- **Adopt when:** ownerless apply spans multiple third-party owners whose code this repo
  cannot vet — one broken stranger must not poison the composed view.

## The transactional candidate view

`-pi` materializers received a view of the candidate being built, so a correction could
read entities **added by earlier corrections in the same pass**
(`src/corrections/overlay.lua:131-140`: "Materializers see the candidate built by earlier
same-owner registrations, never the old published layer"). This repo's correction
functions see only globals; ordering-dependent inference between corrections in one pass
is not expressible.

- **Adopt when:** a correction needs to derive from another correction's output in the
  same apply (the `required_races.lua` inference pass was `-pi`'s consumer of this — and
  note its defect in the ledger: inference that cannot distinguish "unset" from an
  authored zero-clear).

## Static sealing state machine

`-pi` sealed static registration after source init published — a late `ApplyStatic`
failed loudly (`src/corrections/registry_core.lua:199`:
*"Static Correction application is sealed after Source initialization and in Baked
mode"*). This repo relies on the manifest being the only static registrar.

- **Adopt when:** the static path gains any public or semi-public entry point.

## Entity-existence sub-model

`-pi` made existence explicit at registration: `addEntities` / `establishEmptyRows`
options (`registry_core.lua:53-58`) with a deliberate asymmetry — an authored field
establishes an unknown ID, a *pure empty row* requires an explicit missing-entity
registration (`registry_core.lua:247-254`). This repo's composed enumeration (ADR 0003
D7) covers the read side; the write side accepts whatever a correction returns.

- **Prevents:** a typo'd entity ID silently creating a ghost row.
- **Adopt when:** correction authorship opens up and ghost-row bugs appear.

## Caution

`-pi`'s own review found real bugs *inside* this machinery: registrations for
uninstalled entity types silently dropped forever (revision advanced anyway, guard assert
unreachable), the "nothing changed" identity fast path was dead code, and a failing debug
reporter aborted the whole apply. Rigor is not free — each mechanism needs its own
negative tests, or it is ceremony with new failure modes.

Status: **deferred** — trigger is third-party correction authors, not time.
