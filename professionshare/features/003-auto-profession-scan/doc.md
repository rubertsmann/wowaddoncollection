# Automatic profession scan

Status: draft | Since version: 0.2.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The game only shows a profession's recipes while that profession's window is open. Instead of making you click through every profession page, TalentShare opens each of your professions one after another, reads the recipes and closes the window again (a few seconds in total, you will see the profession windows flash by).

## How to use
- Automatic (default on): every time you open the TalentShare window your professions are scanned. To keep the profession windows from flashing on every open, all professions are re-read at most every 10 minutes; in between, only professions with no cached recipes are scanned.
- Button: the small reload symbol at the top right of the Recipes tab (tooltip: "Scan professions") or `/ts autoscan` (dev build: `/tsd autoscan`).
- Turn the automatic run off or on: `/ts autoscan off` / `/ts autoscan on`.
- New recipes you learn are picked up automatically afterwards (`NEW_RECIPE_LEARNED`).

## How it works
- `Core/AutoScan.lua` is a small state machine: for each profession of your character that has a skill line id it calls `C_TradeSkillUI.OpenTradeSkill(id)`, waits 1.2 s, lets `Scanner.Refresh` read the open profession, retries up to 3 times at 1 s if the list is still empty (it loads asynchronously), then moves on. At the end it closes the window and, when something changed, announces the new data to the guild like any other change.
- It never starts or continues in combat, never starts while one of your profession windows is already open, and skips a profession that does not load.
- It needs `C_TradeSkillUI.OpenTradeSkill` (feature-detected). Without it you get a message and the manual way still works.

## Localization
Messages and the button are translated (enUS keys, deDE); profession names in the result line come from your own client.

## Limits and known issues
- The Blizzard profession windows are visible while they are scanned (they are not hidden on purpose).
- Whether `OpenTradeSkill` exists on WoW Forever is checked in game (`/ts i18n` prints it).
- Only your own character's professions; other members' data arrives through the guild sync.

## Changelog line
- Automatic profession scan: one click (or automatically on first open) reads all your professions instead of opening each page by hand; new recipes are picked up automatically.
