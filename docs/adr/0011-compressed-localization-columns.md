# 11. Compressed localization columns

Date: 2026-09-03. Status: accepted 2026-09-03.

## Context

The first CBOR storage revision retained one raw metadata value per translated entity field,
joining all nine locales with a separator. Vanilla localization occupied 11.99 MiB across 44,859 directives; Mists
occupied 57.48 MiB across 198,947. A non-enUS read fetched the whole joined value, scanned to
one segment, and compiled translated `objectivesText` as a Lua literal. enUS decoded nothing,
but every client still retained the uncompressed metadata.

Two block layouts were tested in Classic Era 1.15.9 build 69547. ID-keyed locale maps retained
5.3 to 6.3 MiB on Vanilla and 27.9 to 32.5 MiB on Mists. Field columns aligned with the existing
base ID list retained 3.2 to 4.1 MiB on Vanilla and 14.2 to 18.4 MiB on Mists. The column layout
also compressed better.

## Decisions

### 1. One compressed block per locale and entity type

`X-l10n-<locale>-<Type>` holds base64 of zlib-compressed deterministic CBOR. The entity type
must come last because the client interprets a final `-deDE`-style suffix as a localized TOC
directive and hides it when another locale is active. A block is an array
of compact localization field columns indexed by position in `X-<Type>-IDS`. A nil hole means
that field falls back to base English. The blocks repeat no entity IDs.

`X-l10n-Version: 1` declares the store. The old per-entity keys, locale separator, list literals
and localization ID lists are removed.

### 2. Only the active locale enters Lua memory

enUS decodes no localization blocks. A non-enUS client decodes its four available type blocks
during addon load and retains them for the session. Locale changes decode replacement blocks
first, swap them atomically, then invalidate entity caches.

Providers find positions with a same-ID and sequential-position fast path, followed by binary
search for random access. They use the backend's base ID list rather than composed IDs, so a
Correction-added entity has no accidental translation.

### 3. Existing read contracts stay unchanged

Corrections outrank localization. Missing translations fall back to base values. CBOR produces
translated objective lists with their final type, and shared.lua's copy producer still returns
a fresh mutable table on every read.

### 4. Localization ships in contract version 2

The entity and localization storage changes are unreleased and ship together as contract 2.
The public read interface is unchanged and `minSupportedContract` remains 1.

## Consequences

The production artifacts reduce Vanilla localization to 4.21 MiB and Mists to 19.80 MiB,
about 65% fewer directive bytes. A deDE load retained 3.26 MiB on Vanilla and 15.09 MiB on
Mists. Decode cost was 16.36 ms and 81.41 ms respectively, paid on the loading screen and only
for non-enUS clients.

Cold translated reads improved in the live Vanilla client by 29% for quest names, 42% for NPC
names, 35% for item names, 38% for object names and 52% for quest objectives. Warm scalar reads
remain ordinary cache hits.

The fixed active-locale heap is accepted. On Mists it is substantial, but the compressed TOC
removes roughly twice as many metadata bytes as the decoded columns retain. Client-wide memory
measurement remains the final proof of the net process-memory result.
