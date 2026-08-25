# QuestieTDB

The database Questie consumes. Stores entity data as WoW addon TOC metadata, readable at
runtime with no file I/O, and owns the offline generator that produces it.

QuestieTDB is a separate project from Questie, with its own release cycle and consumers.
Its domain is nonetheless *Questie's data model* — the schema, including Questie-specific
fields, is what QuestieTDB stores and serves.

## Language

### Storage

**TOC metadata store**:
Addon `.toc` metadata used as string-backed storage for lazy entity field access.
_Avoid_: TOC DB, metadata DB, file I/O replacement

**Metadata field**:
One stored value addressed by entity ID and positional field index inside the TOC metadata store.
_Avoid_: Metadata row, TOC row

**Chunked metadata value**:
A long Metadata field split into numbered parts and reassembled before decoding. Parts
never begin or end with client-trimmable bytes — the client strips edge whitespace from
metadata values (measured; see `docs/client-metadata-probes.md`).
_Avoid_: Combined parts, split value

**Raw coordinate**:
An authored or Derived Pass spawn/waypoint coordinate preserved without legacy compiler-grid
quantization in both Source and Baked mode (ADR 0006).
_Avoid_: Unquantized coordinate, full-precision coordinate

**Generation**:
The offline process that turns raw entity data plus Static Corrections into a TOC metadata store.
_Avoid_: Compilation, build, cooking

**Derived Pass**:
A deterministic transform over corrected entity data, run before storage, in both Generation
and Source mode. Distinct from a Correction, which is data (`id` to field index to value) — a
Derived Pass is code, and may read one entity type while writing another. Reproduces a
transform Questie applies between corrections and compilation, so that reads match the
database a player actually receives (ADR 0004).
_Avoid_: Preprocess, precompile, postprocess, pipeline stage

**Support data**:
Game reference data consumed as whole tables rather than through the TOC metadata store —
zone mappings, quest XP, drop tables, faction templates. Shipped as plain Lua files.
_Avoid_: Auxiliary data, helper data, lookup data

**Source mode**:
The runtime state where entity reads resolve from raw entity data with all Corrections
applied live, because no generated TOC metadata store is present.
_Avoid_: Dev mode, debug mode, uncompiled

**Baked mode**:
The runtime state where entity reads resolve from a generated TOC metadata store, with
Static Corrections already folded in.
_Avoid_: Release mode, compiled mode, production

### Corrections

**Correction**:
A change to entity data, expressed as entity ID to field index to value.
_Avoid_: Fix, patch, workaround, override

**Static Correction**:
A Correction folded into the TOC metadata store during Generation. Never shipped to end users.
_Avoid_: Compile-time correction, baked correction

**Dynamic Correction**:
A Correction applied at query time. QuestieTDB-owned Dynamic Corrections may depend only on
provider-owned data or generic character/game facts QuestieTDB determines itself: class, race,
faction, expansion, and season. A consumer registers its own Dynamic Corrections for
consumer-owned runtime state or policy.
_Avoid_: Runtime correction, conditional fix

**Gated Dynamic function**:
A correction function that registers only while its named runtime condition holds — the
SoD and Titan Reforged season gates. An unrecognized gate name stays closed.
_Avoid_: Conditional registration, feature flag

**Correction Overlay**:
The composed query-time layer of Dynamic Corrections that entity reads resolve through.
_Avoid_: Runtime override, override table, merged correction

### Access

**Entity global**:
A public table exposing one entity database, such as quests or NPCs.
_Avoid_: Namespace, module object

**Named getter**:
A function on an Entity global returning one field by its canonical field name.
_Avoid_: Accessor, field helper

**Generic getter**:
A function on an Entity global returning one field by positional field index.
_Avoid_: Index getter, raw getter

**Decoded field cache**:
The runtime cache behind the getters: scalar values are cached directly; table fields
cache a Producer.
_Avoid_: Getter cache, Lua cache

**Producer**:
The cached mechanism a table read executes to return a value — a compiled chunk of the
stored literal in Baked mode, a deep-copy closure for Source, overlay, and translated
values. Executing it costs 0.13–1.8 µs for typical shapes (measured).
_Avoid_: Factory, thunk, generator (collides with the offline Generation vocabulary)

**Caller-owned value**:
Every table returned from an entity read is a fresh, mutable, deeply independent copy the
caller owns — Questie's original per-call semantics (ADR 0003 D10, revised). `table.freeze`
applies only to QuestieTDB-internal shared structures.
_Avoid_: Frozen value (the retired original contract), shared value, borrowed table

**Composed enumeration**:
`GetAllIds` and `Exists` answering over the union of the backend's entities and those the
Correction Overlay adds — an added entity is readable, enumerable, and exists, all three.
_Avoid_: Merged id list, extended pointers

**l10n overlay**:
The optional localization layer wrapping selected Named getters for the active locale.
The Correction Overlay outranks it: a corrected field skips its lookup (ADR 0003 D8).
_Avoid_: Localization DB, translation patch

### Verification

**Equivalence sweep**:
The gate proving Source and Baked modes read identically for every id × field across every
public read form, ending in a Self-proof.
_Avoid_: Parity test, mode test

**Self-proof**:
A gate's built-in demonstration that it fails when it should — an injected divergence or
corrupted byte that must be detected exactly once. A gate without one is decoration.
_Avoid_: Sanity check, canary

**Reconstruction gate**:
`reconstruct.lua` — re-derives every data directive with the current generator and
compares against the artifact as exact bytes, localizing mismatches to named keys.
_Avoid_: Round-trip test (that is `verify.lua`, which decodes)

**Golden snapshot**:
The committed per-id hashes of accepted composed reads (`tools/differential/golden/`),
checked per flavor in CI. The frozen mirror that catches defects where generator and
source mode agree with each other while both diverge from upstream — the class the
retired `-pi` sibling's independence caught during the merge program.
_Avoid_: Baseline (that word belongs to the validators), reference dump

**Compiler comparison adapter**:
The migration-only projection that converts QuestieTDB base coordinates to Questie's legacy
12-bit read values immediately before the compiler differential. It never runs in Generation
or runtime reads and retires with the compiler oracle (ADR 0006).
_Avoid_: Production quantizer, compatibility mode

**Persona**:
The emulator's mocked client identity — faction, race, class, season — letting gated and
faction-differentiated correction branches execute offline.
_Avoid_: Test profile, mock player

## Boundary with Questie

**QuestieTDB owns what is true about game entities. Questie owns what to do with that truth.**

A Correction fixes what is true — a wrong coordinate, a missing prerequisite. QuestieTDB may
select a Dynamic Correction only from provider-owned data or generic character/game facts it
determines itself: class, race, faction, expansion, and season. A Correction selected or
constructed from consumer-owned runtime state or policy belongs to that consumer.

Display suppression, consumer phase/settings state, projections and caches, and asynchronous
repair of consumer data therefore remain consumer-owned. A quest that is duplicate or
unobtainable still exists, and another consumer may legitimately want it.

Questie is a consumer. Storage vocabulary stops here — Questie has no terms for Metadata
fields, Chunked metadata values, or Generation.

Questie's **Runtime Override** is retired in favour of **Correction Overlay**; its former
definition referred to reading compiled data, and compilation no longer exists.
