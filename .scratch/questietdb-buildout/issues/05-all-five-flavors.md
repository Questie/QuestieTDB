# 05 — All five client flavors

**What to build:** A player on any supported client gets the right database. Generation produces one artifact per flavor, and the client picks it automatically through TOC suffix precedence.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Vanilla, BCC, WOTLKC, Cata, and Mists artifacts all generate and verify
- [ ] Each flavor reads only its own expansion's source data
- [ ] Interface versions are correct per flavor
- [ ] The suffixed TOCs are gitignored — generated artifacts are never committed
- [ ] Generating everything stays within a time budget a contributor will tolerate on each run
