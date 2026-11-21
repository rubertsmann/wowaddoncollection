# Changelog

## MINOR 3 (2026-11-21)
- Every HELLO carries `ver` = "<addon version>/<MINOR>" (Channel); receivers keep it per member for the session
  (`Channel.PeerVersions`), note it in the HELLO trace line and `/<cmd> comm` prints both. Optional field, no protocol change.
- `Utility.CanonicalName`: on a client that reports no realm at all (WoW Forever), "Name-AnyRealm" now folds to the
  realm-free "Name". Before, a request from a member whose client still reports realms ("Drakk Nuk-SomeRealm") was
  ignored as "name mismatch", so that member never received the record. MINOR bump so this copy replaces an older
  MINOR 2 copy embedded by another addon, whatever the load order.

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
