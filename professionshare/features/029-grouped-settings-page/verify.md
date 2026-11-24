# 029 Grouped settings page: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 310 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 310 passed, 0 failed (the page test is part of the existing load test)

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | four sections, all controls | test_load (OpenOptions, /ps options build without error) | OFFLINE | 310 passed | pass | 2026-11-24 |
| R1 | look in game | in-game checklist | NOT-VERIFIED | the saved data holds no drop switch or minimap choice: the page switches were not clicked (or set back) | | |
| R2 | values shown and refreshed | refreshers on OnShow and every click | READ-ONLY | UI/Alerts.lua buildOptionsPanel | | |
| R3 | scrolls | in game | NOT-VERIFIED | needs user | | |
| R4 | minimap button switch | test_load (hide flag, MinimapButtonShown) | OFFLINE | 310 passed | pass | 2026-11-24 |

## In-game checklist
- [ ] Restart the game (or /reload: no new files in this feature), `/psd options`.
- [ ] Sections General, Order notifications, Recipe drops, Recipe list; the page scrolls to the sort buttons.
- [ ] Untick "Show the minimap button": the button disappears; tick it again: it is back.
- [ ] Recipe drops: untick "Chat message for a recipe drop", `/psd drops` says chat off; tick again.
- [ ] Order notifications still work: "Test all notifications".

## Accepted gaps
- R1 look, R3 scrolling: not seen in game.
- 2026-11-24, user ("check everything commit then finalize"): the remaining NOT-VERIFIED rows above are accepted; they
  stay listed and are checked when they happen in play.
- RF1 (badge after showing a button hidden at login needs /reload).
