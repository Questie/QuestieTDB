# 14 — Entity localization overlay

**What to build:** A player on a non-English client sees localized quest, NPC, item, and object names, and switching locale takes effect without regenerating anything. Translations overlay the base English data rather than replacing it.

This is what removes the recompile-on-locale-change that Questie has today.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] All nine non-English locales are extracted from Questie's per-locale lookup files
- [ ] Extraction handles the client-locale guard those files open with, so every locale can be read in one generation run
- [ ] Translations are stored per entity and field, and only the requested locale is decoded on access
- [ ] Missing translations fall back to the base English value
- [ ] Changing locale at runtime takes effect without regeneration and without a database rebuild
- [ ] Entity getters behave identically when no localization data is present
- [ ] Field coverage matches what Questie translates today, and no more
