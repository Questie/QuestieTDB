# 05 — All five client flavors

**What to build:** A player on any supported client gets the right database. Generation produces one artifact per flavor, and the client picks it automatically through TOC suffix precedence.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Artifacts generate and verify for all five clients, using the **modern underscore
      suffixes**: `_Vanilla`, `_TBC`, `_Wrath`, `_Cata`, `_Mists` — not the prototypes'
      legacy `-BCC` / `-WOTLKC`
- [ ] Each flavor reads only its own expansion's source data
- [ ] Interface versions are correct per flavor
- [ ] Each client loads its own suffixed TOC, and a client with no matching suffix falls back
      to the base TOC in source mode
- [ ] The suffixed TOCs are gitignored — generated artifacts are never committed
- [ ] `_Wrath` serves Titan Reforged as well as Wrath Classic
- [ ] Generating everything stays within a time budget a contributor will tolerate on each run
