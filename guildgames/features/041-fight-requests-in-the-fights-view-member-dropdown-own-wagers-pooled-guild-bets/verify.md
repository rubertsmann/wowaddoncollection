# 041 Fight requests in the Fights view (member dropdown, own wagers, pooled guild bets): verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 196 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 198 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | dropdown, greyed with the reason | `candidates: every other member is listed; ...`; `load: ...` (menu opens, a greyed pick is refused, hover text) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R1 | the look of the dropdown and its tooltips | in game, dev build: `/ggd arena members`, open the dropdown, hover each greyed row | NOT-VERIFIED | needs the user in game | - | - |
| R2 | request with 3 companions and a wager >= 1g | `pot: wagers below 1g are refused ...`; `load: ...` (Fight! opens the picker, bad / 0g wager stays, 1g sends) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R3 | swords clash after Send | `load: ...` runs `Animate.Clash` on stubs (no error, ends) | OFFLINE (runs only) | `198 passed, 0 failed` | pass | 2026-11-26 |
| R3 | the clash looks right | in game: send a request to the dummy | NOT-VERIFIED | needs the user in game | - | - |
| R4 | accept in the same picker with own wager, decline | `pot: ... the defender's own wager is in the fight`; `load: ...` (accept through the picker) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R5 | bets join the pot; fighters can't bet; once each | `pot: fighters and the guild settle the same pot; ...` | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R6 | split by share, losers lose all, rounding | `pot: the winning side gets its stakes back ...` | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R7 | each settles only themselves, once | `pot: fighters and the guild settle ...` (sum of all balances within the copper rounding) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R8 | Guild view fight icon gone | the panel no longer builds it; `load: ...` guide goes to the dropdown | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R9 | 0.11 leftovers finish under old rules | `pot: a bet ... with old fixed odds is paid by its odds`; `pot: an accept from before the pot ...` | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R10 | dummy accepts with its own wager after 20 s | `arena: the dev dummy accepts my challenge, ...`; `team arena: the dummy fields ...` | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R11 | dev event buttons and commands | `dev events: fake bettors join the pot, ...`; `load: ...` (every dev icon runs) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| R11 | the buttons in game | in game, dev build: each icon along the bottom of the Fights page | NOT-VERIFIED | needs the user in game | - | - |
| RF1 | 1g alone against 500g gets 501g | `pot: the winning side gets ...` | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| RF2 | a late bet: not counted, refunded once | `pot: fighters and the guild ...` (late part) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| RF3 | fighters' bets, other versions ignored | `pot: a bet from a player on another version stays out ...`; `own` refusal | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| RF4 | 0.11 accept without wager, odds bet | see R9 | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| RF5 | member turns busy before Send | `Arena.Challenge` refuses `theybusy` before taking the stake (existing test `arena: one fight at a time ...`) | OFFLINE | `198 passed, 0 failed` | pass | 2026-11-26 |
| - | a real request, accept and pot between two players | two guild members on the dev build, a third betting | NOT-VERIFIED | needs two (three) real players | - | - |

## In-game checklist (things only the user can do)
- [ ] Dev build, `/reload`, AZEcaught > Arena > Fights: the request row (dropdown + Fight!) and the dev icon row at the bottom.
- [ ] `/ggd arena dummy`, pick the dummy in the dropdown, Fight!, pick 3, wager 2, Send: the swords clash and "Request sent".
- [ ] Wait 20 s or press the dev accept icon: the fight shows "Pot: you 2g : xg Arenadummy"; press the coin icon (crowd) with the fight selected: the pot grows on both sides.
- [ ] Skip (stopwatch), Watch: the payout matches the pot share in the chat line.
- [ ] `/ggd arena members`: the dropdown shows Sparring-Test pickable (it accepts after 20 s) and four greyed members with a short reason; hovering shows the long one.
- [ ] Dev request icon: the dummy challenges you; Accept opens the picker with their team in the carousel and your wager box.
- [ ] Two real players on the same build: request, accept with a different wager, a third player bets.

## Accepted gaps
- none
