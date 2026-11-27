# 043 Survivor and Companion Dash polish: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 217 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 218 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Survivor top camera from the fitted distance | test_games_ui "models are framed by their size..." (x1.15, once per creature, re-measured for a new one, clamp) | OFFLINE | suite 218/0 | pass (logic) | 2026-11-27 |
| R1 | ...a big companion fits the tower spot in game | | NOT-VERIFIED | | needs in-game | |
| R2 | re-framed after a scale change, hidden models skipped | same test (RefreshAll) | OFFLINE | suite 218/0 | pass (logic) | 2026-11-27 |
| R2 | ...drawn size follows the window size in game | | NOT-VERIFIED | | needs in-game | |
| R3 | padded frames (camera scaled with them), hitbox markers | test_games_ui (pad -> camera, padded heights); hitbox drawing READ-ONLY | OFFLINE / READ-ONLY | suite 218/0 | needs in-game look | 2026-11-27 |
| R4 | target dropdown: opens, pick saves and closes, locked in a run, closed on start | test_games_ui survivor test | OFFLINE | suite 218/0 | pass | 2026-11-27 |
| R4 | ...look, no overlap, click-away close | | NOT-VERIFIED | | needs in-game | |
| R5 | icon kinds start -> giveup -> start, cashout after a minute (endless) | test_games_ui survivor test | OFFLINE | suite 218/0 | pass | 2026-11-27 |
| R6 | runner stats in a framed box | `UI/RunnerView.lua` statsBox; test_load builds the panel | READ-ONLY | suite 218/0 | needs in-game look | |
| RF1 | no / bad camera numbers -> 4 yd fallback | test (NaN distance, non-number position) | OFFLINE | suite 218/0 | pass | 2026-11-27 |
| RF2 | refresh only on a real scale change, shown + loaded models only | `placeWindow` compares scales; test | OFFLINE | suite 218/0 | pass | 2026-11-27 |
| RF3 | list closed on run start / panel hide | test (start); OnHide hook READ-ONLY | OFFLINE / READ-ONLY | suite 218/0 | pass | 2026-11-27 |
| RF4 | icon returns to the right kind | test | OFFLINE | suite 218/0 | pass | 2026-11-27 |

## In-game checklist (things only the user can do)
- [ ] `/reload`, make a big creature your active companion, open Survivor. Expected: it fits the tower spot like a small one. Drag the window grip smaller and larger: it keeps its size relative to the arena.
- [ ] Companion Dash: start a run with big monsters in the collection at a small and a large window size. Expected: nothing is cut off at a frame edge; a pulsing gold outline marks each monster's hitbox and a blue one the runner's; crashes happen when the outlines touch.
- [ ] Survivor: a pulsing gold ring marks the tower's hit circle above the companion; monsters are drawn over it.
- [ ] Survivor: the target dropdown shows the choice; a click opens the list, a pick closes it; a click elsewhere closes it; it is greyed during a run.
- [ ] Survivor: Start is a charge icon (tooltip "Start"); during a run a red X ("Give up"); in an endless run after 1:00 a coin ("Cash out"); after the run back to the charge icon.
- [ ] Companion Dash: stats and the last result sit in a gold-framed box under Start; a 4-line result still fits.
- [ ] If a companion is still too big or too small in Survivor: `/gg caught log 5 model` and paste the "survivor companion was framed" line (height, fitted).

## Accepted gaps
- none yet
