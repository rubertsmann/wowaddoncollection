# 005 Profession scan buttons: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.2.0
- Owner: claude
- Supersedes: [003 Auto profession scan](../003-auto-profession-scan/spec.md) (abandoned, see its log)
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Reading the recipes of the player's professions takes one click per profession (instead of cycling through the pages of the profession menu), without any addon call the game blocks.

## Why
Feature 003 called `C_TradeSkillUI.OpenTradeSkill` from addon code. In game (user report, German client): "kein Berufsfenster wurde jemals geöffnet" and the red message "Interface-Aktion auf Grund eines Addons fehlgeschlagen". The recipes of a profession are only readable while its window is open, so there is no passive way. User idea: a macro that opens the profession page directly (`/cast <profession>`). A real mouse click on a secure button may run such a macro; addon code may not.

## Requirements
- R1: The Recipes tab shows one icon button per own profession (up to 5, from `GetProfessions`/`GetProfessionInfo`), each a `SecureActionButtonTemplate` with `type=macro`, `macrotext="/cast <profession name>"`. One click opens that profession's window; the existing event-driven scan then stores its recipes.
- R2: Each button shows the number of stored recipes (green) or 0 (red, icon tinted red = not scanned yet) and a tooltip (name, rank/max, recipe count or "not scanned yet", "click to open this profession and read its recipes").
- R3: No addon code opens, closes or toggles professions (no `OpenTradeSkill`, no `CastSpellByName`); `Api.OpenProfession` and the `AutoScan` module are removed.
- R4: Secure attributes/visibility are only changed out of combat; in combat only the counters update, the rest is applied on `PLAYER_REGEN_ENABLED`.
- R5: The counters refresh after a scan (existing `DATA_CHANGED`), so the player sees the 0 turn into a number.
- R6: Old name-keyed records (0.1.0) count toward the right profession.
- R7: New text localized (enUS keys + deDE); `/ts clean` hint updated.

## Non-goals
- No one-click-for-all (a click may run exactly one protected action; chaining several `/cast` lines would replace the window before the list loaded). One click per profession is the honest minimum.
- No automatic closing of the profession window (`CloseTradeSkill` may be blocked too, unverified).
- No passive known-recipe detection (`IsPlayerSpell` needs a candidate recipe list, which only an opened profession provides).

## Design
- `Core/Api.lua`: `GetPlayerProfessions` also returns `icon` (local use only, never stored/sent); `Api.InCombat` kept; open/close helpers removed.
- `Core/Model.lua`: `Model.OwnProfessions(store, me, live)` -> `{ key, id, spellName, icon, rank, max, name, count }` sorted by name.
- `UI/Window.lua`: profession bar (secure buttons), `refreshBar`, combat deferral, empty-state hint.
- `Locales/deDE.lua`: 3 strings.
- Removed: `Core/AutoScan.lua`, `tests/test_autoscan.lua`, `/ts autoscan`, `ui.autoScan` default, reload-symbol button, `/ts i18n` OpenTradeSkill line.

## Tasks
- [x] T1 (S): remove AutoScan and the blocked API calls
- [x] T2 (S): `Model.OwnProfessions` + test
- [x] T3 (M): secure button bar in the Recipes tab, combat handling, locale
- [x] T4 (S): window build smoke test (stubbed widgets) in tests/test_load.lua; docs
- [ ] T5: in-game check by the user (verify.md)

## Review Focus
1. RF1: Addon code must not call a blocked/protected function -> test asserts `Api.OpenProfession` and `ns.AutoScan` do not exist.
2. RF2: Changing secure attributes in combat errors/blocks -> guarded by `Api.InCombat`, re-applied after combat (code read; combat not simulated).
3. RF3: An old name-keyed record must not show "0 recipes" for a scanned profession -> test.
4. RF4: UI build/refresh must not throw -> stubbed build test with a mutation check.

## Cross-cutting checklist
- [x] Protocol: unchanged. Stored data: unchanged (the icon is not stored).
- [x] Trust model: local only. Taint: secure template used as designed; no insecure call to protected functions.
- [x] Localization: strings in enUS keys + deDE, lint test green.
- [x] Load order: AutoScan removed from the TOC. Packaging: no change.
- [x] Tests: 53 passing (see verify.md).
- [ ] Docs: README, CHANGELOG, api-findings.

## Decisions
- 2026-11-16: `type=macro` + `/cast <name>` instead of `type=spell`, because it is exactly the macro the user proposed and works with the localized name the client reports.
- 2026-11-16: the profession windows stay open after a click (closing from addon code is not attempted).
- 2026-11-16: that `OpenTradeSkill` is what the client blocks is inferred from the user's report (nothing opened, red blocked-action message), not from a taint log.

## Open questions
- Does `/cast Kochkunst` (typed by the user) open the profession window on Forever? (the whole feature relies on it: test it first)
- Does a click on the secure button behave the same as the typed macro?
