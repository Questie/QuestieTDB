# Read performance and cost model — measured 2026-08-19

Live-client measurements of what a read actually costs, why, and how QuestieTDB compares to
the two other implementations of the same data. Recorded so the numbers are not re-derived,
in the same spirit as [`client-metadata-probes.md`](./client-metadata-probes.md) and
[`table.freeze.md`](./table.freeze.md).

**Client:** Classic Era 1.15.9, build 69109 (Aug 3 2026), enUS, interface 11509.
**Artifact under test:** the installed `QuestieTDB_Vanilla.toc`, baked mode, producer
`build-7169b67`, 25 MB.
**Compared against:** `{Database}` (the `Getters` prototype, Vanilla TOC 21 MB, snapshot
`7e9067a` from 2026-03-08) and Questie 11.36.1's compiled database.
**Harness:** WoWDevBridge, `debugprofilestop()` for timing, `collectgarbage("count")` for
allocation, `GetAddOnMemoryUsage` for per-addon attribution.

All timings are microseconds per read unless stated. Each figure is one run over every quest
id (4,257 reads) or the stated sweep. Cold paths vary run to run by tens of percent; treat
the ratios as the finding, not the third digit.

---

## 1. What a raw metadata read costs, decomposed

`GetAddOnMetadata` is not one cost, it is four, and only one of them belongs to the client.
Best of five passes, 4,257 iterations each, all against the installed 25 MB artifact unless
noted:

| | Measurement | µs |
| --- | --- | ---: |
| A | `g("QuestieTDB", "Version")`, one constant key | 0.252 |
| B | `g("QuestieTDB", "X-Quest-2-1")`, one constant key, **our own field** | 0.259 |
| C | 4,257 distinct precomputed keys, all hits | 0.810 |
| D | 4,257 distinct precomputed keys, all misses | 0.456 |
| E | Building `"X-Quest-" .. id .. "-1"`, no client call | 0.497 |
| F | Same, but from a pre-stringified id | 0.216 |
| G | The real thing: build the key and look it up | 1.348 |

### Neither key length nor value size explains the spread

**A against B is the whole answer.** A short unrelated key and one of our own field keys, both
as constants, measure the same: 0.252 against 0.259. Ours is the *longer* of the two, 11
characters against 7. Key length is not the variable, and neither is the value, since B
returns a real quest name while A returns a short version string.

What made the earlier `Version` measurement look fast was that it is **the same key every
time**. One string object, one bucket, everything in cache. That is not a metadata lookup
being fast, it is a loop being degenerate.

### The four real costs

Reading C, D, E and B against each other separates them:

    0.50 µs   build the key string in Lua        (E)          37%
    0.26 µs   the client call itself             (B)          19%
    0.20 µs   spread across 4,257 distinct keys  (D - B)      15%
    0.35 µs   return a value instead of nothing  (C - D)      26%
    -------
    1.31 µs   predicted            against 1.35 µs measured (G)

The model closes to within 3%, so those four account for essentially all of it.

Read that column again: **the single largest line is our own Lua string building, not
anything the client does.** The client call proper is 0.26 µs.

### TOC size is not a factor

The same 25 MB artifact answers in 0.26 µs for a constant key and 1.35 µs for a built one, so
5.2× separates two lookups against an identical store. A 21 MB artifact measured no faster
than the 25 MB one. The client indexes metadata by key and does not care how many keys sit
beside it.

**Storage volume is a disk and client-memory question, never a read-latency one.** Adding
flavors, locales or fields does not slow a read, so the format can afford to be verbose where
that buys clarity.

### The artifact's filesystem does not matter either

Development here runs the addon through a Windows junction into `\\wsl.localhost`, which is a
9P mount rather than local disk. That is exactly the kind of thing that quietly invalidates a
benchmark, so it was tested rather than assumed.

A metadata-only copy of `QuestieTDB_Vanilla.toc` was placed on native NTFS under a second
addon folder, keeping every `##` directive and dropping the 48 Lua file references so it
loads no code and cannot collide with anything. Identical bytes, identical keys, best of five:

| Key shape | Over the WSL junction | Native NTFS |
| --- | ---: | ---: |
| Quest `name`, precomputed keys | 0.809 | 0.783 |
| `Npc.spawns`, multi-hundred-byte values | 0.7236 | 0.7237 |
| One constant key | 0.257 | 0.265 |

No difference; the `spawns` row agrees to four significant figures. The client parses the TOC
once at startup and serves every later lookup from memory, so where the file lives cannot
affect read cost.

**Startup cost is a separate question and is still unmeasured.** Parsing 25 MB over 9P at
client launch may well be slower than from NTFS. That is a one-time cost, it does not touch
anything in this document, and measuring it needs full client restarts with an external clock.

An attempt to reuse the duplicate to price the client-side memory of a 25 MB TOC failed and is
recorded so nobody repeats it: removing the addon and reloading moved the process working set
by 7.4 MB, but the Lua heap moved 42 MB over the same interval and the allocator does not
return freed pages to the OS. Working set is too noisy an instrument for this. It needs
restarts, measured at login before any addon activity.

### Building the key: every strategy measured

Key construction is the largest single line above, so it is worth knowing which way of
building `"X-Quest-<id>-<field>"` is actually cheapest. Best of five, 4,257 keys per pass,
no client call:

| Strategy | µs |
| --- | ---: |
| `pre[id] .. SUF[f]`, memoized `"X-Quest-<id>"` plus precomputed `"-<f>"` | **0.225** |
| `"X-Quest-" .. sid .. "-1"`, id pre-stringified | 0.307 |
| `string.format("X-Quest-%d-1", id)` | 0.470 |
| `"X-Quest-" .. id .. "-1"` (what the code does today) | 0.573 |
| `table.concat(scratch, "-")` into a reused 3-slot table | 0.966 |
| `table.concat(scratch, "-")` into a reused 4-slot table | 0.981 |
| `table.concat({"X","Quest",id,1}, "-")`, fresh table each call | 1.156 |
| A bare table lookup, for scale | 0.016 |

**`table.concat` is the worst option here, not the best.** The rule it comes from is about
*accumulating* in a loop, where `s = s .. x` repeated n times is quadratic because each step
allocates a new string. That is a real trap and `table.concat` is the right fix for it.

It does not apply to a single expression. In Lua 5.1 `a .. b .. c .. d` compiles to **one**
`OP_CONCAT` instruction over a register range and is joined in a single pass with no
intermediate strings. It is already doing what `table.concat` does internally, without the
Lua-to-C call, the per-element `rawgeti`, the table writes, or separator handling. Paying for
those to replace one VM instruction costs 0.39 µs.

Both variants also still coerce the id from number to string, so the scratch table does not
avoid the cost that actually dominates.

End to end, with the client call included:

| | µs |
| --- | ---: |
| Memoized prefix plus suffix | **1.061** |
| Fully prebuilt keys, no construction at all | 1.089 |
| `..` with a number id (today) | 1.449 |
| `table.concat` into a reused table | 1.915 |

The memoized form saves **0.39 µs, about 27% of a raw read**, and matches fully prebuilt keys
to within noise. That is the useful result: one memo per *id* captures essentially the whole
available win, where prebuilding every key would mean 153,252 strings for quests alone.

Cost is 192 KB for all 4,257 quest ids, so roughly 1.6 MB if eagerly built for all 35,944
entities across four types. It should not be built eagerly. A per-id cache table already gets
allocated on first touch, so the prefix belongs in a slot on that table: no new structure, and
the memory scales with what a session actually reads rather than with the database.

In context this is about **11% off a cold `Get`** and nothing at all off a warm one, since a
warm read never builds a key. Real, cheap, and not perceptible. It is worth far more to an
uncached design: `{Database}` rebuilds every key on every read forever, so the same change
would be 27% of its steady-state cost rather than a one-time 11%.

### A floor, and who is under it

About 1.3 µs is the floor for any design that builds a key and calls the client on every read.
Neither `{Database}` nor Questie's compiler can get beneath it by improving its decode path.
Only not making the call gets under it, which is what our cache does at 0.59 µs warm.

Single-pass runs of G during this session gave 1.43 and 1.54 µs against the 1.35 best-of-five
here. Treat sub-0.1 µs differences in this document as noise.

## 2. Where a read's time goes

Quest `name`, 4,257 ids, one pass each:

| Step | µs |
| --- | ---: |
| Key construction alone, no client call | 0.50 |
| Key construction plus `GetAddOnMetadata` (the floor) | 1.35 |
| Questie compiler, `QueryQuestSingle` | 0.82 |
| `{Database}` named getter | 2.27 |
| `{Database}` `Get` | 2.53 |
| QuestieTDB `Get`, cold | 3.52 |
| QuestieTDB `name()`, cold | 3.43 |
| QuestieTDB `GetRaw` | 2.92 |
| **QuestieTDB `name()`, warm** | **0.59** |

`{Database}` adds about 0.9 µs on top of the 1.35 µs floor. QuestieTDB adds about 2.1 µs.
That extra 1.2 µs on a **first** read is the whole of the difference, and it is spent on
things the prototype does not have:

* the Correction Overlay probe (`overlay[id]` plus a field lookup)
* the l10n provider hook
* existence gating, so an unknown id reads nil for every field rather than a default
* allocating the per-id cache table
* writing the decoded value or its producer into the cache
* building the copy producer, so every table read hands out a fresh value

None of that is waste. It is the feature set, priced. And it is paid once per `(id, field)`,
not per read.

**Warm reads land below the floor** at 0.59 µs because no client call happens at all. That is
the point of the cache and it is the one thing an uncached design cannot copy.

These agree with the earlier probe session recorded in
[`client-metadata-probes.md`](./client-metadata-probes.md) section 6, which measured 3.7 µs
first-touch on `name`. Its 0.25 µs cached figure is a different shape: 20,000 reads of one
id, so a single cache table stays hot. Sweeping 4,257 distinct ids, as here, touches 4,257
of them and lands at 0.59 µs. Both are the cached path; the gap is cache locality, not
decode work.

### Break-even is the second read

For m reads of the same field:

    QuestieTDB   3.43 + 0.59 × (m - 1)
    {Database}   2.27 × m

| m | QuestieTDB | `{Database}` |
| ---: | ---: | ---: |
| 1 | 3.43 | **2.27** |
| 2 | **4.02** | 4.54 |
| 5 | **5.79** | 11.35 |
| 20 | **14.64** | 45.40 |

Read a field once and never again, and the prototype wins by 1.2 µs. Read it twice, and
QuestieTDB is ahead permanently.

---

## 3. Scalars and tables are different problems

Per field, 4,257 quest ids:

| Field | Kind | Present | TDB cold | TDB warm | `{Database}` | Questie |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `name` | string | 4257 | 3.41 | 0.66 | 2.45 | **0.83** |
| `requiredLevel` | number | 4257 | 3.68 | 0.81 | 2.15 | **0.43** |
| `preQuestGroup` | table | 67 | 2.70 | 0.58 | 1.57 | **0.91** |
| `startedBy` | table | 4257 | 4.90 | **1.21** | 4.02 | 5.27 |
| `objectives` | table | 4257 | 5.18 | **1.37** | 4.63 | 9.90 |

Questie's compiler is fast on scalars and slow on tables, by a factor of twelve between
`requiredLevel` (0.43) and `objectives` (9.90). It does not cache: three consecutive passes
measured 6.2, 6.2 and 6.6 µs on `npc.spawns`, flat. So it extracts a field from a compiled
string on every call, which is cheap for a number and expensive for a nested table.

This explains an aggregate result that otherwise looks strange. Over a full 32-field sweep,
136,224 reads:

| | pass 1 | pass 2 |
| --- | ---: | ---: |
| QuestieTDB | 2.96 | **0.56** |
| `{Database}` | 2.15 | 2.03 |
| Questie compiler | 2.43 | 2.46 |

`{Database}` beats Questie's compiler in aggregate, 2.03 against 2.46, which is a real result
and was the prototype's original headline. But the aggregate is dominated by table fields, and
what it actually says is that the prototype's table path is about twice as fast as the
compiler's. On scalars the compiler is ahead of both uncached designs.

---

## 3b. The heavy table fields, and what copy-per-read costs

The fields that dominate real CPU time are the big nested tables. Measured across every
entity of each type, cold with an empty cache, warm through the current producer cache, and
against a simulated **shared-table** cache that hands back the same table on every read:

| Field | Entities | Present | Cold | Warm (copy per read) | Shared table | Speed-up |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Npc.spawns` | 10,122 | 7,947 | 13.14 | 1.97 | **0.030** | 65× |
| `Object.spawns` | 6,666 | 4,946 | 13.75 | 2.19 | **0.037** | 59× |
| `Quest.objectives` | 4,257 | 4,257 | 5.42 | 1.16 | **0.032** | 36× |
| `Npc.waypoints` | 10,122 | 480 | 5.49 | 0.89 | **0.035** | 25× |

A warm read of a table field does no key building and makes no client call. Every one of
those 0.89 to 2.19 µs is **constructing a fresh copy for the caller**. A shared table reduces
that to a table lookup, 0.03 µs, which is the floor.

### The surprise: it is not a memory trade

The obvious objection is that materializing tables costs memory where a compiled producer does
not. Measured, that is simply false:

| Field | Producer cache | Materialized tables |
| --- | ---: | ---: |
| `Npc.spawns` | 10.52 MB | 10.46 MB |
| `Object.spawns` | 7.95 MB | 8.64 MB |
| `Quest.objectives` | 1.79 MB | 1.56 MB |
| `Npc.waypoints` | 3.95 MB | 3.53 MB |
| **Total** | **24.21 MB** | **24.19 MB** |

Within a fraction of a percent, and cheaper on three of the four fields. A compiled Lua chunk
that constructs a table costs about what the table costs. These are alternatives, not
additions: an implementation holds one or the other.

Re-verified on a **fresh UI reload**, since caching from earlier probes can distort a heap
measurement. Same heap, two phases in sequence, `Npc.spawns` across all 7,953 present
entities: producer cache 10.67 MB, then materializing the tables on top of it a further
10.46 MB. The reload moved nothing.

One measurement trap worth recording: decoding straight from raw metadata with
`loadstring("return " .. value)` to skip the producer cache gives 5.45 MB, which looks like
a large win and is wrong. It silently drops chunked values, and chunked values are by
definition the biggest tables. The entity count gives it away, 7,315 against 7,953.

So the choice between copy-per-read and shared tables is **not** a CPU-versus-memory trade.
It is entirely a question of the read contract.

### What it would actually cost

`docs/api.md` promises that every table read returns a fresh, deeply independent, mutable
value the caller owns, and ADR 0003 Decision 10 chose that deliberately after
[`table.freeze.md`](./table.freeze.md) retired shared frozen values. The reasons still stand:

* Questie's own `Query*Single` returns a fresh table per call and does not cache, so ported
  consumer code assumes it can mutate a read result. Sharing would silently corrupt the
  database for every other consumer.
* `table.freeze` is the mitigation that turns silent corruption into a loud error, and this
  client has it, with `canFreeze` true. But freezing is gated on taint ownership: a
  `Freeze` call from outside QuestieTDB is refused, which this session confirmed by watching
  `shared.freezeRefused` go from 0 to 1. Whether QuestieTDB's own compiled code can freeze
  these values was validated separately in
  [`client-metadata-probes.md`](./client-metadata-probes.md) section 3 and is not re-proven
  here.
* Every consumer that mutates a read result would need auditing, which is precisely the cost
  Decision 10 was revised to avoid.

The number is large enough that the decision deserves to be re-made deliberately rather than
inherited. **65× on the hottest field, at no memory cost**, is a different proposition than
the one Decision 10 was weighed against. A middle option exists and is untested: share frozen
tables only for fields a consumer has no business mutating, and keep copies elsewhere.

### Key building barely matters here

For scale, the memoized-prefix optimization from section 1 saves about 0.4 µs on a cold read.
Against `Npc.spawns` at 13.14 µs cold that is 3%, and it saves nothing at all on a warm read.
On heavy fields, decode and copy dominate; key building is noise.

## 4. A realistic workload

A full 25-quest log, resolving all 74 referenced NPCs, objects and items, reading name and
spawns for each. This is the shape of work Questie does when the log changes.

| | pass 1 | pass 2 | pass 3 |
| --- | ---: | ---: | ---: |
| QuestieTDB | 1.86 ms | 0.47 ms | **0.44 ms** |
| `{Database}` | 1.47 ms | 1.41 ms | |
| Questie compiler | 1.08 ms | 1.15 ms | |

Garbage produced per pass: `{Database}` 174 KB, Questie 53 KB, QuestieTDB nothing once warm
(its 200 KB is cache, allocated once and retained).

Every one of these is under two milliseconds. The practical difference between them is not
frame time, it is whether the cost repeats.

---

## 5. Memory

Floors, after `InvalidateCache()` and two full collections:

| Addon | MB |
| --- | ---: |
| `{Database}` | 4.57 |
| QuestieTDB | 6.65 |
| Questie | 51.9 |

QuestieTDB at rest immediately after a fresh UI reload, before any query: **6.37 MB**.

The cache is the variable. Growth measured across all 4,257 quest ids:

| | KB |
| --- | ---: |
| First field swept across every id | 937 |
| Each additional field | 427 |

About 510 KB of that first figure is the one-time per-id cache table, roughly 120 bytes per
id, paid on the first field touched and never again. The rest is per-field.

Worst case, after reading **every field of every entity** across all four types, which no
session would ever do: **37.6 MB**. `InvalidateCache()` returns it to 8.3 MB.

`{Database}` never grows, because it never caches. It pays the floor forever instead.

The Lua figures exclude the client-side cost of holding the TOC metadata itself, which
`collectgarbage("count")` cannot see. `GetAddOnMemoryUsage` attributes only Lua allocations
made by that addon.

---

## 6. Findings worth acting on

A third one, memoizing the key prefix per id, is measured in full in section 1.

### `Get(id, index)` is slower than `Get(id, name)`

Best of three over a 32-field sweep, 136,224 reads, after a warm-up pass:

| Call | Cold | Warm |
| --- | ---: | ---: |
| `Get(id, "name")` | 2.836 | 0.546 |
| `Get(id, 1)` | 2.989 | 0.634 |
| `GetByIndex(id, 1)` | 2.974 | 0.593 |

`entity.Get` at `src/read/shared.lua:318` resolves the key as
`keys[key] or (type(key) == "number" and key or nil)`. A name hits `meta.keys` on the first
lookup and stops. A number misses it, then pays a `type()` call and the `and`/`or` chain.

The penalty is **0.088 µs warm and 0.153 µs cold**, and `GetByIndex`, which skips the failed
lookup and only validates the number, recovers most of it at 0.593. So a private index-aware
map inside the reader is worth roughly 0.05 to 0.09 µs on warm index reads, and nothing at all
on name reads.

A fix must not seed `meta.keys` with numeric self-mappings: that table is the public
`questKeys` that Correction authors index, and it holds exactly 36 name entries.

**An earlier single pass in this session reported 0.95 against 0.56 and put the penalty at
0.39 µs. That was noise.** The measurement above adds a warm-up pass and takes the best of
three; it is the one to trust. The asymmetry is real, the magnitude was overstated 4×.

### The two read-path fixes do not compose

Memoizing the key prefix (section 1) and fixing index resolution act on different phases, so
their savings do not add:

| Read | Index fix | Key memo | Total |
| --- | ---: | ---: | ---: |
| Warm, by name | 0 | 0 | **0** |
| Warm, by index | 0.09 | 0 | 0.09 |
| Cold, by name | 0 | ~0.40 | 0.40 |
| Cold, by index | 0.15 | ~0.40 | ~0.55 |

The key memo can only help a **cold** read, because a warm read builds no key and makes no
client call at all. The proof is in the numbers above: a warm read costs 0.546 µs, well under
the 1.35 µs a single `GetAddOnMetadata` call takes, so it cannot be making one.

The index fix can only help a call that passes a **number** to `Get`. Name keys already take
the fast path, and the generated per-field getters like `QuestDB.name(id)` bypass `Get`
entirely.

They stack only on a cold read by numeric index, which is the rarest of the four cases.

### `GetRaw` is uncached

2.92 µs cold and 2.73 µs on repeat, with no improvement, because it goes to the backend every
time. That is defensible for a tooling and debugging surface, but it is undocumented, and a
consumer who reaches for `GetRaw` in a loop will not get the read path they expect.

---

## 7. Measurement hazard: the Entity globals collide

`{Database}` defines the globals `QuestDB`, `NpcDB`, `ItemDB` and `ObjectDB`. So does
QuestieTDB. `{` sorts after letters, so with both installed `{Database}` loads later (index 63
against 42) and **wins every one of those four names**.

Anything that benchmarks or tests through a bare global with both addons installed is
measuring whichever one loaded last, silently. Two properties tell them apart without
ambiguity:

```lua
_G.QuestDB == LibQuestieDB.Quest   -- false when the prototype has taken the global
type(_G.QuestDB.test)              -- "function" on the prototype, nil on QuestieTDB
type(_G.QuestDB.GetRaw)            -- "function" on QuestieTDB, nil on the prototype
```

They also disagree about the signature, which makes a silent mismatch cheap to detect: the
prototype's `Get` takes a **numeric index only** and returns nil for a string key, while
QuestieTDB's `Get` accepts either. Every measurement in this document was taken through
`LibQuestieDB.<Type>` and `_G.QuestDB` explicitly, with the identity asserted in the same
call.

The prototype is being retired (see
[`retiring-the-prototypes.md`](./retiring-the-prototypes.md)), so this is a hazard for
comparison work rather than a shipping conflict.

---

## 8. Reproducing this

The harness is a `_G.__H` table holding explicit handles, installed once, then small chunks
that read it. Keep each bridge request under 3,900 characters and each frame's work under a
second or two.

**Do not sweep large-value keys in bulk.** Reading 4,257 multi-kilobyte `X-l10n-Quest-*`
values three times in one frame killed the client outright during this session, on a process
already at 2.5 GB working set. Large-value probes need batching across frames; the small-key
sweeps in section 1 are safe at 4,257 iterations each.

```lua
_G.__H = {
  ids   = LibQuestieDB.Quest.GetAllIds(),
  qnames= LibQuestieDB.Meta.Quest.names,
  tdbQ  = LibQuestieDB.Quest,
  protoQ= _G.QuestDB,
  qsingle = QuestieLoader:ImportModule("QuestieDB").QueryQuestSingle,
  inval = function() LibQuestieDB.InvalidateCache() end,
}
```

Fields 1 to 32 of the quest schema are identical in name and order between QuestieTDB and
`{Database}`, so they compare directly. QuestieTDB has 36; the prototype has 32 plus an
injected `xpReward`. Entity counts differ because the prototype is a March data snapshot:
4,256 quests against 4,257, and 9,883 NPCs against 10,122.

---

# Findings 2026-09-03: first-pass cost, the prototype, and CBOR

A second measurement session, recorded in full so none of it is re-derived. Everything here
was taken live, and the ideas that lost are recorded beside the ones that won.

**Client:** Classic Era 1.15.9, build 69547 (Aug 26 2026), enUS, interface 11509.
**Artifact under test:** the installed `QuestieTDB_Vanilla.toc`, baked mode, producer
`build-eaea07d`, 20.8 MB. Four commits behind HEAD at the time, none touching the read path.
**Compared against:** `{Database}` (the `Getters` prototype, loaded alongside), and the
read shapes in the Questie fork on branch `QuestieTDB`, which still runs the compiler.
**Harness:** WoWDevBridge, `debugprofilestop()` for timing, `collectgarbage("count")` with
the collector stopped for allocation. Section 9.11 has the harness.

Microseconds per read unless stated. Cold figures drift by tens of percent between runs
with heap state, and one pair in this session was inverted by it (9.8); treat ratios as the
finding. Figures marked ≈ are composed from measured parts rather than measured end to end.

## 9.1 Where a cold scalar read goes

Quest `name`, 4,257 ids. Cold 3.3 to 3.6, warm 0.36 to 0.55. Layers added one at a time:

| Layer | µs | Share |
| --- | ---: | ---: |
| Build the key, two number coercions (`prefix .. id .. "-" .. fieldIndex`) | 0.64 | 19% |
| `GetAddOnMetadata` | 0.77 | 23% |
| `getStored`: call plus `codec.chunkCount[value]` | 0.26 | 8% |
| `readField`: decoder lookup, `decodeString` | 0.36 | 11% |
| `get` in shared.lua: per-id cache table, overlay probe, l10n hook, type lookup, cache write | 1.3 | 39% |

Smaller pieces measured on their own, each the best of five over 4,257 iterations:

| Piece | µs |
| --- | ---: |
| Key with one number coerced | 0.41 |
| Key with two numbers coerced | 0.64 |
| `chunkCount[value]` on a non-chunk value: metatable miss plus `string.match` | 0.27 |
| Same check as `byte(value, 1) == 126` | 0.17 |
| `decodeString` as written (`sub(value, 1, 3)` allocates) | 0.31 |
| `decodeString` with a first-byte guard | 0.19 |
| `tonumber("20")` | 0.27 |
| The l10n provider hook on enUS, where it returns nil at once | 0.15 to 0.19 |
| `Exists(id)` | 0.16 |
| `Get(id, "name")` warm / `Get(id, 1)` warm | 0.54 / 0.63 |

The `chunkCount` miss is worth naming: the memo only covers hits, so every ordinary value
pays a pattern match through `__index` and is never memoized. Together the four small
fixes (first-byte chunk check, first-byte quote guard, l10n hook filtered by translatable
field index, memoized key prefix) are worth about 0.7 µs of a cold scalar and nothing warm.
They matter less under 9.9, which pays them per entity rather than per field.

## 9.2 Tables: compile dominates cold, copy dominates warm

| Field | Entities | Cold | of which `loadstring` | Warm | Garbage per warm sweep |
| --- | ---: | ---: | ---: | ---: | ---: |
| `Npc.spawns` | 10,122 | 12.4 to 13.1 | ≈8.4 | 2.3 to 2.7 | 10.3 MB |
| `Object.spawns` | 6,666 | 14.9 | | 2.3 | |
| `Quest.objectives` | 4,257 | 6.2 to 8.2 | | 1.3 to 2.6 | 1.3 MB |
| `Quest.startedBy` | 4,257 | 5.3 to 7.4 | | 0.9 to 1.0 | |

A warm `Npc.spawns` read allocates about 1 KB, which is the fresh copy. A cold sweep of
`Npc.spawns` produced 31.7 MB of garbage, mostly compile. Scalars allocate nothing warm.
102 of the 7,947 stored spawn tables are chunked.

`loadstring` cost is close to linear in literal bytes, about 27 ns per byte plus 1 µs fixed:

| Literal | Bytes | Compile | Execute |
| --- | ---: | ---: | ---: |
| `{{12676}}` | 9 | 1.09 | 0.18 |
| `{{12676},nil,{16305}}` | 21 | 2.0 | 0.66 |
| 20 small tuples | 159 | 8.4 | 4.3 |
| 60 coordinate pairs | 848 | 23.4 | 16.3 |

**Batching compiles does not help.** Fifty small literals compiled as one chunk returning
fifty producers cost 2.8 µs each against 2.0 compiled one at a time; fifty big ones cost
24 each against 23.4. There is no per-call overhead to amortise, so the idea is dead.

## 9.3 Localization and other per-read costs

| Read | Cold µs |
| --- | ---: |
| Quest `name`, enUS | 3.5 |
| Quest `name`, deDE | 4.05 |
| Quest `name`, zhTW | 5.61 |
| Quest `objectivesText`, enUS | 5.75 |
| Quest `objectivesText`, deDE | 16.2 |
| Npc `name`, deDE | 4.04 |

`localeSegment` walks the joined value segment by segment, about 0.25 µs each, so the last
locale of nine pays 2 µs more than the first. The translated list field costs nearly three
times English because the provider returns a decoded table through `codec.decodeTable`,
which `get` then wraps in a deep-copy producer instead of the compiled-chunk producer the
baked fast path uses.

Other findings from the same pass:

* **Unknown ids get a cache table.** 4,257 misses cost 2.4 µs first and 0.41 repeated,
  and retained 561 KB until the next invalidate.
* **`GetAll` with three keys:** 10.4 cold, 2.5 warm, against 1.5 for three separate `Get`
  calls warm.
* **`GetRaw` allocates 373 KB per 4,257 reads** and stays at 2.7 µs, as documented.
* **Garbage per cold sweep of 4,257 quests:** `name` 913 KB, `requiredLevel` 579 KB,
  `objectives` 4.5 MB.

## 9.4 Load-time and first-touch work

| Work | ms |
| --- | ---: |
| `ApplyRegisteredCorrections("QuestieTDB")` at load | 1.2, +184 KB |
| `decodeIdMap` via `gsub` plus `loadstring`: Item / Npc / Object / Quest | 11.7 / 8.8 / 7.1 / 2.9 |
| `decodeIdList` for the same: | 2.8 / 1.7 / 1.2 / 0.8 |
| Building the Item map from the decoded list in a loop instead | 1.0 |
| `BuildNameIndex`: Item / Npc / Object / Quest | 59 / 36 / 26 / 15 |

The id maps are lazy but land on the first `Exists` or `GetAllIds` per type, which for
Questie is its init. Thirty milliseconds there against four is an easy change.

Load-time CPU of the addon itself is still unmeasured. `scriptProfile` set to 1 followed by
a `/reload` reported zero CPU for QuestieTDB, so that cvar needs a full client restart to
catch addon load; it was reset to 0 afterwards.

## 9.5 A quest-log workload, and the prototype

25 quests resolving 76 NPCs, objects and items: names, spawns, objectives and drops.

| | pass 1 | pass 2 | pass 3 |
| --- | ---: | ---: | ---: |
| QuestieTDB | 1.55 ms, 206 KB | 0.25 ms, 49 KB | 0.22 ms, 49 KB |
| `{Database}` | 1.51 ms, 189 KB | 1.20 ms, 156 KB | 1.29 ms, 155 KB |

The steady 49 KB is the copy-per-read contract on the table fields. Nothing else allocates
warm.

Side by side, same session. The prototype has no cold or warm state because it caches nothing:

| Field | Prototype | TDB cold | TDB warm |
| --- | ---: | ---: | ---: |
| Quest `name` | 2.30 | 3.65 | 0.36 |
| Quest `requiredLevel` | 2.30 | 3.95 | 0.41 |
| Quest `objectives` | 5.17 | 8.16 | 2.63 |
| Quest `startedBy` | 4.64 | 7.38 | 0.86 |
| Quest `Get(id, 1)` | 2.65 | | 0.64 |
| Npc `name` | 2.06 | 3.33 | 0.33 |
| Npc `minLevel` (semicolon-combined in the prototype) | 3.30 | 2.62 | 0.38 |
| Npc `npcFlags` (ninth sub-field of the combined value) | 3.86 | | |
| Npc `spawns` | 10.86 | 13.1 | 2.67 |
| Npc `spawns` garbage per sweep | 28.7 MB | | 10.3 MB |

Resting memory after invalidate and two collections: prototype 4.7 MB, QuestieTDB 8.7 MB.

The prototype is faster on first touch by about 1.3 µs on a scalar and 3 µs on a table,
which is exactly the cache layer in 9.1. It loses on every read after the first, on garbage,
and on its combined scalars, where each getter rescans the joined string with `gmatch`. Its
own `test()` sweeps read every field once, which is the one shape where it wins.

## 9.6 What Questie actually reads

The fork on branch `QuestieTDB` does not consume QuestieTDB yet. Its read shapes are the
compiler's, and they are what any format must serve:

* `GetQuest`, `GetNPC`, `GetObject`, `GetItem` read **every field** of one entity through
  `Query<Type>(id, adapterOrder)` once and cache the object on Questie's side. QuestieTDB's
  per-field cache never sees a second read from this path.
* 184 single-field call sites: `QueryQuestSingle` 125, `QueryItemSingle` 27,
  `QueryNPCSingle` 20, `QueryObjectSingle` 12. The availability calculation is the hot one:
  two or three quest scalars across every quest id.

Whole quest row, 36 fields, 500 quests:

| | µs per quest |
| --- | ---: |
| QuestieTDB cold, 36 reads (6 scalar hits, 12 scalar misses, 6 table hits, 12 table misses) | 110 |
| Prototype, 32 getters | 67 |
| QuestieTDB warm | 21 |
| One row as a Lua literal, 369 bytes, `loadstring` and execute | 19.2 (14.5 compile) |
| The 29 scalar slots joined in one string, split with `string.find` | 7.3 |

The availability shape, `requiredLevel`, `requiredRaces`, `requiredClasses` for all 4,257:
7.0 µs per quest cold (30 ms), 0.97 warm (4 ms).

## 9.7 CBOR: fidelity

`C_EncodingUtil` on this build exposes `SerializeCBOR`, `DeserializeCBOR`, `SerializeJSON`,
`DeserializeJSON`, `CompressString`, `DecompressString`, `EncodeBase64`, `DecodeBase64`,
`EncodeHex`, `DecodeHex`.

Every value shape the database uses round-trips exactly through the client codec: sparse
arrays with nil holes (`{{1},nil,{3}}`), `{[3]={16305}}`, integer-keyed maps of coordinate
lists, floats including 2^53 and 1e10, nested empties, booleans, and strings containing NUL,
tab and newline. Numbers come back as numbers and tables as tables, so `tonumber`,
`loadstring`, the `~E~` marker and `~Q~` quoting are unnecessary on this path. The offline
`BlizzardCBOR.lua` encoder agrees with the client on the full Classic quest table, 4,244
rows and 55,726 leaf values, zero differences. Transport through TOC lines, base64 charset
survival, and compression are in
[`client-metadata-probes.md` §10](./client-metadata-probes.md).

## 9.8 CBOR: cost by granularity

Per field, real stored values, best of three:

| Value | `loadstring` cold | chunk re-exec warm | CBOR decode | base64 then CBOR | Literal B | CBOR B | CBOR b64 B | CBOR zlib b64 B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Quest 2 `startedBy` | 1.29 | 0.18 | 0.50 | 0.96 | 13 | 6 | 8 | 12 |
| Quest 2 `objectivesText` | 1.50 | 0.21 | 0.51 | 1.01 | 83 | 82 | 112 | 104 |
| Npc 30 `spawns` | 17.1 | 3.2 | 4 to 5 | 3.5 to 5 | 228 | 307 | 412 | 276 |
| Npc 721 `spawns`, largest in the first 3,000 | 477 | 82 | 135 | 162 | 6,346 | 8,451 | 11,268 | 4,224 |

CBOR is three to four times faster than compiling a literal and level with re-executing a
compiled chunk, and each decode is a fresh table. Its floor is about 0.5 µs, and base64
adds about 0.5 on small values. Coordinates serialize as 8-byte doubles, which is why CBOR
bytes exceed the literal on spawns; storing them as integers scaled by 100 cut the NPC
table 33% before compression and 8% after, with no decode-time change. (The Npc 30 pair
where base64-then-CBOR read faster than bare CBOR is noise of 1 to 2 µs on a 1,000-iteration
loop.)

Per row, per page and per table:

| Unit | CBOR | zlib + base64 in the TOC | Decode | Heap after |
| --- | ---: | ---: | ---: | ---: |
| One quest row, all 36 fields | | 216 B (base64 only) | 5.2 µs | |
| 500 quest rows | 80 KB | 51 KB | 1.4 ms | |
| All 4,257 quests, scalars only, row layout | 175 KB | 97 KB | 4.6 ms | 2.5 MB |
| All 4,257 quests, every field | 690 KB | 353 KB, 354 lines | 8.8 ms isolated, 12.4 ms pipeline | 8.3 MB |
| All 10,122 NPCs, every field | 1,972 KB | 751 KB zlib | 46 ms | 19.2 MB |
| Same with integer coordinates | 1,312 KB | 688 KB zlib | 46 ms | |

Read cost after decoding: 0.12 µs per quest for three scalars from the decoded table,
against 7.0 cold and 0.97 warm today. `DeserializeCBOR` cannot yield, so the NPC figure
rules out whole-table blobs for table fields.

**A first pipeline run read 23 ms compressed against 45 uncompressed.** That was heap
state between two back-to-back 690 KB decodes in one frame. Isolated, with a collection
before each run, compression costs about 1.5 ms extra and is a size decision only.

## 9.9 The scalar blob per type: row layout against column layout

Scalars of every entity of one type in one blob, decoded once at load. Two layouts.

**Row layout**, one sparse table per entity keyed by field index:

| Type | Ids | Scalar fields | TOC, zlib base64 | Decode | Heap |
| --- | ---: | ---: | ---: | ---: | ---: |
| Item | 14,899 | 10 | 252 KB | 9.9 ms | 7.0 MB |
| Npc | 10,122 | 11 | 226 KB | 10.5 ms | 5.5 MB |
| Quest | 4,257 | 18 | 97 KB | 3.9 ms | 2.5 MB |
| Object | 6,666 | 3 | 76 KB | 3.1 ms | 1.5 MB |
| **Total** | | | **651 KB** | **27 ms** | **16.5 MB** |

Too heavy. Each entity is its own table with a hash part for sparse field indices, about
470 bytes of structure per item before any value.

**Column layout**, one array per field indexed by position in the ascending id list, plus an
id-to-position map:

| Type | TOC | Decode | Columns (dense, `false` holes) | Position map | Read |
| --- | ---: | ---: | ---: | ---: | ---: |
| Item | 222 KB | 9.3 ms | 3.8 MB | 0.8 MB, 1.9 ms to build | 0.06 |
| Npc | 184 KB | 7.5 ms | 2.8 MB | 0.4 MB, 1.2 ms | 0.06 |
| Quest | 80 KB | 3.8 ms | 1.9 MB | 0.3 MB, 0.5 ms | 0.06 |
| Object | 64 KB | 1.9 ms | 0.6 MB | 0.4 MB, 0.8 ms | 0.08 |
| **Total** | **550 KB** | **22 ms** | **9.1 MB** | **1.9 MB** | |

The position map can replace the id-to-true map QuestieTDB already builds for `Exists` and
`GetAllIds(true)` if that contract is relaxed from `true` to truthy, in which case it costs
4.5 ms for all four types against the 30 ms `gsub` path in 9.4 and adds no memory.

**Dense against sparse columns, per field.** Lua puts integer keys in the array part when
more than about half the slots between 1 and the largest key are used, 16 bytes per slot
including holes, and otherwise in the hash part at about 40 bytes per present entry and
nothing for absent ones. So a column with nil holes never costs more than one padded with
`false`, and costs far less when mostly empty. Heap in KB:

| Column | Present | Dense with `false` | Nil holes |
| --- | ---: | ---: | ---: |
| Item `itemLevel` | 99% | 384 | 384 |
| Item `requiredLevel` | 59% | 384 | 384 |
| Item `flags` | 22% | 384 | 224 |
| Item `startQuest` | 1.4% | 384 | 14 |
| Item `teachesSpell` | 0% | 384 | 0 |
| Npc `zoneID` | 78% | 384 | 304 |
| Npc `subName` | 24% | 384 | 224 |
| Npc `rank` | 25% | 384 | 224 |
| Quest `requiredRaces` | 68% | 192 | 99 |
| Quest `nextQuestInChain` | 41% | 192 | 104 |
| Quest `requiredClasses` | 20% | 192 | 56 |
| Quest `parentQuest` | 1% | 192 | 3 |

| Type | Dense columns | Nil-hole columns | CBOR dense | CBOR nil holes |
| --- | ---: | ---: | ---: | ---: |
| Item | 3.6 MB | 2.2 MB | 447 KB | 388 KB |
| Npc | 4.2 MB | 2.8 MB | 341 KB | 324 KB |
| Quest | 3.4 MB | 1.3 MB | 178 KB | 147 KB |
| Object | 0.6 MB | 0.4 MB | 111 KB | 105 KB |
| **Total** | **11.8 MB** | **6.7 MB** | | |

Nil-hole columns round-trip through CBOR with positions intact for every column. The one
place dense read smaller, Item `name` at 98 KB against 384, was string interning from an
earlier pass and collector granularity, and is not worth a special case: the rule is
**omit absent values and let Lua choose**.

Four columns are 0% present on Vanilla (`Item.teachesSpell`, `Item.foodType`,
`Npc.minLevelHealth`, `Npc.maxLevelHealth`) and ten of the eighteen quest scalars are under
5%. An absent column should not exist in the blob; a read of it returns the field default.

**Scalar layer total with nil-hole columns: about 6.7 MB, plus 1.9 MB of position maps
unless folded into the id map.** Questie's compiled database is 51.9 MB for comparison.

## 9.10 Options by read shape, and what was rejected

| Read shape | Today | Prototype | CBOR per field | CBOR per quest | Scalar columns + CBOR tables |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold scalar | 3.5 | 2.3 | 3.5 | ≈7 | 0.1 to 0.4 |
| Warm scalar | 0.4 | 2.3 | 0.4 | 0.4 | 0.1 to 0.4 |
| Cold `Npc.spawns` | 13 | 10.9 | ≈5.5 | ≈6 | ≈5.5 |
| Warm `Npc.spawns` | 2.5 | 10.9 | ≈3.5 | ≈3.5 | ≈3.5 |
| `GetQuest`, 36 fields, first time | 110 | 67 | ≈95 | ≈7 | ≈40 |
| Availability sweep, 3 scalars × 4,257, first time | 30 ms | 29 ms | 30 ms | ≈33 ms | 0.5 ms |
| Same, repeated | 4 ms | 29 ms | 4 ms | 4 ms | 0.5 ms |
| One-time decode at load | 0 | 0 | 0 | 0 | 22 ms |
| Heap held at rest | 8.7 MB | 4.7 MB | same | same | +6.7 to 8.6 MB |
| Quest data in the TOC (today: 683 KB scalars + 1,002 KB tables) | 1,685 KB | | ≈1.9 MB | ≈920 KB | 80 KB + ≈1.2 MB |

Of the 20.8 MB Vanilla TOC, 8.9 MB is localization and 3.0 MB is NPC data. Entity scalars
are not where the artifact's size lives.

Rejected, with the number that rejected it:

* **Batching table compiles.** 2.8 µs per literal batched against 2.0 alone (9.2).
* **A whole row as a Lua literal.** 19.2 µs against CBOR's 5.2 (9.6, 9.8).
* **Whole-table blobs for table fields.** 46 ms atomic and 19 MB for NPCs (9.8).
* **Row-layout scalar blobs.** 16.5 MB (9.9).
* **Dense columns with `false` placeholders.** 11.8 MB against 6.7 (9.9).
* **CBOR per quest row as the only layout.** Fixes `GetQuest` and leaves the availability
  sweep untouched (9.10).
* **Hex transport.** Base64 survives TOC lines, and hex doubles the bytes (probes §10).
* **SavedVariables as a warm cache.** Cannot hold functions, loads slower than metadata.
* **The prototype's semicolon-combined scalars.** Rescanning per getter costs more than a
  cold TDB read (9.5).

Still unmeasured: what today's cache grows into over a real Questie session, per-field CBOR
table storage on a generated artifact, the client's own TOC parse at startup, and whether a
producer cache on top of per-field CBOR is worth keeping for warm table reads.

**Direction taken:** scalar columns per type with nil holes, per-field CBOR tables with
integer coordinates, zlib base64 transport, the position map folded into the id map. See the
ADR still to be written; until it exists this section is the decision record.

## 9.11 Reproducing this

The harness installs `_G.__P` once and every measurement is a short chunk against it. Keep
each bridge request under 3,900 characters and each frame under a second; the whole-table
row builds in 9.8 and 9.9 took 190 to 540 ms per type and were fine.

```lua
local L = LibQuestieDB
local P = { L = L, g = C_AddOns.GetAddOnMetadata, Q = L.Quest, N = L.Npc, I = L.Item, O = L.Object }
P.qids, P.nids, P.iids, P.oids = L.Quest.GetAllIds(), L.Npc.GetAllIds(), L.Item.GetAllIds(), L.Object.GetAllIds()
P.qk, P.nk, P.ik, P.ok = L.Meta.Quest.keys, L.Meta.Npc.keys, L.Meta.Item.keys, L.Meta.Object.keys
function P.us(fn, ids, reps)            -- best-of-reps, microseconds per call
  local best
  for r = 1, (reps or 1) do
    local t0 = debugprofilestop()
    for i = 1, #ids do fn(ids[i]) end
    local dt = debugprofilestop() - t0
    if not best or dt < best then best = dt end
  end
  return math.floor(best * 1000 / #ids * 1000 + 0.5) / 1000
end
function P.cold(fn, ids) L.InvalidateCache() return P.us(fn, ids, 1) end
function P.kb(fn, ids)                  -- KB allocated over one pass, collector stopped
  collectgarbage("collect"); collectgarbage("stop")
  local b = collectgarbage("count")
  for i = 1, #ids do fn(ids[i]) end
  local d = collectgarbage("count") - b
  collectgarbage("restart")
  return math.floor(d * 10 + 0.5) / 10
end
_G.__P = P
```

For blob measurements, take the best of three with `collectgarbage("collect")` before each
run; without it the second decode in a frame pays for the first one's garbage (9.8). The
CBOR transport battery and its generators are in `tools/probe-addon/`.

## 9.12 CBOR row acceptance, 2026-09-03

The implementation from ADR 0010 was measured on the same Classic Era 1.15.9 build 69547.
Sections 1 through 9.6 describe the retired per-field literal reader and remain as its cost
record. This section supersedes the preliminary scalar-column direction at the end of 9.10:
production
uses one scalar row per entity, raw coordinates, per-field CBOR tables and compressed CBOR ID
headers. The generated Vanilla artifact reported contract 2 and loaded in Baked mode. Field sweeps use
the best of three cold passes and repeated warm passes, with collection between trials.

| Read | Cold µs | Warm µs |
| --- | ---: | ---: |
| Quest `name` | 4.13 | 0.45 |
| Quest `requiredLevel` | 4.25 | 0.30 to 0.50 |
| Quest `objectives` | 6.88 | 1.30 |
| Npc `spawns` | 10.67 | 2.18 |

The 36-field `Quest.GetAll` pass over 500 quests cost **44.88 µs per quest** cold and
17.83 µs warm. The three-scalar availability shape, `requiredLevel`, `requiredRaces` and
`requiredClasses` over all 4,257 quests, cost **21.46 ms** cold and **4.53 ms** warm. A
fully warmed scalar sweep reached 0.30 µs per read. These meet the timing thresholds, though
the full-row result is close to its 45 µs limit and ordinary cold single-scalar reads do not
improve.

A fixed quest-log-shaped sample read four fields from 25 quests and names, spawn or drop
fields from 30 NPCs, 23 Items and 23 Objects. Three passes, collecting before each and
stopping the collector during the pass, measured:

| Pass | Time | Garbage |
| --- | ---: | ---: |
| Cold | 1.49 ms | 209.4 KB |
| Warm 1 | 0.45 ms | 83.6 KB |
| Warm 2 | 0.43 ms | 83.6 KB |

The integrated Questie Profiler showed the larger practical effect. Two comparable runs of
`CalculateAndDrawAll` fell from 150 and 165 ms to 92 and 97 ms. Its `IsDoable` portion fell
from 60 and 57 ms to 31 and 33 ms. The averages are about **40% faster overall** and **45%
faster in `IsDoable`**.

A controlled reload comparison after materializing all four ID sets reported 8,037 KB for
the retired literal reader and 10,857 KB for the CBOR reader through
`GetAddOnMemoryUsage`. This misses the original resting-memory threshold by 1.8 MB. A
separate allocation probe attributed 1,311 KB to the native-decoded ID arrays and 1,969 KB
to their existence maps. The old `loadstring` allocations were attributed outside
QuestieTDB, so this is partly an ownership-accounting change. The fixed allocation is retained
for the session and creates no recurring garbage. The accepted decision is to keep the
portable compressed CBOR headers and revisit their representation only if client-wide memory
profiling shows pressure.

With Questie itself retaining values returned by the database, the paired acceptance sweep
reported 16,920 KB at rest and 19,399 KB after the three-scalar pass. The **2,479 KB growth**
is below the 3.5 MB row-cache threshold. The higher absolute baseline includes retained
consumer values and is not comparable to the isolated 8,037 KB literal baseline.

The generated Mists artifact was temporarily loaded through the Era-selected TOC after
changing only its `Interface` directive. Reassembly, base64 decode, zlib inflate and CBOR
decode for all four ID headers took **10.36 ms** total, below the 30 ms threshold:

| Header | IDs | Decode |
| --- | ---: | ---: |
| Quest | 17,693 | 1.04 ms |
| Npc | 60,224 | 3.42 ms |
| Item | 80,049 | 4.62 ms |
| Object | 20,326 | 1.27 ms |

The non-enUS check returned `Klaue von Scharfkralle` for quest 2 in deDE and returned its
`objectivesText` as a one-element German table, then restored enUS. A runtime Correction
changed quest 2 `requiredLevel` from 20 to 27 and added quest 4,999,999. Reads, `Exists` and
`GetAllIds(true)` saw both changes. Withdrawing the Correction restored level 20 and removed
the synthetic quest from all three views.
