# Two read modes: source and baked

Generation is an offline process, so a correction contributor would otherwise need a Lua
toolchain before they could see a change in-game. QuestieTDB therefore ships two read
backends behind one getter API: **source mode** resolves reads from raw entity data with all
corrections applied live, and **baked mode** resolves them from the generated TOC metadata
store. The WoW client selects between them for free — it prefers a flavour-suffixed `.toc`
and falls back to the base `.toc` only when none exists, so a fresh clone with no generated
artifact is a working development environment.

## Consequences

- A contributor clones, junctions the folder into `AddOns`, edits a correction, and reloads.
  No download, no toolchain.
- Only `readField` and `getAllIds` differ between modes. Getters, correction overlay, field
  cache, defaults, l10n overlay, and schema are single-implementation.
- Source mode and the generator apply static corrections through the same path, so
  "what I see in dev is what ships" follows from shared code rather than from a test.
- Deleting a correction behaves correctly, because source mode applies corrections to base
  data rather than layering over already-baked data.
- **The source/baked equivalence test never retires.** With two permanent backends it is the
  load-bearing check in the system, not a migration artifact.
- Mode selection is implicit, so it must be unmistakable in-game: source mode carries a
  permanent visible indicator, not just a login message.
