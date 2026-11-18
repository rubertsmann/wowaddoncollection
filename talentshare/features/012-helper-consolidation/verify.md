# 012 Helper consolidation: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 194 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 204 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | U.Count only, non-table -> 0 | test_helpers "Count: ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| R2 | U.SortedKeys | test_helpers "SortedKeys: ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| R3 | U.Wipe / U.Refill keep identity | test_helpers "Wipe and Refill ..."; existing Recanon/clean tests | OFFLINE | 204 passed | pass | 2026-11-17 |
| R4 | U.Me before Store.Init | test_helpers "Me: ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| R5 | one itemIDOf in Api.lua | code read (client-only file, not loaded offline) | READ-ONLY | Core/Game/Api.lua:173 | needs in-game | 2026-11-17 |
| R6 | Store.Knows | test_helpers "Store.Knows ..."; test_notify, test_orders | OFFLINE | 204 passed | pass | 2026-11-17 |
| R7 | Store.RecipeCount | test_helpers "Store.RecipeCount ..."; test_diagnostics | OFFLINE | 204 passed | pass | 2026-11-17 |
| R8 | SanitizeMap, same drop rules | test_helpers "SanitizeMap ..."; test_hardening, test_version_reset | OFFLINE | 204 passed | pass | 2026-11-17 |
| R9 | ChatSafe / ChatText unchanged | test_helpers "ChatSafe ...", "Model.ChatText ..."; test_notify | OFFLINE | 204 passed | pass | 2026-11-17 |
| R10 | no behaviour change | the 194 existing tests, unchanged | OFFLINE | 204 passed | pass | 2026-11-17 |
| RF1 | Me before Store.Init | test_helpers "Me: ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| RF2 | Knows on record without recipes | test_helpers "Store.Knows ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| RF3 | numeric key order kept | test_helpers "SortedKeys ..." | OFFLINE | 204 passed | pass | 2026-11-17 |
| RF4 | throwing sanitizer dropped | test_helpers "SanitizeMap ..." | OFFLINE | 204 passed | pass | 2026-11-17 |

UI files (`UI/Window.lua`, `UI/Alerts.lua`, `UI/DevProbe.lua`) and `Core/Game/Events.lua` are not loaded by the offline suite: their one-line changes are READ-ONLY until the in-game checklist is done.

## In-game checklist (things only the user can do)
- [ ] `powershell tools/deploy.ps1`, restart the game, `/console scriptErrors 1`, `/tsd`: window opens, Recipes/Orders/Available/Debug tabs fill, no Lua errors.
- [ ] Open a profession window (legacy API path uses `itemIDOf`): `/tsd dump` shows `produces` and reagent item ids.
- [ ] `/tsd offers scan` and `/tsd export`: no errors, the report lists characters/offers/orders.

## Accepted gaps
- none yet
