# WoW `table.freeze` and `table.isfrozen`

This document describes the behavior of World of Warcraft's table-freezing APIs, including live-client observations, important metatable caveats, and performance measurements relevant to static addon databases.

## Verification scope and availability

The behavior documented here was tested through `wow-lua-bridge` on this client:

| Property | Value |
|---|---|
| Game variant | Classic Era |
| `WOW_PROJECT_ID` | `2` (`WOW_PROJECT_CLASSIC`) |
| Version | `1.15.9` |
| Build | `68808` |
| Interface | `11509` |
| Build date | `Jul 17 2026` |

Both `table.freeze` and `table.isfrozen` were present as functions. Warcraft Wiki marks them as additions from the [12.0.5 API wave](https://warcraft.wiki.gg/wiki/API_table.freeze). Their presence in Era strongly suggests that the APIs are part of the modern shared client runtime and are available in the other currently updated WoW variants. Only the Era client above was directly verified, however.

The `C_TableUtil` namespace also existed on this client, but `C_TableUtil.freeze` and `C_TableUtil.isfrozen` were both `nil`. Only the `table.freeze` and `table.isfrozen` paths were live-verified; code should not assume that `C_TableUtil` aliases are exported.

Standard Lua 5.1 does not provide these functions. Capability detection remains useful for older clients, standalone Lua tools, and test environments:

```lua
local freeze = table.freeze

if freeze then
    freeze(database)
end
```

A compatibility guard means that the table remains mutable when the API is absent. Code that requires enforced immutability should instead establish a minimum supported client or provide an appropriate test-environment substitute.

## API summary

```lua
table.freeze(value)
local frozen = table.isfrozen(value)
```

Both functions require a table. Passing `nil`, a number, or another non-table value raises a normal bad-argument error, for example:

```text
bad argument #1 to 'freeze' (table expected, got nil)
bad argument #1 to 'isfrozen' (table expected, got number)
```

On the tested client:

- `table.freeze(value)` returned the same table object.
- Calling `table.freeze` repeatedly on the same table succeeded and behaved idempotently in practice on this build.
- `table.isfrozen(value)` returned `true` after freezing and `false` for an ordinary mutable table.
- There was no `table.thaw` or `table.unfreeze` function.

The supplied API description does not document a return value for `table.freeze`, so code should treat it as a side-effecting operation and not depend on the observed same-table return unless that behavior is formally guaranteed for its target clients.

## What freezing enforces

Freezing marks the existing table object as read-only. It does not copy the table.

```lua
local values = {
    first = 1,
}

table.freeze(values)

print(values.first)              -- 1
print(table.isfrozen(values))    -- true
```

Normal reads continue to work, including indexing, `rawget`, iteration, length operations, and read-only table-library functions such as `table.concat`.

Without a `__newindex` escape path, all of these modifications failed in live testing:

- Replacing an existing value
- Adding a new value
- Deleting a value by assigning `nil`
- Calling `rawset`
- Calling `table.insert`, `table.remove`, or `table.sort`
- Replacing the table's metatable with `setmetatable`

The observed errors were:

```text
attempted to perform indexed assignment on a frozen table
attempted to replace metatable of a frozen table
```

A plain table still reported `getmetatable(value) == nil` after freezing, while `rawset` was nevertheless blocked. This is consistent with a VM-level frozen flag rather than an ordinary Lua metatable wrapper.

### Freezing is shallow

Only the supplied table is frozen. Referenced tables remain mutable:

```lua
local inner = {
    value = 1,
}

local outer = {
    inner = inner,
}
table.freeze(outer)

inner.value = 2                 -- Allowed
outer.inner = {}                -- Error

print(table.isfrozen(outer))    -- true
print(table.isfrozen(inner))    -- false
```

Nested tables must be frozen individually when the entire value tree is intended to be static.

### The metatable object is not frozen

Freezing prevents replacing a table's metatable, but it does not freeze the attached metatable object:

```lua
local metatable = {
    marker = "before",
}
local value = setmetatable({}, metatable)

table.freeze(value)
metatable.marker = "after"     -- Allowed

print(getmetatable(value).marker) -- "after"
```

If the metatable's own entries must remain fixed, finish configuring it and freeze it separately:

```lua
local metatable = {
    __index = defaults,
}
local value = setmetatable({}, metatable)

table.freeze(defaults) -- If this owned table is also intended to be static
table.freeze(metatable)
table.freeze(value)
```

Freezing the metatable protects only its entries. Its behavior can still depend on mutable referenced tables such as `defaults`, or on mutable external state captured by function metamethods. Freeze all owned reachable state that is intended to be static; freezing the metatable alone does not guarantee behaviorally immutable lookups.

A table with a protected metatable (`__metatable = "locked"`) could still be frozen. Weak tables could also be frozen and retained their weak-table mode.

## Critical `__newindex` behavior

A frozen table with `__newindex` is not necessarily logically immutable, and an assignment is not guaranteed to raise an error.

On the tested client, freezing changed the usual assignment routing. Both assignments to existing raw keys and assignments to missing keys were passed to `__newindex`:

```lua
local redirectedWrites = {}
local value = setmetatable({
    existing = 1,
}, {
    __newindex = redirectedWrites,
})

table.freeze(value)

value.existing = 2
value.added = 3

print(rawget(value, "existing"))       -- 1
print(rawget(value, "added"))          -- nil
print(redirectedWrites.existing)       -- 2
print(redirectedWrites.added)          -- 3
```

This differs from ordinary Lua behavior. Before freezing, assignment to the existing raw key bypassed `__newindex` and changed the raw value. After freezing, the same assignment was redirected and the frozen table remained unchanged.

The same behavior was observed with a `__newindex` function. The assignment completed successfully when the function logged, ignored, or redirected the write. Attempting to write back into the frozen table from that function still failed:

```lua
local value = setmetatable({}, {
    __newindex = function(self, key, newValue)
        rawset(self, key, newValue) -- Error: self is frozen
    end,
})

table.freeze(value)
value.example = true
```

Because the metatable object remains mutable, adding `__newindex` to an already attached metatable after freezing caused subsequent assignments to be redirected in live testing. Removing it caused assignments to fail again. This late-mutation behavior goes beyond the documented pre-existing-`__newindex` case and should be treated as an implementation detail rather than a compatibility promise.

Consequences:

- Successful assignment only means the metamethod accepted the operation; it does not mean the frozen table changed.
- A `__newindex` table or function can mutate external state.
- Freeze the metatable separately if late changes to its `__newindex` entry must be prevented; separately consider any mutable state referenced by that metamethod.
- Avoid `__newindex` entirely when the desired contract is that every attempted assignment raises an error.

The existing-key and missing-key routing behavior was repeated 100 times without a mismatch on the tested build. That establishes the current behavior, not a guarantee for future clients.

## Ownership, addon taint, and lifetime

The API documentation states that tainted addon code may freeze only tables created by the same addon making the call. This prevents one addon from freezing another addon's or Blizzard's shared state for that table's lifetime in the current UI session. Freezing does not remove taint, make a value secure, or otherwise cleanse its provenance.

The cross-addon failure path was not tested live. A safe test requires a cooperating second addon that deliberately provides a disposable table; freezing a real table owned by another addon would be irreversible for that UI session and potentially disruptive.

Fresh disposable tables returned through the tested `C_DateAndTime` API, `CopyTable`, `CreateFromMixins`, and `securecallfunction` factory paths could all be frozen by the bridge addon. This does not prove that an existing table owned by another addon can be frozen; those returned tables were created in response to the calling addon's operation.

Freezing applies to a runtime table object. There is no exposed operation to reverse it during that object's lifetime. A UI reload recreates Lua state and addon tables, so initialization code should freeze the recreated data again. The reload behavior was not deliberately exercised during these tests.

## Deep-freezing a static database

For a known acyclic database made from plain tables, a direct recursive traversal is simple and performs no explicit per-node Lua-table allocation. Localizing frequently used globals produced a measurable improvement in the live benchmarks:

```lua
local pairs = pairs
local type = type
local freeze = table.freeze

local function DeepFreeze(database)
    for _, value in pairs(database) do
        if type(value) == "table" then
            DeepFreeze(value)
        end
    end

    freeze(database)
    return database
end
```

Freezing children before their parent keeps the traversal straightforward. The function assumes:

- No cycles exist.
- Only table values need recursive freezing.
- Metatable objects do not need recursive freezing.
- Repeated references to the same child are uncommon or small enough to revisit.

Repeated `table.freeze` calls behaved idempotently in practice on the tested build, so repeated references remained correct there, but the shared subtree is traversed once per reference. A cycle would recurse indefinitely. Like other recursive Lua implementations, these helpers are also limited by available call-stack depth.

### Cycle-safe variant

For an arbitrary object graph, track visited tables explicitly:

```lua
local pairs = pairs
local type = type
local freeze = table.freeze

local function DeepFreeze(database, seen)
    seen = seen or {}

    if seen[database] then
        return database
    end
    seen[database] = true

    for _, value in pairs(database) do
        if type(value) == "table" then
            DeepFreeze(value, seen)
        end
    end

    freeze(database)
    return database
end
```

This version successfully froze a self-referencing table while preserving the cycle. Its `seen` table adds temporary allocation and lookup overhead.

A fresh graph can instead be frozen before recursion and use `table.isfrozen` as its visited marker. That avoids the `seen` allocation and handles fresh cycles, but it is unsafe for a partially frozen graph: encountering a previously frozen parent skips any mutable descendants. On the generated 4-way, depth-5 tree with 1,365 tables and 4,094 entries, a 20-traversal median batch measured 31.36 ms for `CopyTable` and 32.71 ms for this freeze-first/`isfrozen` variant, approximately 4.3% slower in that smoke run.

The examples recurse through table values to match the common addon-database shape and WoW's `CopyTable` behavior. To inspect table-valued keys too, replace the value-only loop inside the cycle-safe helper above with:

```lua
for key, value in pairs(database) do
    if type(key) == "table" then
        DeepFreeze(key, seen)
    end
    if type(value) == "table" then
        DeepFreeze(value, seen)
    end
end
```

That performs more type checks and may freeze objects that callers do not consider owned by the database. Establish ownership rules before using graph-wide behavior.

## Comparison with `CopyTable`

The tested WoW implementation of `CopyTable` is an ordinary recursive Lua function:

```lua
function CopyTable(settings, shallow)
    local copy = {}

    for key, value in pairs(settings) do
        if type(value) == "table" and not shallow then
            copy[key] = CopyTable(value)
        else
            copy[key] = value
        end
    end

    return copy
end
```

Both copying and deep-freezing must perform Lua recursion, iteration, and type checks. Copying additionally allocates a new table at every level and writes every copied entry. Deep-freezing instead invokes the native `table.freeze` once per table.

This `CopyTable` implementation also has semantic differences:

- It does not copy metatables.
- It duplicates shared child references instead of preserving alias identity.
- It recurses indefinitely on cycles.
- It recursively copies table values, but table-valued keys remain references to the original key objects.
- A shallow copy leaves all child tables shared.

Copying a frozen table worked because reads remain available, and the returned copy was mutable and not frozen. This is useful when a consumer needs an editable copy of static database information.

If the original table must remain mutable while a separate immutable snapshot is needed, both operations are required:

```lua
local immutableSnapshot = DeepFreeze(CopyTable(database))
```

This necessarily traverses the structure twice.

## Performance measurements

These are live-client smoke measurements, not universal benchmarks. Timings depend on client build, hardware, UI load, table shape, allocator state, and the timing order.

The generated sources modeled numeric-ID databases with record tables and nested record groups. Equivalent inputs for deep-freezing were prepared outside the timed region because freezing is irreversible. Garbage collection was requested before timed batches, results were retained during each batch, and elapsed time was measured with `debugprofilestop`.

### Localized copy versus localized deep freeze

The comparison used seven runs per generated shape. The reported duration is the median time for a batch of three complete traversals, not one traversal:

| Generated database shape | Tables | Entries | Batch iterations | Localized `CopyTable` | Localized deep freeze | Freeze difference |
|---|---:|---:|---:|---:|---:|---:|
| 2,000 records with 10 fields | 2,001 | 22,000 | 3 | 18.22 ms | 14.72 ms | 19.2% faster |
| 500 nested records | 2,501 | 14,500 | 3 | 13.85 ms | 11.53 ms | 16.7% faster |

Approximate time per traversal was therefore 6.07 ms versus 4.91 ms for the first shape, and 4.62 ms versus 3.84 ms for the second. Percentage differences were calculated from the unrounded medians; the displayed times are rounded to two decimals.

Operations ran sequentially in the live UI, so residual ordering, allocator, and client-load effects remain despite garbage collection before each timed batch. The percentages should be read as approximate smoke results.

Broader generated-shape tests used five runs per shape and put simple deep-freezing in the same performance class as copying. It was commonly about 8-20% faster, but one noisy, table-heavy sample measured about 2% slower. The reliable conclusion is that avoiding the copy provides a modest CPU improvement, not an order-of-magnitude improvement.

### Effect of localizing functions

A separate test used 3,000 records, 3,001 tables, 33,000 entries, three traversals per batch, and nine runs per variant. The table reports median batch duration:

| Deep-freeze implementation | Median batch time | Change from globals |
|---|---:|---:|
| Global `pairs`, `type`, and `table.freeze` | 23.21 ms | Baseline |
| Local `pairs` | 22.21 ms | 4.3% faster |
| Local `pairs` and `type` | 21.73 ms | 6.4% faster |
| Local `pairs`, `type`, and `table.freeze` | 21.41 ms | 7.8% faster |

That final difference was approximately 0.6 ms per complete traversal for this generated database. Localizing the same lookups in `CopyTable` produced a smaller improvement of roughly 1.5-2.2% in the tested shapes.

### Copying and then freezing

Across the five-run generated-shape smoke tests, `DeepFreeze(CopyTable(database))` measured approximately 1.8-2.0 times the cost of `CopyTable` alone. This is expected because it performs both full traversals. If ownership permits freezing the original static database, doing so avoids the copy entirely.

### Allocation measurements

`collectgarbage("count")` was sampled around operations on a generated tree with 1,365 tables and 4,094 entries:

| Operation | Measured Lua heap increase |
|---|---:|
| `CopyTable` | approximately 357 KiB |
| Simple acyclic deep freeze | 0 KiB measured |
| Cycle-safe deep freeze with `seen` | approximately 112 KiB temporary |

The `seen` allocation becomes collectible after the operation. The copied tables remain allocated while the copy is retained. These figures are allocator smoke measurements rather than precise retained-memory profiles, but they illustrate the principal advantage of freezing static data: substantially less allocation and subsequent garbage-collection pressure.

## Stability smoke tests

The following loops completed successfully on the verified Era build:

| Test | Result |
|---|---|
| Create, freeze, check, and read 10,000 tables | Exact expected checksum; approximately 5.28 ms |
| Attempt 1,000 writes under `pcall` | Zero unexpected successes; approximately 3.05 ms |
| Repeat frozen-table `__newindex` routing 100 times | All raw values and redirected writes matched expectations |

The 10,000-iteration timing includes table creation, freezing, `table.isfrozen`, and reading. The failed-write timing includes `pcall` and error creation. Neither is a standalone microbenchmark of the native freeze operation.

These tests found no inconsistent behavior or runtime instability on one client build. They do not guarantee identical behavior across all WoW variants or future versions, especially for edge cases such as `__newindex` routing.

## Recommended use

`table.freeze` is a good fit for:

- Private, fully constructed static databases
- Constant lookup tables
- Immutable snapshots returned to consumers
- Internal records that should fail fast on accidental mutation

Use it cautiously or avoid it for:

- Public API tables that consumers traditionally decorate or monkey-patch
- Mixins and method tables intended for hooks or extensions
- Plugin registries
- Shared library state
- Tables whose metatables or nested values are still being configured

For an acyclic static database owned by the addon:

1. Finish all corrections and compilation first.
2. Deep-freeze nested value tables once, using localized `pairs`, `type`, and `table.freeze`.
3. Avoid `__newindex` when attempted writes must reliably fail.
4. Freeze an attached metatable to lock its own entries, and separately freeze any owned state its metamethods reference when that state must also remain fixed.
5. Reapply freezing whenever runtime tables are recreated.
6. Use `CopyTable` only when a caller genuinely needs a mutable independent copy.
7. Retain capability detection where non-WoW Lua tools, tests, or older clients remain supported.

---

## Ownership: measured in a live client, and it changes the conclusion

Classic Era 1.15.9, read through QuestieTDB in Baked mode.

`table.freeze` **enforces ownership**. It raises unless the table's owner matches the calling
function's owner:

```
attempted to freeze a table not owned by the calling function
(expected 'QuestieTDB', got '*** ForceTaint_Strong ***')
```

That interacts badly with lazy decoding, which is the whole point of a TOC metadata store. A
table field is materialised by `loadstring` **inside whatever execution context asked for it**,
and that context owns the result. The caller is never QuestieTDB — it is the consumer — so the
owner never matches.

Measured over 200 consecutive table reads from a consumer's context:

| | |
| --- | ---: |
| `table.freeze` present | yes |
| tables successfully frozen | **0** |
| freeze attempts refused | **113** |

Before this was handled the refusal propagated out of the getter: the read threw, the value was
never cached, and it threw again on every call. `shared.Freeze` now degrades — it returns the
value unfrozen and counts the refusal in `LibQuestieDB.shared.freezeRefused`.

**So the value-ownership guarantee does not currently hold in Baked mode.** The measurements
higher up this document (0 KiB, 8–20% faster) are real, but they were taken freezing tables the
measuring code owned. They do not carry over to values decoded on a consumer's behalf.

Three ways out, none of them free:

1. **Accept it.** Values are shared and mutable; ownership is convention, enforced offline by
   the harness in `emulator/freeze.lua` and its mutation audit. Costs nothing, guarantees
   nothing at runtime.
2. **Decode eagerly at load, inside QuestieTDB's own context**, then freeze. Restores the
   guarantee and defeats lazy decoding — which is the reason this storage format was chosen.
   Plausible for Source mode, where base data is one `loadstring` per entity type; ruinous for
   Baked mode.
3. **Freeze only what QuestieTDB itself creates** — the composed Correction Overlay, which is
   built during recomposition in QuestieTDB's context. Partial, cheap, and honest about its
   scope.

**Resolved — twice over — on 2026-08-18** (see
[`client-metadata-probes.md`](./client-metadata-probes.md) §3 and 6b):

- The refusals were root-caused live: `table.freeze` is gated on taint *ownership*, and every
  table a `loadstring` chunk builds belongs to `*** ForceTaint_Strong ***`, not to the addon —
  so option 2's "inside QuestieTDB's own context" could never have worked as written. The
  working mechanism is the inverse: perform the deep freeze **inside** loadstring-compiled
  code (a single shared helper, itself compiled via `loadstring`, freezes across separately
  compiled chunks — validated in-client, nested tables fully frozen).
- And then the question became moot: ADR 0003 Decision 10 (revised) retired frozen shared
  values entirely. Re-executing the cached compiled chunk returns a fresh mutable copy per
  read at 0.13–1.8 µs for typical shapes, which is Questie's existing per-call semantics with
  no consumer audit at all. Freezing now applies only to QuestieTDB-internal shared
  structures, where addon ownership makes it real — a strict superset of option 3.

The validated in-chunk freeze pattern stays recorded in the probes document should shared
frozen values ever return.
