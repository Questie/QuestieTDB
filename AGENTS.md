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

## LuaLS declaration maintenance

Treat `src/types/*.t.lua` as part of the public API. Update the declarations in the same
change when any of these contracts change:

- an entity field is added, removed, or renamed, or its value shape or nilability changes —
  update `General.t.lua` and the affected entity declaration;
- a public global, property, function signature, return type, overload, or dot-call/method-call
  convention changes — update the affected entity declaration or `LibQuestieDB.t.lua`;
- a public structured value changes, including IDs, coordinates, spawn maps, objectives, or
  Correction entries and callbacks — update its shared alias in `General.t.lua`;
- the exported Correction API changes — update both `General.t.lua` and
  `LibQuestieDB.t.lua`;
- type packaging paths or the shipped declaration set changes — update `tools/package.sh`,
  the LuaLS tests, and the consumer documentation together.

Internal refactors that preserve these contracts do not require a type change. Keep declarations
out of TOCs; WoW must never load them. Add or strengthen `src/types/consumer.test.lua` when a
signature, overload, or structured type needs semantic coverage, then run:

```sh
lua5.1 test.lua lua-types
lua-language-server --check=src/types --checklevel=Warning --check_format=pretty
```

## Agent skills

### Issue tracker

Issues, specs, and Wayfinder maps live in GitHub Issues at `Questie/QuestieTDB`, via the `gh` CLI. This repository configuration overrides Wayfinder's default local Markdown tracker. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using the default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
