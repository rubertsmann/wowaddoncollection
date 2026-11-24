# 030 Compact pet view: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.
SIM = wow-ui-sim v0.1.41: Blizzard's UI, but no 3D models and no units. It backs a row as evidence; it is not IN-GAME.

Baseline before work: `luajit tests/run.lua` -> 139 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 146 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | two modes, switch icon top left, same spot | test_load "the default start mode builds the pet view" + SetMode("full"); sim: switch click | READ-ONLY (+ SIM) | <wow-ui-sim>/petview-full.webp: the full window opened at the pet view's corner, 0 Lua errors | open | 2026-11-24 |
| R2 | /gg opens start mode, default minimal | test_load (Toggle builds the pet view); test_pet_view "settings default to minimal" | OFFLINE (default) / NOT-VERIFIED (in game) | 146 passed | partial | 2026-11-24 |
| R3 | round pet with outline, emotes, placeholder | sim shot (no models in the sim) | NOT-VERIFIED | needs checklist 1, 3 | open | |
| R4 | 4 ring gauges around the lower half, zone colours | test_pet_view ring and layout tests; sim | OFFLINE (logic) + SIM | <wow-ui-sim>/petview.webp: 80% green, 45% yellow, 20% red, 100% green | partial | 2026-11-24 |
| R5 | click = care action, wake while asleep, greyed when unusable | shared Panel.ClickCare / Panel.Care | READ-ONLY | needs checklist 2 | open | |
| R6 | heart: pulse on gain, dark below 0, count in tooltip | | NOT-VERIFIED | needs checklist 4 | open | |
| R7 | no text drawn | sim shot | SIM | petview.webp: no text on the view | partial | 2026-11-24 |
| R8 | drag, lock, full view opens at the same spot | | NOT-VERIFIED | needs checklist 5 | open | |
| R9 | options: start mode, opacity, size, lock, hide in combat | test_pet_view settings tests (limits) | OFFLINE (limits) / NOT-VERIFIED (page) | needs checklist 6 | partial | 2026-11-24 |
| R10 | combat fade, reopen at login | | NOT-VERIFIED | needs checklist 7, 8 | open | |
| R11 | live updates, animates only while shown | OnUpdate on the view frame (hidden frames get none) | READ-ONLY | | open | |
| RF1 | broken need values | test_pet_view "the ring lights a share of its segments; broken values light none" | OFFLINE | 146 passed | pass | 2026-11-24 |
| RF2 | broken saved options, off-screen position | test_pet_view "broken saved settings ...", "a window off the screen is moved back ..." | OFFLINE | 146 passed | pass | 2026-11-24 |
| RF3 | panel and pet view clicked in the same second | one Panel.state.careReadyAt for both | READ-ONLY | needs checklist 2 | open | |
| RF4 | combat starts while dragging | PetView.Hide stops the drag first | READ-ONLY | | open | |
| RF5 | no companion / model fails | placeholder path | NOT-VERIFIED | needs checklist 3 | open | |

## In-game checklist (things only the user can do)
Dev build: `tools/deploy.ps1` ran. RESTART the game (a new file; `/reload` does not read it). Dev commands start with
`/ggd`. Run `/console scriptErrors 1` first.
- [ ] 1. `/ggd`: the minimal view opens. It shows the companion in a round gold ring, four ringed buttons around its
  lower half, a heart top right and the switch icon top left. Screenshot.
- [ ] 2. `/ggd caught need hunger 40`, then click the food gauge: it pays, the ring fills and the pet plays its emote.
  Click the food gauge and the panel's food button in the same second: only one payment. Put the pet to sleep: the
  sleep gauge shows the wake icon, and a click wakes it.
- [ ] 3. Without a companion (a test character before its first catch): a dimmed placeholder shows. A click opens the
  full window at AZEcaught.
- [ ] 4. `/ggd caught hearts 5`, then `6`: the heart pulses. `/ggd caught hearts -3`: the heart turns dark red. Hover:
  "Hearts: -3".
- [ ] 5. Drag the view, then click the switch: the full window opens at the same top-left corner, and its top-left
  icon goes back. Options -> lock: dragging does nothing.
- [ ] 6. Options > AddOns > GuildGames-Dev AZEcaught: the "Minimal view" section shows. The opacity and size sliders
  change the view at once. Hovering shows the view at full opacity.
- [ ] 7. Pull a mob with the view open: it fades out and comes back after combat. Set "In combat" to shown: it stays.
- [ ] 8. `/reload` with the view open: it is open again. Close it with `/ggd`: after `/reload` it stays closed.

## Accepted gaps
- none yet
