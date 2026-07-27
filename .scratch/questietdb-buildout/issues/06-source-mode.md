# 06 — Source mode

**What to build:** A contributor clones the repo, links it into their AddOns folder, and has a working database — with no download, no generated artifact, and no Lua toolchain. Reads resolve from raw entity data instead of TOC metadata, behind the identical getter surface.

The client chooses the mode for free: a suffixed TOC wins when present, and the base TOC is used when it is not.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] The base TOC loads raw entity data and serves every getter that baked mode serves
- [ ] A clean clone with no generated artifact works in-game with no extra steps
- [ ] Generating an artifact switches the same folder to baked mode with no code change
- [ ] Only the field-read and ID-list functions differ between modes; everything else is shared
- [ ] The active mode is unmistakable in-game — source mode shows a persistent indicator, not just a login message
- [ ] Deleting a Static Correction is observable in source mode, since corrections apply to base data rather than over it
