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
- `docs/adr/` — decision records; `0003` is the current contract
- `docs/merge-program.md` — how the two parallel implementations became one: defects
  fixed, standing guarantees, ready-to-file future work, retirement checklist
- `docs/client-metadata-probes.md` — measured live-client behavior (trimming, key
  case-folding, the 1,023-byte line limit, freeze ownership, read-path costs)
- `docs/read-performance.md` — what a read costs and why, measured against the `Getters`
  prototype and Questie's compiler; the cost model behind the caching design
- `docs/table.freeze.md` — live-client research on `table.freeze` / `table.isfrozen`
- `docs/pi/` — the retired `-pi` sibling: unadopted design ideas and its defect ledger

## Agent skills

### Issue tracker

Issues live in GitHub Issues at `Questie/QuestieTDB`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using the default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
