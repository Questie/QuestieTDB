# 12. Objective-ordering hint applicability

Date: 2026-09-05. Status: accepted.

## Context

Questie's correction sources assign `ObjectiveFirst` hints when their Lua files load. Runtime
Correction registration gates run later, so they cannot prevent hints from an inapplicable
expansion or season from leaking into the published tables. In the pinned Questie source, the
Classic TOC loads SoD correction files unconditionally even when SoD is inactive.

## Decision

QuestieTDB preserves the hint values authored in the pinned correction sources, but applies its own
explicit applicability boundary when those files load. Base-expansion hints are cumulative. SoD
hints require Vanilla with season 2 active, and Titan Reforged hints require Wrath with season 109
active. Plain Vanilla therefore excludes SoD hints despite Questie's unconditional file loading.

Applicability controls only the five `ObjectiveFirst` hint tables. Seasonal files and their Dynamic
Correction providers may still ship and load so they are available when their season becomes
active. QuestieTDB does not split the seasonal artifact or edit the copied correction sources.

Source, Baked, and Static-Correction-stripped packages publish identical applicable hint contents.
The existing public shape remains five consumer-must-not-mutate `{ [questId] = true }` tables.

## Consequences

Objective-ordering hints follow the same expansion and season facts as the data they describe,
without changing Correction registration or copied source ownership. Fidelity checks compare all
five tables with pinned source contents under this explicit applicability policy rather than with
Questie's incidental unconditional SoD load effect.
