# 7. Dynamic Correction ownership

Date: 2026-08-26. Status: accepted.

## Context

ADR 0003 Decision 9 exposed a parameterized Correction API for a provider function whose
selection depended on consumer-owned runtime state. That made QuestieTDB understand how one
consumer represented and dispatched state the database does not own. Extending that pattern
would pull consumer settings, schedules, projections, caches, and lifecycle into the provider.

Owner-scoped generic registration already provides the correct boundary: a consumer can build a
Correction from its own state, register it under its own owner, and refresh or clear that layer
without changing base data.

## Decisions

### 1. QuestieTDB selects only from facts it owns

A QuestieTDB-owned Dynamic Correction may depend only on provider-owned data or generic WoW
character/game facts QuestieTDB determines itself: class, race, faction, expansion, and season.

A Correction selected or constructed from consumer-owned runtime state or policy belongs to that
consumer. Display suppression, consumer phase/settings state, projections and caches, and
asynchronous consumer-side repair are examples of consumer ownership even when the resulting
value has the ordinary `id -> field -> value` Correction shape.

### 2. Consumers use the generic owner-scoped registrar

Consumers register these Corrections through `GetRegistrar(owner)`, re-apply after their state
changes, and clear their returned table to remove obsolete overlay values. QuestieTDB does not
add consumer-specific dispatch, schedules, state representations, or convenience APIs.

### 3. The parameterized interface is removed

The manifest category, registration machinery, public API, types, and examples for parameterized
Corrections are removed with no compatibility shim. Provider functions that violate the
ownership boundary are excluded as complete documented function blocks during the pinned source
port. Every non-excluded byte remains subject to exact fidelity comparison.

### 4. Contract Version 1 is corrected in place

QuestieTDB has no tags, releases, or successful publication. The parameterized interface has no
released consumer contract to preserve, so `contractVersion = 1` and
`minSupportedContract = 1` remain unchanged. Adding a compatibility shim would preserve an
unreleased ownership error and is explicitly rejected.

## Consequences

- QuestieTDB has no public or internal parameterized-correction lifecycle.
- Generic owner-scoped Corrections continue to support changed-table re-apply, clearing, stable
  owner precedence, provenance, and unmodified `GetRaw` reads.
- The source port is no longer byte-identical for explicitly excluded functions. Exclusion is
  deterministic and fails on absence or duplication; fidelity remains exact for all other
  content.
- Consumer-specific runtime state remains independently evolvable in the consumer that owns it.

This ADR supersedes the parameterized-correction portion of ADR 0003 Decision 9. Decision 9's
season gate and every other ADR 0003 decision remain current.
