# 16 — CI, release, and bootstrap

**What to build:** Every commit produces a verified, downloadable database, and a contributor can refresh their local copy with one command instead of regenerating. Releases are reproducible and identifiable by content, not just by tag.

**Blocked by:** 05, 13

**Status:** ready-for-agent

- [ ] CI generates, verifies, and validates every flavor on every commit
- [ ] Source/baked equivalence runs in CI and blocks merge on failure
- [ ] Every commit publishes a pre-release; a full release can be triggered deliberately
- [ ] Releases carry a machine-readable manifest with per-artifact checksums, the producing commit, and the contract version
- [ ] A bootstrap script installs artifacts into a contributor's addon folder, verifying checksums before installing
- [ ] The bootstrap needs no Lua — it is a downloader
- [ ] Generated artifacts are never committed to the repository
- [ ] A consumer can pin an exact release for reproducible builds
