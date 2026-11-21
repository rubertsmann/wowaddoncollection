# 020 Companion arena: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 126 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 133 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | fighter: stats, training, level, morale, hunger | test_arena "levels need n x 50 XP; training ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R2 | training: cost, energy, time, one at a time, max | test_arena "levels ... training ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R3 | arena level from XP, +3% per level | test_arena "levels ..."; "challenge, accept ..." (XP gained) | OFFLINE | suite line | pass | 2026-11-21 |
| R4 | deterministic battle, abilities, balance | test_arena "the battle is deterministic ...", "abilities are balanced ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R5 | challenge, stake leaves once, no double challenge | test_arena "challenge, accept, bets and settlement ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R6 | accept / decline, only the opponent | test_arena "challenge ..."; "a decline or an expired challenge ..."; "hostile sections ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R7 | settlement: winner takes both, W/L, XP, once | test_arena "challenge, accept, bets and settlement ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R8 | side bets: window, own fight refused, odds, payout | test_arena "challenge, accept, bets ..." | OFFLINE | suite line | pass | 2026-11-21 |
| R9 | history and W/L in the guild preview | test_arena (history); test_load (guild view) | OFFLINE / NOT-VERIFIED (look in game) | suite line | pass offline | 2026-11-21 |
| R10 | arena view, train, answer, replay, guild fight icon + challenge modal | test_load "all TOC files run ..." (arena view: train, accept, watch, steps, tick; modal steps, fight icon) | OFFLINE / NOT-VERIFIED (look in game) | suite line | pass offline | 2026-11-21 |
| R12 | dev dummy and fake request | test_arena "the dev dummy accepts my challenge ..."; test_load (modal with the dummy) | OFFLINE / NOT-VERIFIED (in game) | suite line "134 passed, 0 failed" | pass offline | 2026-11-21 |
| R13 | one fight at a time, stop | test_arena "one fight at a time on both sides ..." and "an accept made before the stop ..."; test_load (Stop on the Fights page) | OFFLINE / NOT-VERIFIED (in game) | suite line "136 passed, 0 failed" | pass offline | 2026-11-21 |
| R11 | chat notices once | test_arena (noticed once); test_load (ArenaTick) | OFFLINE / NOT-VERIFIED | suite line | pass offline | 2026-11-21 |
| RF1 | same winner on every client | test_arena "challenge ..." (A's and B's result equal), determinism test | OFFLINE | suite line | pass | 2026-11-21 |
| RF2 | money never doubles | test_arena settle twice, refund once | OFFLINE | suite line | pass | 2026-11-21 |
| RF3 | garbage sections dropped alone | test_arena "hostile sections ..." | OFFLINE | suite line | pass | 2026-11-21 |
| RF4 | only the opponent's answer counts | test_arena "hostile sections ..." | OFFLINE | suite line | pass | 2026-11-21 |
| RF5 | no bet on own fight / after fight time | test_arena "challenge ..." (own, closed) | OFFLINE | suite line | pass | 2026-11-21 |
| MC | two real players: challenge, accept, bet, same result | in game with a guild member | NOT-VERIFIED | needs user + a second player | | |

## In-game checklist (things only the user can do)
- [ ] Restart the game (new files in the TOC), `/ggd arena`: the Fighter page shows the companion, stats and Train.
- [ ] Train a stat: gold and energy go down, the bar fills over 10 min of play time, chat says "Training done".
- [ ] With a guild member on the same build: Guild view -> Challenge; they get the chat line and Accept; after 5 min
  both get the result in chat and the same winner in Fights -> Watch.
- [ ] A third member bets in those 5 minutes and is paid when right.

## Accepted gaps
- none yet
