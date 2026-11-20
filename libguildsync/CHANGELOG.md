# Changelog

## MINOR 2 (2026-11-20)
- New module `Addon` (GuildGames feature 019): `Addon.Setup(addon, addonName, { name, prefix, command, fallbackVersion,
  color })` sets an addon's identity (build flag, version, title, prefix, SavedVariables, frame names, slash commands,
  Print), warns about a TOC that saves another global, and registers the slash dispatcher; `Addon.AddDiagnosticCommands`
  adds `comm`, `hello`, `debug`, `trace`. Both addons used to carry a copy. Additive: a MINOR 1 copy loaded first is
  upgraded in place and gains the module.

## MINOR 1 (2026-11-18)
- First version, extracted from TalentShare 0.6.0 (feature 015): Utility, Log, Trace, Codec, Guard, Locale, Events,
  Sync (generic record-pull engine), Guild, Channel (shared send bucket across addons), Widgets (incl. the minimap
  button both addons use).
