# 005 Profession scan buttons: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 62 passed, 0 failed (with the old AutoScan tests)
Result after work:    `luajit tests/run.lua` -> 53 passed, 0 failed (AutoScan tests removed with the module, +2 new)

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | One secure button per own profession, `/cast <name>` | window build smoke test; user clicked the buttons in game | OFFLINE + IN-GAME (user report) | tests/test_load.lua, user message 2026-11-16 | Kochkunst and Lederverarbeitung open their window; Kürschnerei does NOT (second spellbook entry, under investigation) | 2026-11-16 |
| R2 | Counter + tooltip | `model: own professions for the scan buttons ...`; tooltip code read | OFFLINE (data) / READ-ONLY (widgets) | tests/test_localization.lua | pass | 2026-11-16 |
| R3 | No addon code opens professions | `load: ...` asserts `Api.OpenProfession == nil` and `ns.AutoScan == nil`; grep | OFFLINE | tests/test_load.lua | pass | 2026-11-16 |
| R4 | Secure changes only out of combat | code read (`Api.InCombat` guard, `PLAYER_REGEN_ENABLED`) | READ-ONLY | UI/Window.lua | combat never simulated | 2026-11-16 |
| R5 | Counter refreshes after a scan | `DATA_CHANGED` -> `UI.Refresh` -> `refreshBar` (code read) | READ-ONLY | UI/Window.lua | not seen in game | 2026-11-16 |
| R6 | Old name-keyed records counted | `model: own professions ...` (Kürschnerei name-keyed) | OFFLINE | tests/test_localization.lua | pass | 2026-11-16 |
| R7 | Localized text | `locale files: ...`, `ui lint` | OFFLINE | tests/test_locale_files.lua | pass | 2026-11-16 |
| RF1 | No call the client blocks | see R3 | OFFLINE | tests | pass | 2026-11-16 |
| RF4 | UI build/refresh does not throw | stubbed build + refresh + tab switch; mutation check | OFFLINE | tests/test_load.lua | pass | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] **First, without the addon:** type `/cast Kochkunst` into chat (your own profession name). Does the profession window open? If not, tell me; the whole approach depends on this.
- [ ] `/reload`, open `/tsd`: no red "Interface-Aktion ..." message, no Lua error (`/console scriptErrors 1`).
- [ ] Top right of the Recipes tab: one icon per profession, a red 0 (not scanned) or a green number each; hovering shows the tooltip.
- [ ] While all icons show a red 0, a pulsing gold "HIER KLICKEN ->" (English: "CLICK HERE ->") is to the left of the icons and disappears once one profession has recipes.
- [ ] Click an icon: the profession window opens by itself; after a second the number on the icon turns green and the recipes appear in the list.
- [ ] Click the other icons: each opens its profession and fills.
- [ ] Optional: click an icon during combat (expect nothing to be broken; the bar only updates after combat).

## Accepted gaps
- none yet
