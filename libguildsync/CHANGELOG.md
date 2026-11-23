# Changelog

## MINOR 6 (2026-11-23)
- `Widgets.CreateMinimapButton` also adds the button to the addon compartment (the numbered button at the top right
  of the minimap) through LibDBIcon's `AddButtonToCompartment`, on clients that have one. LibDBIcon keeps
  `settings.showInCompartment`, so the entry stays after a reload. With a button collector such as Leatrix Plus that
  hides or gathers minimap buttons, the window can still be opened from there. Tests: `tests/test_widgets.lua`.

## MINOR 5 (2026-11-23)
- Channel option `replaceableTypes`: a newer message of such a type (record answers) to the same recipient on the same
  channel replaces one still waiting with no chunk sent (trace `replaced`). A live session had 434 chunks waiting, the
  oldest 12 minutes, 53 of them outdated answers.
- Whispers to a member the guild roster shows offline (and not heard from in 120 s) are dropped from the queue instead
  of sent (trace `dropped`, "recipient offline (guild roster)"); the game answered those with "no player named ... is
  online". `Guild.GetGuildRoster` records the online flag, `Guild.IsOnline(name)` reads it; a channel's guild access may
  offer `IsOnline` (optional).
- `Channel.SendChunk` split out of `SendQueued`; new `Channel.RemoveWaiting`, `Channel.RecipientOffline`,
  `Channel.DropWhispersTo`; `channel.lastHeardAt`.

## MINOR 4 (2026-11-23)
- `Widgets.CreateMinimapButton` is rebuilt on the standard libraries: a LibDataBroker-1.1 `launcher` object registered
  with LibDBIcon-1.0, so button collectors (Leatrix Plus "Combine addon buttons", Minimap Button Bag, ElvUI, ...) and data
  displays (Titan Panel, ChocolateBar) find it. They only pick up LibDBIcon buttons, so the hand-made button was missing.
  New options: `name`, `label`, `icon`, `settings` (LibDBIcon's saved table: minimapPos, hide, lock), `defaultPosition`, `onClick`,
  `onTooltip`. LibDBIcon owns placement and dragging (left-drag now). The counter badge is kept; the icon changes
  through `button.dataObject.icon`. Returns nil when the libraries are not loaded. `Widgets.MinimapButtonOffset` and its
  constants are removed. **Breaking:** the embedding addon must load CallbackHandler-1.0, LibDataBroker-1.1 and
  LibDBIcon-1.0 before this library; the old saved angle is not carried over.

## MINOR 3 (2026-11-21)
- Every HELLO carries `ver` = "<addon version>/<MINOR>" (Channel); receivers keep it per member for the session
  (`Channel.PeerVersions`), note it in the HELLO trace line and `/<cmd> comm` prints both. Optional field, no protocol change.
- `Utility.CanonicalName`: on a client that reports no realm at all (WoW Forever), "Name-AnyRealm" now folds to the
  realm-free "Name". Before, a request from a member whose client still reports realms ("Dorn Vask-SomeRealm") was
  ignored as "name mismatch", so that member never received the record. MINOR bump so this copy replaces an older
  MINOR 2 copy embedded by another addon, whatever the load order.
- `Widgets.CreateMinimapButton`: the button sat at a fixed 80 px from the centre, INSIDE the larger Forever minimap. It
  now sits half the minimap's size + 5 px out (`Widgets.MinimapButtonOffset`, LibDBIcon's rule incl. square minimap
  shapes), so it lines up with other addons' buttons (Spoken), and follows the minimap when it is resized.

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
