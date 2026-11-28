# 031 Catch refused in dungeons: spec

- Status: done
- Created: 2026-11-24
- Target version: GuildGames 0.6.0 (protocol 1.3, schema 2)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
`/gg catch` (and every other rope throw) inside a dungeon or raid tells the player, on screen and in chat, that
catching does not work there, instead of failing on the client's hidden unit values.

## Requirements
- R1: In a dungeon (`IsInInstance` kind "party") or raid ("raid") a throw is refused: no rope, `Catcher.Throw` returns false.
- R2: The refusal shows "Catching does not work in dungeons and raids." in the red overlay line (UIErrorsFrame).
- R3: The same text is printed in chat.
- R4: Outside instances the throw behaves as before (no overlay).
- R5: The text is localized (deDE).
- R6: A throw at an enemy tagged by someone else (`UnitIsTapDenied` true) is refused: "Someone else tagged this one: only your own kills can be caught."
- R7: A throw at an enemy farther than 28 yards (`CheckInteractDistance(unit, 4)` false) is refused: "Too far away: get within 28 yards to throw the rope."
- R8: When the client does not answer R6/R7 (nil, secret, error) the throw is allowed.

## Non-goals
- No change for scenarios, battlegrounds or arenas.
- The rope icon is not hidden in instances (the check sits in the throw, so a click gets the same message).

## Design
- Files touched: `Core/Game/Api.lua` (changed): `Api.InDungeon()`, `Api.ShowOverlay(text)`; `Core/Game/Catcher.lua`
  (changed): check at the start of `Catcher.Throw` (covers `/gg catch`, the key binding and the icon click);
  `Locales/deDE.lua` (changed): one string; `tests/test_load.lua` (changed): the refusal test.
- Data shape change: none. Message shape change: none.
- WoW calls only in `Core/Game/Api.lua`.

## Tasks
- [x] T1 (S): `Api.InDungeon`, `Api.ShowOverlay`, the check in `Catcher.Throw`, deDE string. Verify: test_load.
- [x] T2 (S): test: party/raid refuse with overlay + chat; open world shows no overlay. Verify: `luajit tests/run.lua`.
- [x] T3 (S): in game: `/gg catch` in a dungeon shows both. Verify: user.
- [x] T4 (S): `Api.IsTapDenied`, `Api.InRopeRange` in `Api.UnitSnapshot`; refusals "tapped" and "range" in the pure
  `AzeCaught.Throw` (Core/Minigames/AzeCaught.lua); texts in `Catcher.lua` + deDE; `interactRange4` in the unit dump.
  Verify: test_azecaught "a throw needs low health ...".
- [ ] T5 (S): in game: does `CheckInteractDistance(unit, 4)` answer for a hostile unit in combat on this client? Read
  `interactRange4` in the catch dump (`/gg caught log 20 catch`). Verify: user.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: `IsInInstance` missing or returning secrets -> `Api.InInstance` yields nil -> throw allowed as before. Pinned by: T1 (reuses the guarded `Api.InInstance`).
2. RF2: no `UIErrorsFrame` -> chat line only, no error. Pinned by: T1 (guard + pcall).
3. RF3: Retail restricts `CheckInteractDistance` on hostile units in combat -> it errors or returns nil -> R8 allows the
   throw (the range rule then does nothing in combat). If the client raises ADDON_ACTION_BLOCKED instead, the existing
   blocked-action handler logs it and the check must move to another API. Pinned by: T5 (in game).
4. RF4: health over 35% and out of range -> the health message wins (told first). Pinned by: test_azecaught.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged, nothing sent.
- [x] Stored data: unchanged.
- [x] Trust model: n/a, no peer data.
- [x] Localization: new key through `Text[...]`, deDE added.
- [x] Load order: n/a, no new file.
- [x] Packaging: n/a, no new file.
- [x] Tests: added to `tests/test_load.lua` (party, raid, open world).
- [x] Docs: README, CHANGELOG (Unreleased), doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: user asked that `/gg catch` print an overlay and a chat line saying it does not work in dungeons.
- 2026-11-24: the check is in `Catcher.Throw`, so the key binding and the icon click get the same message (one path).
- 2026-11-24: raids are included (same hidden unit values); the text says "dungeons and raids".
- 2026-11-24: overlay = UIErrorsFrame red line, as the care refusals already use.
- 2026-11-24: user added two limits: a distance to the enemy and "not tagged by others". User chose: within ~28 yards
  (CheckInteractDistance index 4), and allow the throw when the client does not say the distance.
- 2026-11-24: range/tag refusals go to chat only (like the other throw refusals); only the dungeon refusal also uses the overlay.

## Open questions
- none
