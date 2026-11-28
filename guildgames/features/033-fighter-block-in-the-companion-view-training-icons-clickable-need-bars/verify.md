# 033 Fighter block in the Companion view (training icons, clickable need bars): verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 152 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 152 passed, 0 failed (more assertions in the load test)

SIM = wow-ui-sim (Blizzard UI without the game, `tools/wow-sim.ps1`): layout and load, not the real client. It is not IN-GAME.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | level line + XP bar under the name, tooltip | sim screenshot; load test RefreshFighter | OFFLINE (+SIM) | evidence/sim-companion.png | pass | 2026-11-25 |
| R2 | four stat icons with points/maximum | load test "points/maximum below the icon" (0/25); sim shows 10/25, 3/25, 25/25 | OFFLINE (+SIM) | evidence/sim-companion.png | pass | 2026-11-25 |
| R3 | click trains at once; refusal in the status line | load test "train click", "busy while training" + the busy text | OFFLINE | test_load | pass | 2026-11-25 |
| R4 | training: shade + time on the icon, others greyed | load test "the time is on the training icon", "no time on the others"; sim (Speed lit, others grey) | OFFLINE (+SIM) | evidence/sim-companion.png | pass | 2026-11-25 |
| R5 | need bars are the care buttons (4 needs), greyed when unusable / cooldown | load test careBars mapping, careEnabled full/usable/cooldown, ClickCare | OFFLINE | test_load | pass (real mouse click on a bar: NOT-VERIFIED) | 2026-11-25 |
| R6 | Arena: Guild + Fights; saved "fighter" -> Guild | load test "no fighter page any more" | OFFLINE | test_load | pass | 2026-11-25 |
| R7 | no companion: no fighter block | READ-ONLY (RefreshFighter hides the holder, FillStatIcon(nil) hides the icons; PetView hides the button) | READ-ONLY | UI/ArenaView.lua RefreshFighter | - | 2026-11-25 |
| R8 | deDE | locale test (every key translated and used) | OFFLINE | test_store_and_locale | pass | 2026-11-25 |
| R9 | compact view training button + menu, closes on a click elsewhere | load test (button, 4 icons, opens, time on icon, closes); sim screenshot; outside click | OFFLINE (+SIM) | evidence/sim-minimal-training-menu.png | pass; the outside click (GLOBAL_MOUSE_DOWN on this client): NOT-VERIFIED | 2026-11-25 |
| RF1 | old saved page "fighter" | = R6 | OFFLINE | test_load | pass | 2026-11-25 |
| RF2 | asleep: Energy bar wakes, training refused "asleep" | READ-ONLY (RefreshCareButtons maps sleep -> wake; Arena.Train returns asleep) | READ-ONLY | | - | |
| RF3 | switched companion while training | FighterState drops a training of another npc | READ-ONLY | UI/ArenaView.lua FighterState | - | |
| RF4 | guide arrow finds Arena > Guild | existing load/guide tests | OFFLINE | test_load | pass | 2026-11-25 |
| RF5 | fits the 336 px stage | sim screenshot: icons + labels above the status line | SIM | evidence/sim-companion.png | pass | 2026-11-25 |
| ALL | simulator window (wow-ui-sim GUI, not the game): Companion view and the minimal training menu clicked through | user | SIM | user: "looks like it works fine" (2026-11-25) | pass | 2026-11-25 |
| R3, R5 | train by icon click, feed by bar click | user, live client | IN-GAME | user: "training and feeding works" | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] Full window > AZEcaught > Companion: the line "Arena level N  xW yL" and a purple XP bar under the name; hover it (stats, ability).
- [ ] Click the Food bar (hungry companion): it eats, 50s paid; Water bar when full: dimmed icon, tooltip says why, click does nothing.
- [ ] Click the Energy bar: sleeps; again: wakes.
- [ ] Click a stat icon: training starts (time on the icon, others grey); click another: "Already training." in the status line.
- [ ] Arena tab: only Guild and Fights.
- [ ] Minimal view (`/gg`, or the switch top left): the small button under the pet ("Training"); click: four icons; click one: training (time on it); click on the game world: the row closes; while training a gold ring around the button.
- [ ] `/ggd` / `/gg caught log 5 petView.train` shows `globalMouse=true` (if false, the row closes through a screen-wide catcher that eats that one click).

## Accepted gaps
- R9 outside click / compact menu, RF2, RF3 (READ-ONLY): closed at the user's status review (2026-11-28).
