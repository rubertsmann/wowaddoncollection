# 014 Guild game base: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 209 passed, 0 failed (2026-11-17)
Result after work:    `luajit tests/run.lua` -> 242 passed, 0 failed (2026-11-17, 6 runs)

| ID | Requirement / Review Focus | How verified (test name or steps) | Target level | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|---|
| R1 | Games tab, tab list | test_games_ui + in-game click through all 5 tabs | IN-GAME | NOT-VERIFIED | OFFLINE part: test_load "all TOC files run" (games tab built and selected, both identities), test_games_ui "the tab builds" | offline pass; in game pending | 2026-11-17 |
| R2 | stake/pick rules, 50/50, +/- stake | test_games (Flip), tools/coinflip.lua distribution | OFFLINE | OFFLINE | test_games "a flip wins or loses", "invalid stakes"; `luajit tools/coinflip.lua H 2000` -> heads 47.25%, record valid | pass | 2026-11-17 |
| R3 | stored before animation, no double/re-roll | test_games + test_games_ui; in-game `/reload` mid-flip | IN-GAME | NOT-VERIFIED | OFFLINE part: test_games_ui "a flip is stored before the coin moves" (stored at click, second click refused) | offline pass; /reload pending | 2026-11-17 |
| R4 | coin animation + effects + fallback | test_coinflip, test_games_ui; in-game look (screenshot/video) | IN-GAME | NOT-VERIFIED | OFFLINE part: test_coinflip (3), test_games_ui fallback, win and loss tests | offline pass; look pending | 2026-11-17 |
| R5 | record sync 2.3, schema 4 | test_sync, test_soak, test_hardening; two clients | MULTI-CLIENT | NOT-VERIFIED | OFFLINE part: test_games_sync (6, incl. 10-peer soak at 10% loss), test_hardening "014: protocol 2.3 and schema 4" | offline pass; two clients pending | 2026-11-17 |
| R6 | leaderboard scopes and order | test_games_model; `/tsd game sim 12` | IN-GAME | NOT-VERIFIED | OFFLINE part: test_games_model "sorts by net", "scope week"; test_games_ui scope buttons | offline pass | 2026-11-17 |
| R7 | recent flips feed | test_games_model; in game | IN-GAME | NOT-VERIFIED | OFFLINE part: test_games_model "the flip feed merges" | offline pass | 2026-11-17 |
| R8 | last week's winner | test_games_model | OFFLINE | OFFLINE | test_games_model "last week's winner" | pass | 2026-11-17 |
| R9 | "for fun only" note, no gold API used | grep for GetMoney/trade/mail calls in new files; in game | IN-GAME | NOT-VERIFIED | OFFLINE part: grep GetMoney, PickupPlayerMoney, SetTradeMoney, SendMail, SetSendMailMoney in Core/Play, UI/GamesTab.lua, UI/Animate.lua -> no match | offline pass; note in game pending | 2026-11-17 |
| R10 | 2.2 peers and 0.5.x files unaffected | test_hardening, test_sync; one client on 0.5.x | MULTI-CLIENT | NOT-VERIFIED | OFFLINE part: test_games_sync (HELLO without grev), test_hardening schema-5 readonly | offline pass | 2026-11-17 |
| R11 | offline tooling + dev commands | suite runs; `luajit tools/coinflip.lua`; `/tsd anim`, `/tsd game sim` | IN-GAME | NOT-VERIFIED | OFFLINE part: suite + tools/coinflip.lua run; test_load calls `game sim 3` in the dev identity | offline pass; /tsd anim pending | 2026-11-17 |
| R12 | slot machine: paylines, payouts, stored before reels move, own board, selector | test_slots (8), test_games_ui slot tests (3), test_load spin; in game: look of reels/lines/shower | IN-GAME | NOT-VERIFIED | OFFLINE part: 254 passed | offline pass; look pending | 2026-11-17 |
| RF1 | forged/broken records rejected | test_games Sanitize cases, test_sync wrong author | OFFLINE | OFFLINE | test_games "Sanitize rejects" (17 cases), test_games_sync "forged, broken and older GAMES" | pass | 2026-11-17 |
| RF2 | week rollover / ISO year edges | test_games PeriodKey vectors | OFFLINE | OFFLINE | test_games "PeriodKey gives ISO 8601 weeks" (6 vectors + Sunday 23:59:59), Sanitize "a peer already in the next week" | pass | 2026-11-17 |
| RF3 | reload/double click/readonly | test_games, test_games_ui; in-game `/reload` mid-flip | IN-GAME | NOT-VERIFIED | OFFLINE part: test_games "readonly", test_games_ui double click, refused flip, tween replace | offline pass | 2026-11-17 |
| RF4 | compatibility 2.2 / schema | test_hardening, test_sync | OFFLINE | OFFLINE | test_hardening "014: protocol 2.3 and schema 4 ... migration 3 -> 4", test_games "extra fields ... dropped" | pass | 2026-11-17 |
| RF5 | HELLO coalescing, simulated never sent | test_sync, test_games | OFFLINE | OFFLINE | test_games_sync "coalesced HELLOs", "never with simulated records"; test_games "simulated players never reach the db" | pass | 2026-11-17 |
| RF6 | animation quirks handled | `/tsd anim` P1-P8 answers + test_games_ui fallback | IN-GAME | NOT-VERIFIED | OFFLINE part: test_games_ui "unsupported animation type", "effects reuse one group" | offline pass; probe pending | 2026-11-17 |

## In-game checklist (things only the user can do)
- [ ] `powershell tools/deploy.ps1`, restart WoW, `/console scriptErrors 1`.
- [ ] `/tsd anim` -> send the chat output (P1-P8 lines) and screenshots of P5 (scale origin/text) and P8 (rotation).
- [ ] `/ts` -> Games tab: flip 5 times with stakes 10, 250, 100000, 0 (refused), 100001 (refused); coin lands on the shown result; screenshot of a win and a loss.
- [ ] Click Flip twice quickly -> only one flip recorded (leaderboard flips +1).
- [ ] Start a flip and `/reload` immediately -> after reload the flip is in the leaderboard exactly once.
- [ ] `/tsd game sim 12` -> leaderboard shows 12 fake players + me, sorted by net; switch This week / All time; `/tsd game sim 0` clears.
- [ ] `/tsd anim speed 0.25` then flip -> slow-motion coin for review; `/tsd anim speed 1`.
- [ ] Two guild members (L5): both flip; within ~1 min each sees the other on the leaderboard and in Recent flips; `/ts comm` shows no rejects.
- [ ] Slots: select "Slots", spin 5-10 times at 10s; reels stop left to right, the shown symbols match the result line; on a
      win the lines cycle, symbols glow, the payout counts up; `/tsd anim speed 0.25` for slow motion; screenshot of a win.
      Hover the machine: paytable. `anim tex` line lists the slot icons (any `false` = coloured tile fallback).
- [ ] One member on 0.5.x: orders/offers still sync both ways; no Lua errors.

## Accepted gaps
- <row id>: accepted by <user> on <date>, reason:
