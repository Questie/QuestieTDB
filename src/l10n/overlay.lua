-- src/l10n/overlay.lua
--
-- The optional localization layer wrapping selected Named getters for the active locale.
--
-- Locale-joined values live in the TOC metadata store alongside entity data. Because segments
-- are only extracted on access, a German user never touches the other eight locales' strings
-- and they never cost Lua memory or GC pressure — which is what makes keeping all nine
-- locales in one store the right call rather than splitting l10n into its own addon.
--
-- Filled in by ticket 14. Until then entity getters behave identically to having no
-- localization data present, which is the required fallback anyway.

local _, LibQuestieDB = ...

local overlay = {
  currentLocale = "enUS",
  onLocaleChanged = {},
}

--- Changing locale at runtime takes effect without regeneration and without a database
--- rebuild — this is what removes Questie's recompile-on-locale-change.
function overlay.SetLocale(locale)
  overlay.currentLocale = locale
  for _, callback in ipairs(overlay.onLocaleChanged) do callback(locale) end
end

LibQuestieDB.l10n = overlay

return overlay
