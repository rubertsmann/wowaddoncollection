# 004 Clean command: verification

Baseline before work: `luajit tests/run.lua` -> 59 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 60 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Removes chars, catalog, orders, learned names, debug; keeps prefs/schema/me | `store: Clean empties everything in place, keeps preferences ...` | OFFLINE | tests/test_core.lua | pass | 2026-11-16 |
| R2 | Confirmation required | code read (`ns.Slash.clean`), slash registered (load test) | READ-ONLY | Core/Events.lua | not run in game | 2026-11-16 |
| R3 | In-place, holders keep working | same test (order board object keeps storing into the live table) | OFFLINE | tests/test_core.lua | pass | 2026-11-16 |
| R4 | Refresh, rescan on next open, HELLO | code read | READ-ONLY | Core/Events.lua | not run in game | 2026-11-16 |
| RF3 | Own empty record not published | NOT guarded beyond reopening the window (see spec Decisions) | NOT-VERIFIED | n/a | known gap | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] `/tsd clean`: prints what would be deleted, deletes nothing.
- [ ] `/tsd clean confirm`: prints "cleaned: ...", `/tsd` window is empty with the hint; minimap button and UI language are unchanged.
- [ ] Reopen `/tsd`: the automatic scan refills your recipes.
