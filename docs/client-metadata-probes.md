# Live-client metadata probes — 2026-08-18

Measurements taken against a running client through WoWDevBridge. Recorded so they are not
repeated, in the same spirit as [`table.freeze.md`](./table.freeze.md).

**Client:** Classic Era 1.15.9, build 69109 (Aug 3 2026), enUS, interface 11509.
**Artifact under test:** the installed `QuestieTDB_Vanilla.toc`, baked mode, producer
`0f540d3` (the dirty-worktree snapshot whose line-safe output matches `b5ca4bd`).
Probes read the artifact through both raw `C_AddOns.GetAddOnMetadata` and the public
`LibQuestieDB` getters.

## 1. The client trims edge whitespace from metadata values — CONFIRMED

The highest-stakes open question from the comparative review, now measured:

| Key | Bytes on disk | Bytes returned | Lost |
| --- | ---: | ---: | --- |
| `X-l10n-Quest-10-2-1` (ends `"seine "`) | 998 | **997** | trailing space |
| `X-l10n-Quest-237-2-2` (starts `" пехотинец"`) | 480 | **479** | leading space |

Chunk headers (`~2~`) and interior bytes return intact. Consequence: every chunk part that
begins or ends with whitespace loses those bytes during reassembly. The Vanilla artifact
carries ~351 such parts, all `X-l10n-Quest-` keys.

**Proven end-to-end**, not just at the raw layer: with `SetLocale("ruRU")`,
`Quest.Get(10, "objectivesText")[1]` returns `"Узнайте, чтостало…"` — the space at the
part-1/part-2 boundary is missing from the composed public read. (`"что стало"` is absent,
`"чтостало"` is present.)

**Required fix:** `splitValue` must never end or begin a part with trimmable bytes, and
`verify.lua` must scan every emitted part for edge whitespace alongside its line-length scan.

## 2. Metadata keys are case-insensitive — new fact

`x-l10n-quest-10-2`, `X-L10N-QUEST-10-2`, and the canonical spelling all return the same
value. Key identity in the client is case-folded.

**Required fix:** generation must assert case-insensitive uniqueness across every emitted
key. (No current collision exists — `X-l10n-Quest-…` and `X-Quest-…` differ by more than
case — but nothing enforces it.)

## 3. `table.freeze` refusal root cause — and a validated fix

`table.freeze` and `table.isfrozen` exist on this build. Freezing is gated on **taint
ownership**, and the runtime's captured failure explains all 38 refusals observed during
the probe session:

    attempted to freeze a table not owned by the calling function
    (expected 'QuestieTDB', got '*** ForceTaint_Strong ***')

Chunks compiled by `loadstring` execute force-tainted, so every table the Baked decoder
creates is owned by the taint context — addon-owned code can never freeze them. This is
why `docs/table.freeze.md` measured 0 frozen / all refused in Baked mode.

**Fix validated live:** a `loadstring` chunk that deep-freezes the tables it creates
succeeds completely — root, nested children, all `isfrozen == true`, writes error. The
decoder controls the chunk text it compiles, so wrapping the payload

    local v = <payload> ; <deep-freeze v> ; return v

restores the frozen-value guarantee in Baked mode with no storage-format change. Probed
result on a nested `{1, {2, {3}}, s = "x"}`: `rootFrozen`, `childFrozen`, `grandFrozen`,
`writeBlocked` all true.

Probe-time state of the current runtime: 0 of 38 table values returned by the public
getters were frozen; all accepted writes; `shared.freezeRefused` counted each refusal.

**Implementation refinement, also probed:** the ownership check is on the *calling
function*, so the deep-freeze helper must not be ordinary addon-owned code — but a helper
**itself compiled once via `loadstring`** shares the force-taint owner and successfully
deep-froze tables produced by a *separately compiled* payload chunk (root and nested
children all `isfrozen`). Production shape: compile one shared helper at init, call
`helper(value)` after each decode. Two simplifications follow from the wider freeze
research (`table.freeze.md`): decoded Lua literals are trees by construction — no aliasing
or cycles are expressible in literal syntax — so the decode-path helper needs no
visited-set; and because a frozen table with `__newindex` redirects writes instead of
erroring, tables composed by the Correction Overlay must be verified metatable-free
before freezing (decoded literals are plain by construction).

## 4. Marker discipline in-client

- `~E~` decodes correctly through the full runtime: `Npc.Get(15672, 1)` returns a true
  empty string. First live exercise of this path.
- `~Q~` remains unexercised — zero instances exist in any artifact. A synthetic-TOC probe
  is still wanted (see §7).
- Missing key returns `nil` (`X-Does-Not-Exist`).

## 5. Line-length boundary, safe side re-validated

The artifact's longest line — `X-Quest-IDS-LIST-10`, 1,023 bytes total, 999-byte value —
returns all 999 bytes intact on build 69109. The unsafe side (lines over 1,023) cannot be
probed against this artifact because generation now keeps every line at or under the
limit; the original measurement stands (`generator/lib.lua:17-28`), and a synthetic-TOC
probe would re-establish the exact boundary on current builds.

## 6. Read-path cost and heap growth (Vanilla, 4,257 quests)

| Measurement | Result |
| --- | ---: |
| Cached read (`Get(10, "objectivesText")` × 20,000) | 4.93 ms (~0.25 µs/read) |
| First-touch decode, `name`, all 4,257 quests | 15.6 ms (~3.7 µs each) |
| First-touch decode, `startedBy` (table), all quests | 38.6 ms (~9 µs each) |
| Re-read `name` sweep, cached | 1.58 ms |
| Heap growth for the two full-field sweeps | ~4.1 MB |

The unbounded decoded cache is real but bounded in practice: a consumer sweeping a handful
of fields across every quest costs tens of MB at Mists scale, not hundreds. A budget
decision, not an emergency.

## 6b. Copy-mechanism benchmarks — `C_EncodingUtil` CBOR vs cached chunks vs `CopyTable`

`C_EncodingUtil` exists on Era (`SerializeCBOR`, `DeserializeCBOR`, JSON, Base64, Hex,
`CompressString`). `DeserializeCBOR` returns a genuinely fresh deep copy (fresh identity
at every level; mutating the copy leaves the source untouched) with exact double
round-trip, UTF-8 and empty-string fidelity. Timed with `GetTimePreciseSec`, 10–20k
iterations, per-op µs:

| Shape | cached-chunk exec | DeserializeCBOR | CopyTable | loadstring+exec |
| --- | ---: | ---: | ---: | ---: |
| `{2787}` | **0.13** | 0.42 | 0.61 | — |
| `{5, 3, 7}` | **0.26** | 0.68 | 1.63 | — |
| 6 coordinate pairs | **1.70** | 1.80 | 8.72 | — |
| 64-pair spawn table | **19.2** | 20.7 | 91.4 | 86.4 |

One-time costs for the 64-pair table: `SerializeCBOR` 10.9 µs, Base64 decode 3.5 µs,
base64→CBOR chain 23.5 µs. Sizes: CBOR 1,241 B, base64(CBOR) 1,656 B, Lua literal
2,685 B.

Consequences (ADR 0003 Decision 10, revised): re-executing an already-compiled literal
chunk produces a fresh mutable deep copy at or near decoded-cache-hit cost for typical
field shapes, which voids DESIGN.md's stated reason for rejecting fresh-per-read values
and retires the frozen-shared-value contract for reads. `CopyTable` is 4–5× slower than
either native path at every size. CBOR-as-storage is rejected for artifact diffability.

## 7. Synthetic-TOC probes — MEASURED (TDBProbe addon, build 69109)

The deferred battery ran via `tools/probe-addon/` after a full client restart:

| Directive | Line bytes | Returned |
| --- | ---: | --- |
| `X-P-L1023` (value 1,009 B, tail `01234567`) | 1,023 | **1,009 B intact**, tail `01234567` |
| `X-P-L1024` (value 1,010 B) | 1,024 | 1,009 B, tail `a0123456` — **exactly 1 byte lost** |
| `X-P-L1027` (value 1,013 B) | 1,027 | 1,009 B, tail `aaaa0123` — **exactly 4 bytes lost** |
| `X-P-Empty` / `X-P-Colon-NoSpace` / `X-P-OnlyWs` | | **`""`** — empty string, never nil |
| `X-P-Marker` `~3~` / `X-P-QMarker` `~Q~test` | | verbatim, byte-intact |
| `X-P-InnerWs` `alpha␣␣beta⇥gamma` | | 17 B intact — interior spaces AND tabs preserved |
| `X-P-LeadWs` / `X-P-TrailWs` (edge spaces) | | trimmed, as §1 measured |
| `X-P-Tab` (leading tab) | | **10 B intact, tab preserved** |

Conclusions:

- **The truncation boundary is exactly 1,023 line bytes on build 69109** — the original
  measurement re-confirmed to the byte, from both sides.
- **An empty or whitespace-only value returns `""`, not nil** (absent key returns nil), so
  empty-vs-absent is distinguishable even raw. `~E~` stays as the explicit representation —
  it keeps empties representable inside joined/chunked contexts and is now belt-and-braces
  rather than load-bearing.
- The client performs no marker interpretation; `~Q~` guards only our own decoder, as
  designed.
- **Edge trimming is spaces only on this build — a leading tab survives.** The splitter's
  trimmable set (space, tab, CR, LF) is deliberately a conservative superset and stays;
  trailing-tab was not probed (covered by that conservatism).

## 7b. Live acceptance of the merged implementation (build 69109, baked mode)

After the merge branch's artifacts and runtime loaded in the client (producer `dfe8ee0`
data), the ADR 0003 contract was exercised live: the ruRU quest-10 corruption from §1 is
**fixed on the wire** ("что стало" reads correctly through the public getter); deDE
`objectivesText` decodes as a table (D3); `~E~` still reads as `""`; fresh-per-read
returns distinct, mutation-isolated tables (D10); packed `GetAll` carries `n` and the
value after a nil hole — the one the old `unpack` pattern dropped (D11); unknown and nil
ids read nil with `Exists` false and no error (D6); a live-registered runtime correction
outranks the ruRU translation with provenance naming the true owner (D8); 20,000 cached
scalar reads in 9.3 ms. (The smoke correction under owner `LiveSmoke` persists for the
session; a `/reload` clears it.)

## 8. Incidental runtime defect found while probing

`Quest.Get(nil, "name")` raises `table index is nil` from the decoded-field cache
(`src/read/shared.lua:180`) — `Get` validates the field argument but not the id. Public
getters should reject a nil/non-numeric id cleanly instead of erroring mid-cache.
