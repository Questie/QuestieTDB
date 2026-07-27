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
A long Metadata field split into numbered parts and reassembled before decoding.
_Avoid_: Combined parts, split value

**Generation**:
The offline process that turns raw entity data plus Static Corrections into a TOC metadata store.
_Avoid_: Compilation, build, cooking

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
A Correction whose applicability cannot be known before Generation — because it depends on
runtime state such as faction, season, expansion, or user settings. Always applied at query time.
_Avoid_: Runtime correction, conditional fix

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
The runtime cache holding decoded Metadata field values after first access.
_Avoid_: Getter cache, Lua cache

**Frozen value**:
A table returned from an entity read that the database owns and callers must not modify.
A caller needing a mutable working copy takes one explicitly.
_Avoid_: Read-only table, immutable table, const

**l10n overlay**:
The optional localization layer wrapping selected Named getters for the active locale.
_Avoid_: Localization DB, translation patch

## Boundary with Questie

**QuestieTDB owns what is true about game entities. Questie owns what to do with that truth.**

A Correction fixes what is true — a wrong coordinate, a missing prerequisite. Deciding that
an entity should not be shown is a consumer policy, not a database fact, and belongs to the
consumer. A quest that is a duplicate or unobtainable still exists, and another consumer may
legitimately want it.

Questie is a consumer. Storage vocabulary stops here — Questie has no terms for Metadata
fields, Chunked metadata values, or Generation.

Questie's **Runtime Override** is retired in favour of **Correction Overlay**; its former
definition referred to reading compiled data, and compilation no longer exists.
