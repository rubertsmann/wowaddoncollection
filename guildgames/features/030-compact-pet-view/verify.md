# 030 Compact pet view: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.
SIM = wow-ui-sim v0.1.41: Blizzard's UI, but no 3D models and no units. It backs a row as evidence; it is not IN-GAME.

Baseline before work: `luajit tests/run.lua` -> 139 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 147 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | two modes, switch icon top left, same spot | test_load "the default start mode builds the pet view" + SetMode("full"); sim: switch click | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R2 | /gg opens start mode, default minimal | test_load (Toggle builds the pet view); test_pet_view "settings default to minimal" | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R3 | round pet with outline, emotes, placeholder | sim shot (no models in the sim) | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R4 | 4 ring gauges around the lower half, zone colours | test_pet_view ring and layout tests; sim | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R5 | click = care action, wake while asleep, greyed when unusable | shared Panel.ClickCare / Panel.Care | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R6 | heart: pulse on gain, dark below 0, count in tooltip | | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R7 | no text drawn | sim shot | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R8 | drag, lock, full view opens at the same spot | | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R9 | options: start mode, opacity, size, lock, hide in combat | test_pet_view settings tests (limits) | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R10 | combat fade, reopen at login | | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| R11 | live updates, animates only while shown | OnUpdate on the view frame (hidden frames get none) | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| RF1 | broken need values | test_pet_view "the ring shows a share of 0..1; broken values show none", "the arc cell follows the share; nothing at 0, every cell reachable" | OFFLINE | 147 passed | pass | 2026-11-24 |
| RF2 | broken saved options, off-screen position | test_pet_view "broken saved settings ...", "a window off the screen is moved back ..." | OFFLINE | 147 passed | pass | 2026-11-24 |
| RF3 | panel and pet view clicked in the same second | one Panel.state.careReadyAt for both | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| RF4 | combat starts while dragging | PetView.Hide stops the drag first | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |
| RF5 | no companion / model fails | placeholder path | IN-GAME | user report 2026-11-24 ("every unconfirmed feature seems to be working as expected") with the 0.5.0 dev/live build | pass | 2026-11-24 |

## In-game checklist (things only the user can do)
Dev build: `tools/deploy.ps1` ran. RESTART the game (a new file; `/reload` does not read it). Dev commands start with
`/ggd`. Run `/console scriptErrors 1` first.
- [x] 1. `/ggd`: the minimal view opens. It shows the companion in a round gold ring, four ringed buttons around its
  lower half, a heart top right and the switch icon top left. Screenshot.
- [x] 2. `/ggd caught need hunger 40`, then click the food gauge: it pays, the ring fills and the pet plays its emote.
  Click the food gauge and the panel's food button in the same second: only one payment. Put the pet to sleep: the
  sleep gauge shows the wake icon, and a click wakes it.
- [x] 3. Without a companion (a test character before its first catch): a dimmed placeholder shows. A click opens the
  full window at AZEcaught.
- [x] 4. `/ggd caught hearts 5`, then `6`: the heart pulses. `/ggd caught hearts -3`: the heart turns dark red. Hover:
  "Hearts: -3".
- [x] 5. Drag the view, then click the switch: the full window opens at the same top-left corner, and its top-left
  icon goes back. Options -> lock: dragging does nothing.
- [x] 6. Options > AddOns > GuildGames-Dev AZEcaught: the "Minimal view" section shows. The opacity and size sliders
  change the view at once. Hovering shows the view at full opacity.
- [x] 7. Pull a mob with the view open: it fades out and comes back after combat. Set "In combat" to shown: it stays.
- [x] 8. `/reload` with the view open: it is open again. Close it with `/ggd`: after `/reload` it stays closed.

## Accepted gaps
- none yet
