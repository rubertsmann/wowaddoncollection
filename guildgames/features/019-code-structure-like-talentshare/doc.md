# Code structure like TalentShare

Status: verifying | Since version: next GuildGames release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Nothing new for the player: the code is reorganised like TalentShare's so both addons read the same way. The only
visible change: times in the companion panel and the minimap tooltip are rounded to the nearest minute and whole hours
show as "2h" (they showed "2h 0m"), the same as the NPC info overlay.

## How to use
- Developers: the folder table, the names and the "one helper per job" table are in `docs/coding-conventions.md`.
- Commands: unchanged (`/gg locale` moved from Core/Game/Events.lua to Core/Base/Locale.lua, same words).

## How it works
- Data (SavedVariables): no change (schema 2).
- Messages: no change (protocol 1.1).
- Modules: `Core/Base` (Init, Utility, Log, Locale), `Core/Debug` (Trace), `Core/Net` (Codec, Guard, Sync,
  Communication), `Core/Data` (Store, Games, Wallet), `Core/Minigames` (CoinFlip, Slots, Survivor, AzeCaught),
  `Core/View` (Model), `Core/Game` (Api, Catcher, Events with the event bus), `UI/Helpers.lua` (first UI file).
- New shared helpers: `Utility.Clamp`, `Api.PlaySoundNamed`, `Model.CommonRefusalText`, `UIHelpers.Settings`,
  `UIHelpers.SetTextureOr`, `UIHelpers.FrameLevel`; `Model.Duration` is the only duration text.
- Lints (tests/test_store_and_locale.lua): no module guards outside the listed exceptions; ids spelled `ID`.

## Localization
No new strings. The shared refusal texts keep literal `Text[...]` keys in Core/View/Model.lua, so the locale lint sees them.

## Limits and known issues
- Not yet started in the game client (verify.md IG1).
- The identity (build flag, names, slash dispatcher) and the diagnostic commands come from LibGuildSync MINOR 2
  (`Addon.Setup`, `Addon.AddDiagnosticCommands`), shared with TalentShare. `/gg comm` now also prints
  "incompatible peers=N".

## Changelog line
- Code reorganised like TalentShare (folders by role, shared helpers, naming lints); durations now read "2h" instead of "2h 0m" (feature 019).
