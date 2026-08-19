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
