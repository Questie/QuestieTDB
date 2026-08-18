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

## 7. Deferred: synthetic-TOC probes (need a probe addon + full client restart)

TOC files are read at client start, so these need a crafted addon and a restart slot:

1. Exact truncation boundary on current builds (1,023 / 1,024 / 1,027-byte lines).
2. A directive with an empty value — `""` or `nil`?
3. A value that is exactly `~3~` (marker-lookalike) read back raw.
4. A value with interior-only whitespace vs edge whitespace, CRLF line endings, and a
   value ending in a UTF-8 continuation-byte split.

None block the merge program: the merged format keeps the line budget (1), `~E~` makes raw
empties unrepresentable (2), and `~Q~` escapes lookalikes (3).

## 8. Incidental runtime defect found while probing

`Quest.Get(nil, "name")` raises `table index is nil` from the decoded-field cache
(`src/read/shared.lua:180`) — `Get` validates the field argument but not the id. Public
getters should reject a nil/non-numeric id cleanly instead of erroring mid-cache.
