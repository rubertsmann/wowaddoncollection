# 032 Arena watch to reveal and counter offers: verification

SIM = wow-ui-sim (`tools/wow-sim.ps1`): Blizzard's UI without the server; it backs a row as evidence, it is not IN-GAME.
Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `147 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `152 passed, 0 failed`

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | fighters: result + money after watching, "ready" once | test_arena "challenge, accept, bets and settlement ..." (nothing paid, no W/L, `answered,ready` notices; then watched -> paid once) | OFFLINE | 152 passed, 0 failed | pass | 2026-11-24 |
| R1 | replay end / close marks watched and settles | test_load: Watch, Step, FinishReplay, StopReplay, then "the fight was settled" | OFFLINE | same | pass | 2026-11-24 |
| R1 | chat before / after watching | sim scenarios `ready`, `watched` | SIM | evidence/sim-ready.png ("Arena: your fight against Arenadummy is decided. Watch it ..."), evidence/sim-watched.png ("Arena: Arenadummy beat your companion.", w+l=1) | pass | 2026-11-24 |
| R2 | bettors wait too | test_arena: C gets `betready`, paid after watching | OFFLINE | same | pass | 2026-11-24 |
| R3 | auto reveal after 24 h | test_arena "an unwatched fight settles by itself after REVEAL_AFTER ..." | OFFLINE | same | pass | 2026-11-24 |
| R4 | list hides the result until watched | sim: row shows "watch!" (orange) before, the result after | SIM | evidence/sim-rows-contrast.png (rows 3 and 4) | pass | 2026-11-24 |
| R5 | counter: stake at once, one per challenge, no accept after it, only the challenged | test_arena "a counter offer (higher or lower) accepted ..." | OFFLINE | same | pass | 2026-11-24 |
| R5 | UI: wager box + Counter offer button on an incoming challenge | sim scenario `incoming` | SIM | evidence/sim-incoming.png, sim-rows-contrast.png (row 1) | pass | 2026-11-24 |
| R6 | challenger accepts: difference paid / returned, fight with the counter wager, bet window from the accept | test_arena counter test (3g and 0.4g counters to a 1g challenge) | OFFLINE | same | pass | 2026-11-24 |
| R5/R6 | Accept / Decline in the dialog (not in the row), counter offer on the line below; dialog Accept answers the challenge | test_load: `widgets.acceptButton` exists, `ArenaView.Decide(true)` accepts the selected incoming challenge; sim scenarios `incoming`, `counterin` | OFFLINE + SIM | evidence/sim-dialog-buttons.png (contrast-boosted): Accept, Decline / 5 gold, Counter offer; Accept, Decline / Stop | pass | 2026-11-25 |
| R6 | UI: counter offer to my challenge shown with the amount | sim scenario `counterin` | SIM | evidence/sim-counterin.png ("Counter offer: 12g", Stop) | pass | 2026-11-24 |
| R7 | declined / stopped / expired counter refunds both once | test_arena "a declined, stopped or expired counter offer refunds both stakes once" | OFFLINE | same | pass | 2026-11-24 |
| R8 | both busy while countered | test_arena counter test: `Busy` for A and B | OFFLINE | same | pass | 2026-11-24 |
| R9 | notices countered / counteranswered | test_arena counter test (kinds and wager) | OFFLINE | same | pass | 2026-11-24 |
| RF1 | money adds up with higher and lower counters | test_arena counter test: "nothing created or lost" for both | OFFLINE | same | pass | 2026-11-24 |
| RF2 | a 1.2 peer keeps the section | test_arena "counter sections from peers are validated ...": the section without `co` stays valid, the counter is not in `an`; 1.2 sanitizer copies ch/an/bt only | OFFLINE + READ-ONLY (the old sanitizer itself is not run) | same | pass | 2026-11-24 |
| RF3 | same fight on every client after a counter | test_arena counter test: A and C compute the same winner and event count | OFFLINE | same | pass | 2026-11-24 |
| RF4 | watch gate | see R1-R3 | OFFLINE | same | pass | 2026-11-24 |
| RF5 | hostile `co` entries | test_arena "counter sections ...": wager too high, bad fighter, counter in the challenger's own record, `ca`+`cd` together | OFFLINE | same | pass | 2026-11-24 |
| R1, R4, R5, R6 | dev build with the arena dummy: request, counter offer (icons, box), skip, "watch!", Watch, result after the replay | user in game (steps in the checklist below) | IN-GAME | user: "looks good", then "works" (2026-11-25) | pass | 2026-11-25 |
| ALL | two real guild members | two guild members | NOT-VERIFIED | needs user | | |

## In-game checklist (things only the user can do)
- [x] Dev build alone (user, 2026-11-25: "works"): `/ggd arena request 5`, select the challenge, enter another amount, **Counter offer** -> the dummy accepts within 5 s -> `/ggd arena skip` -> chat says "decided, watch it", the row says "watch!" -> **Watch** -> after the replay the result line in chat and the pool changes.
- [ ] Two guild members: A challenges B, B counters, A sees the chat line and the row (accept / decline icons), A accepts -> fight after 5 min; a third member can bet once it is accepted.
- [ ] A declines a counter -> both get their wagers back.

## Accepted gaps
- none yet
