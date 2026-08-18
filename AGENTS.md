# QuestieTDB Agent Notes

The database Questie consumes. Stores entity data as WoW addon TOC metadata and owns the
offline generator that produces it.

This repo is **implemented**: the generator, both runtime modes, corrections,
localization, validators, CI, and release tooling all exist. `DESIGN.md` describes the
architecture as designed; where it and the code disagree, read the ADRs in `docs/adr/` —
`0003-merged-storage-and-read-contract.md` is the most recent contract statement.

## Read first

- `DESIGN.md` — architecture, locked decisions, rejected alternatives, phasing
- `CONTEXT.md` — glossary
- `docs/storage-format.md` — the on-disk TOC contract and nil/empty rules
- `docs/adr/` — decision records
- `docs/table.freeze.md` — live-client research on `table.freeze` / `table.isfrozen`

## Agent skills

### Issue tracker

Issues live in GitHub Issues at `Questie/QuestieTDB`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using the default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
