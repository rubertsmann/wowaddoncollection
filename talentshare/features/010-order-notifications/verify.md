# 010 Order notifications: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 178 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 187 passed, 0 failed (after tools/deploy.ps1 regenerated the dev TOC)
UI smoke (stubbed client, scratchpad harness): new order after start -> chat "New order: 3x [..] from .." + PlaySound(880); every OnClick/OnShow of window and options panel runs without error.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | relevance by scope | `notify: only orders for my profession count (scope profession)`, `notify: without any profession nothing is relevant`, `notify: my own new order, claimed or closed orders of others are not new` | OFFLINE | test run | pass | 2026-11-16 |
| R2 | my order claimed / done | `notify: my order claimed or done by someone else is news, by me it is not`, `notify: fresh reports each item once, a new claimer again` | OFFLINE (logic) / NOT-VERIFIED (two clients) | test run | pass | 2026-11-16 |
| R3 | badge, tab label, letter icon | checklist 1 | NOT-VERIFIED | needs game | | |
| R4 | Orders tab marks seen; first run quiet | `notify: seen orders stay seen, a new one appears`; checklist 2 | OFFLINE (logic) / NOT-VERIFIED (UI) | test run | pass | 2026-11-16 |
| R5 | chat/sound/screen/flash, throttle | harness; checklist 3-5 | READ-ONLY + stub run | scratchpad harness | | 2026-11-16 |
| R6 | options panel, `/ts options` | checklist 6 | NOT-VERIFIED | needs game | | |
| R7 | no markup from peers | 009 test `whisper: a peer recipe name cannot inject a link` (same `Model.ChatText`) | OFFLINE | test run | pass | 2026-11-16 |
| RF1 | login flood -> one sound | throttle in `UI/Alerts.lua` alert() | READ-ONLY | | | 2026-11-16 |
| RF2 | link injection | as R7 | OFFLINE | | pass | 2026-11-16 |
| RF3 | other-language profession | `notify: profession match works across languages (skill line id)` | OFFLINE | test run | pass | 2026-11-16 |
| RF4 | garbage settings | `notify: settings fall back to defaults, bad values are ignored`, `notify: mark seen forgets pruned orders and ignores garbage` | OFFLINE | test run | pass | 2026-11-16 |
| RF5 | board open -> no alert | `Alerts.Update` marks seen when `UI.OrdersVisible()` | READ-ONLY | | | 2026-11-16 |

## In-game checklist (`/console scriptErrors 1` first; needs a second guild member with the dev build, or two accounts)
- [ ] 1. Member B creates an order for a recipe of a profession A has: A's minimap button shows a red **1** and a letter icon; the window's tab reads **Orders (1)**.
- [ ] 2. A opens the Orders tab: badge and letter disappear. `/reload`: nothing comes back.
- [ ] 3. A gets a chat line "New order: ..." and hears the sound. An order for a profession A does not have: nothing.
- [ ] 4. A creates an order, B clicks "I'll craft it": A gets "{B} will craft your order ..."; B marks done: "... finished your order ...".
- [ ] 5. Options: switch on the screen message and the taskbar flash, alt-tab out, B creates an order: message mid-screen, taskbar flashes.
- [ ] 6. `/tsd options` and the **Options** button open the panel (game settings > AddOns, or own window); every checkbox sticks after `/reload`; Test plays the chosen sound.
- [ ] 7. Options > **Test all notifications**: every switched-on effect appears once (chat line, sound, screen message, red 1 + letter on the minimap button and `Orders (1)` for 8 s); switch to another window: the taskbar flashes after 3 s. With only the letter on: letter without number.

## Accepted gaps
- none yet
