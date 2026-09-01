# The merge program — 2026-08-18/19

The record of how two parallel implementations of this design became one. Written while
the working context was still live, so the knowledge survives it. Companion documents:
[`adr/0003-merged-storage-and-read-contract.md`](./adr/0003-merged-storage-and-read-contract.md)
(the contract), [`client-metadata-probes.md`](./client-metadata-probes.md) (the
measurements), [`pi/`](./pi/README.md) (what the sibling contributed and its defect
ledger).

## What happened

Two independent implementations of the same locked spec existed: this tree ("A",
`Questie-toc`) and a sibling ("B", `Questie-toc-pi`), forked from one commit and built
through the same 17 tickets separately. A comparative review found their strengths nearly
disjoint — A owned the wire format and the only live-client evidence; B owned lifecycle
rigor and verification depth — and their artifacts non-equivalent on contracts the spec
had never decided.

Decision: **A is the base; B is the donor; B retires after acceptance.** The deciding
arguments: A's unforked-corrections layout avoids a permanent upstream-sync tax, B's
verification suite needed rebuilding against A's wire format under either base, and B's
self-describing artifact matters little while reader and data ship in one addon
(`pi/self-describing-artifact.md` records when that changes).

## How it ran

Live-client probes came first because the logged-in client was the perishable resource —
and they immediately converted the review's sharpest *suspected* risk into a *proven*
shipped bug (edge-whitespace trimming corrupting Russian text through the public getter).
ADR 0003 then locked every contract the two trees had answered differently, and the
implementation ran as sequenced worker passes over disjoint file sets, each independently
verified and committed:

| Pass | Landed |
| --- | --- |
| Probes | Client behavior measured: trimming, key case-folding, truncation boundary, `table.freeze` taint ownership, read-path costs |
| Wire | Trim-safe chunking, case-folded key uniqueness, 40.90 coordinate quantization, shortest round-trip spelling, table-valued l10n segments |
| Runtime | Fresh-per-read producers, corrections-over-l10n, existence gating, composed enumeration, season gating, the parameterized API later retired by ADR 0007, packed `GetAll`, ranged contract |
| CI | Publication gated on the full quality bar; terminal gates job |
| Harness | B's verification methodology rebuilt: widened self-proving equivalence, byte-exact reconstruction gate, persona emulator, allocation guards |
| Differential | Cross-implementation read-value comparison vs B — the acceptance instrument |
| Correction gating | Era-manifest fix, per-expansion constants, per-function Titan Reforged gate — each exposed by the previous differential collapse |
| Review + fixes | Fresh-eyes adversarial review; precedence stability, uniform `{}` delete, `GetByIndex` parity, baked-mode recompose flavor |
| Harvest | A-vs-golden gate replacing the B oracle; `docs/pi/` idea and defect record |

The Wire row records what landed during this historical program. ADR 0006 later superseded
production coordinate quantization: QuestieTDB now stores raw coordinates, and a tool-only
Compiler comparison adapter reproduces the old grid while that migration oracle remains.

## Defects found and fixed in this tree

Every one was invisible to the tree's own pre-existing gates:

1. **l10n chunk-boundary corruption** — the client trims edge whitespace; ~351 Vanilla
   chunk parts lost a byte on reassembly (proven live end-to-end on quest 10 ruRU, and
   proven fixed live after regeneration).
2. **Era fix files Classic-gated** — upstream applies them on every expansion; TBC+
   artifacts were missing all Era-inherited statics (~8,451 TBC divergences, 39 missing
   entities). Invisible to verify/equivalence because generator and source mode shared the
   same wrong manifest.
3. **Era-frozen constants** — expansion-dependent race masks/npcFlags/ALL_CLASSES
   extracted once at Era values (440 TBC divergences).
4. **Titan Reforged sets ungated on plain Wrath** (92 divergences; season-109 gate,
   per-function).
5. **Owner re-apply hoisted precedence** — `ApplyParameterized` moved QuestieTDB's whole
   dynamic layer above consumer corrections; rank is now fixed at first apply.
6. **`{}` delete idiom corrupted scalar fields** through the dynamic overlay; now uniform
   delete, with author-error reporting for non-empty tables on scalar fields.
7. Edge-contract batch: `GetAll`+`unpack` data loss (now packed with `n`), `GetRaw` and
   `GetByIndex` mode parity, `RequireContract` equality→range, `InvalidateCache` case
   sensitivity, `Get(nil)` cache crash, unknown-id numeric-zero phantoms.

Defect classes 2–4 share a shape worth remembering: **consistently wrong on both sides of
the seam** — generator and source mode agreeing with each other while both diverge from
upstream. Only comparison against an independent implementation (or a frozen golden)
catches it; that is why the golden gate now runs per flavor in CI.

## The design reversal worth remembering

ADR 0003 D10 originally mandated frozen shared values. Live measurement overturned it
twice: `table.freeze` is taint-ownership-gated (decoder tables belong to the force-taint
context — the validated in-chunk workaround is preserved in the probes doc), and then
benchmarks showed **re-executing a cached compiled chunk returns a fresh mutable deep copy
at 0.13–1.8 µs** — at cache-hit cost for typical shapes, and *exactly* the per-call
semantics Questie's ~290 call sites were compiled against. Fresh-per-read eliminated the
frozen-value contract, the consumer mutation audit, and the taint problem in one move.
`C_EncodingUtil.DeserializeCBOR` measured within ~15% and `CopyTable` 4–5× slower; CBOR as
a storage format was rejected for artifact diffability.

## Standing guarantees after the program

- 729 offline checks; five-flavor verify; widened equivalence with a sensitivity
  self-proof; byte-exact reconstruction (CI, Vanilla+Mists); A-vs-golden composed-read
  gate with self-check (CI, all flavors); release publication structurally blocked on red.
- Live-validated on Classic Era 1.15.9 build 69109 in baked mode: the ADR contract
  exercised end-to-end, including the ruRU fix, fresh-per-read isolation, and
  corrections-over-l10n with honest provenance (`client-metadata-probes.md` §7b).
- Differential vs B fully explained on Vanilla/TBC/Wrath: remaining divergences are the
  documented nested-zero storage decision plus B's own ledgered bugs.

## Future work — ready to file as issues once the branch is pushed

File with `gh issue create` per `agents/issue-tracker.md`; drafts here so nothing is lost:

1. **Adopt byte-provenance discipline for copied upstream files.** PROVENANCE.tsv
   (path, bytes, SHA-256, upstream commit) emitted by `tools/port-corrections.lua`, CI
   byte-verify. The adopt-soonest item in `pi/release-and-provenance.md`.
2. **Fresh LuaLS consumer type stub** for the *current* API (packed `GetAll`,
   owner-scoped Corrections, ranged `RequireContract`). Written new — never ported from B
   (`pi/consumer-tooling.md`).
3. **Mists-scale in-client acceptance.** Raw-coordinate storage reduced the Mists artifact
   from 117,410,435 to 102,430,533 bytes (97.7 MiB), still above the 85 MB live-tested range.
   One session on a Mists client: load time, `GetAddOnMetadata` behavior, memory. Extend the
   live battery to one non-enUS locale there too.
4. **`*Pointers` semantics audit** (DESIGN open risk 2): confirm the ~22 Questie sites
   only test existence/iterate, making `GetAllIds(true)` a drop-in.
5. **Per-validator positive+negative fixtures** (B's pattern, `pi/consumer-tooling.md`)
   on top of the committed baselines.
6. **File the upstream zhTW DEL-byte issue** — ready-to-file text sits at the workspace
   root (`UPSTREAM-ISSUE-zhTW-del-byte.md`); QuestieTDB already sanitizes at extraction.
7. **Trailing-tab / CRLF client probes** — the two micro-gaps the synthetic battery
   couldn't cover in one TOC (`tools/probe-addon/README.md`); the conservative splitter
   makes them non-blocking.
8. **Questie integration phases** — DESIGN.md's phasing 5–13 (backend flag in Questie,
   compiled/TOC differential golden before compiler removal, seam cutover). The next
   large program.
9. **Release pipeline completion** — CurseForge publication, bundled/nolib packaging
   (DESIGN packaging section; B's draft-transaction pattern in
   `pi/release-and-provenance.md`).
10. **Explicit owner re-rank API** — only if a consumer ever legitimately needs to change
    correction precedence after first apply (WS11 design note; deliberately undesigned).

## Retirement checklist for the sibling

1. Merge this branch; **push first** — A and B share the `Questie/QuestieTDB` remote with
   divergent histories, and first-to-push owns the truth.
2. Move `Questie-toc-pi` to the workspace's gitignored `.retired/`.
3. Nothing in this repo references the live B checkout — the golden gate replaced the
   differential oracle (`tools/differential/dump_b.lua` stays as the historical record).

## Meta-lessons

- **Live probes before design.** Three "known" behaviors were wrong or incomplete until
  measured (trimming, key case-folding, freeze ownership) — and one measurement
  (chunk-exec cost) reversed a locked architectural decision for the better.
- **Byte-measure, don't char-measure.** An `awk length()` census under a UTF-8 locale
  undercounted the sibling's over-limit lines 3× ; the byte-accurate census changed the
  finding's severity class. Measure wire formats in bytes, always.
- **Independent implementations are the only mirror for shared-seam bugs.** Four real
  defects here produced identical wrong answers from generator and source mode alike.
  The golden gate is that mirror, frozen.
- **Verification must prove its own sensitivity.** Every gate added in this program can
  demonstrate that it fails when it should (self-proofs, negative controls) — a gate that
  cannot fail is decoration.
