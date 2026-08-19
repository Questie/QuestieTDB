# The `-pi` sibling — harvest and defect ledger

`Questie-toc-pi/QuestieTDB` was an independent implementation of the same locked spec this
repo implements, built in parallel from the shared fork point. During the merge program it
served as the cross-implementation differential oracle (`tools/differential/`) — the role
that caught four real defects in this tree that its own gates were structurally blind to.
After acceptance it retires to the workspace's gitignored `.retired/`; the source paths
cited in this directory refer to that retired checkout.

Everything worth adopting was ported during the merge (verification methodology,
corrections-over-l10n precedence, table-valued l10n, 40.90 coordinate quantization, the
persona emulator, CI gating patterns). This directory preserves what was **not** adopted:

| File | What it holds |
| --- | --- |
| [`self-describing-artifact.md`](./self-describing-artifact.md) | In-band schema manifests — rejected with re-adoption conditions |
| [`transactional-corrections.md`](./transactional-corrections.md) | Correction lifecycle rigor — deferred until third-party authors exist |
| [`release-and-provenance.md`](./release-and-provenance.md) | Release transactions and byte-provenance — partial follow-ups |
| [`consumer-tooling.md`](./consumer-tooling.md) | Type stub, validator fixtures, TOC test fixtures |

## Defect ledger

Recorded so nobody trusts `-pi`'s artifacts or resurrects its code uncritically. None of
these need fixing — the tree is retired — and the differential verified this repo is
correct on every point below.

1. **Value-only chunk budget — its artifacts are corrupt on real clients.**
   `src/generation/toc.lua:3` caps the *value* at 1,000 bytes and ignores the key, so
   ~33k artifact lines exceed the client's measured 1,023-byte line limit (max observed
   1,027) and `GetAddOnMetadata` silently truncates them. Its own verifier cannot see
   this: `verification.lua:305-308` checks `#line.value` against the same constant.
   Never install a `-pi`-generated TOC in a client.
2. **Static `requiredRaces` inference stomps authored zero-clears.**
   `src/corrections/static/era/required_races.lua:17-18` treats `requiredRaces == 0` as
   "unset" and re-infers a faction mask from questgivers, so upstream's deliberate
   `raceIDs.NONE` clears on the AQ war-effort quests read back as 178/77 (Era) and
   1101/690 (Wrath) — observed as 7 Vanilla and 344 Wrath divergences against this
   repo's upstream-faithful reads.
3. **`LoadAutomatics` entities lose spawns in its composed Wrath view** (20 divergences,
   e.g. npc 28136: present in its `static/` tree, spawns absent from its composed read;
   upstream applies `LoadAutomatics` ungated and this repo matches upstream).
4. **Latent newline guard asymmetry.** `generate.lua:153-157` asserts no `[\r\n]` only
   for `storage == "string"` fields; table-nested strings go through Lua 5.1
   `string.format("%q")`, which emits a backslash + literal LF — a newline inside nested
   text would split a directive into a stray TOC content line. Latent, not live, in its
   artifacts at retirement.
5. **Hot-path allocation on every read.** `src/read/shared.lua:118-119` calls
   `overlay:GetProvenance` per read, and `src/corrections/overlay.lua:517-518` builds its
   assert message by eager concatenation — one string allocated per public read,
   including cache hits.

Status: **ledger** — reference only, nothing to do.
