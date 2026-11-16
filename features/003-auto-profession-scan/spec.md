# 003 Auto profession scan: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.2.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A player never has to open each profession page by hand: the addon opens each of the player's professions one after another, reads the recipes, and closes the window again.

## Why
In game the recipe list of a profession is only readable while THAT profession's window is open (`GetAllRecipeIDs` is empty otherwise). User report: "K is for professions and it shows 0 recipes ... after manually cycling through all pages it showed 11 recipes ... it isn't expected for the user that he cycles through all pages".

## Requirements
- R1: One click on "Scan professions" (Recipes tab) or `/ts autoscan` scans every profession of the character that has a skill line id, sequentially, and prints a one-line result per run ("Scanned: Kochkunst 10, ...").
- R2: Automatic and ON by default (`db.ui.autoScan`): every time the addon window opens, all professions are scanned if the last automatic scan is 10+ minutes old, otherwise only professions with no cached recipes (so the Blizzard windows do not flash on every open). Disable: `/ts autoscan off`, re-enable `on`. (Changed 2026-11-16 after the user asked "auto scan should default be on - so opening the window auto scans"; first version ran once per session and only for missing recipes.)
- R3: Safe: never starts or continues in combat; never hijacks a profession window the player has open (it tells them to close it); a profession whose list does not load is skipped after ~4 s and the run continues; the player's window is closed at the end.
- R4: A run that cannot work (no `C_TradeSkillUI.OpenTradeSkill` on the client) says so once and falls back to the manual hint; nothing errors.
- R5: Learning a new recipe updates the cache by itself (`NEW_RECIPE_LEARNED` triggers the debounced scan).
- R6: All new text is localized (enUS keys + deDE); the empty-list hint mentions the button.

## Non-goals
- No hiding of the Blizzard profession window (it is visible for ~1-4 s per profession).
- No scanning of other players' professions, no background scanning in combat or while a window is in use.

## Design
- `Core/AutoScan.lua` (new): `AutoScan.New(env)` state machine (pure, env-injected: supported, inCombat, windowOpen, professions, recipeCount, open, close, scan, after, done); `AutoScan.Instance()` wires the real Api/Scanner/Store/C_Timer; `AutoScan.Run(manual)` maps start failures to localized messages; `/ts autoscan [now|on|off]`.
- `Core/Api.lua`: `CanOpenProfession`, `OpenProfession(skillLineID)`, `CloseProfession`, `InCombat`, `IsProfessionWindowShown`.
- `Core/Events.lua`: `NEW_RECIPE_LEARNED` -> `scheduleScan`.
- `UI/Window.lua`: "Scan professions" button, auto-run on first open (`db.ui.autoScan ~= false`), updated empty-state hint.
- `Locales/deDE.lua`: new strings. `TalentShare.toc`: `Core\AutoScan.lua` after Scanner.
- Retry logic: after `open`, wait 1.2 s, `scan`, if the profession still shows 0 recipes retry up to 3 times at 1 s (the list loads asynchronously).

## Tasks
- [x] T1 (M): `AutoScan` state machine + `tests/test_autoscan.lua`
- [x] T2 (S): Api wrappers, wiring, slash command, event
- [x] T3 (S): UI button, auto-run, hint, locale strings, TOC
- [x] T4 (S): docs; in-game checklist

## Review Focus
1. RF1: Combat starts during a run -> run stops, window closed, no further opens -> test.
2. RF2: Player already has a profession window open -> no run, message -> test.
3. RF3: A profession that never loads must not stall the run or loop forever -> test (bounded retries).
4. RF4: Starting twice / a stale timer from an earlier run must not act on a newer run -> test.
5. RF5: Client without the open API -> message once, no error -> test + load smoke.

## Cross-cutting checklist
- [x] Protocol: unchanged. A completed scan that changes the record triggers the existing HELLO path.
- [x] Stored data: unchanged schema; `db.ui.autoScan` is a boolean preference.
- [x] Trust model: local only, no network input.
- [x] Localization: new keys in enUS (key = text) + deDE; lint test covers them.
- [x] Load order: `Core\AutoScan.lua` after `Core\Scanner.lua`, before `Core\Events.lua`.
- [x] Packaging: `Core/` is already shipped.
- [x] Tests: tests/test_autoscan.lua.
- [ ] Docs: README, CHANGELOG, doc.md.

## Decisions
- 2026-11-16: user-visible window flashing accepted (hiding Blizzard frames risks taint/unknown Forever behaviour); automatic run only when data is missing and once per session.
- 2026-11-16: `C_TradeSkillUI.OpenTradeSkill(skillLineID)` is assumed (retail API; NOT in the probe's API list), so it is feature-detected at runtime and verified in game with `/ts autoscan`.

## Open questions
- Does `C_TradeSkillUI.OpenTradeSkill` exist on Forever and accept the skill line ids from `GetProfessionInfo` (165/185/393)? (needs game)
- Does opening a second profession while one is open switch the list without closing the frame? (the state machine only opens the next one; if not, add a close in between)
