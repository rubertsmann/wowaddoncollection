# 018 AZEcaught: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 69 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 95 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | fought NPCs are found | test_azecaught "found NPCs are added once..."; combat-log path only in game | OFFLINE (logic) / NOT-VERIFIED (combat log) | suite line | pass (logic) | 2026-11-20 |
| R2 | rope icon / key binding / `/gg catch` | test_load drives `/gg catch` and the binding under stubs; icon on nameplates needs the game (S3) | NOT-VERIFIED | in-game checklist 2-3 | open | |
| R3 | 3 s window, one roll per GUID | test_azecaught "a throw needs low health..." | OFFLINE | suite line | pass | 2026-11-20 |
| R4 | chance formula | test_azecaught "health factor is logarithmic", "difficulty lowers the chance" | OFFLINE | suite line | pass | 2026-11-20 |
| R5 | catch marks caught + reward | test_azecaught "a successful roll catches..." | OFFLINE | suite line | pass | 2026-11-20 |
| R6 | scrollable collection | test_azecaught "model rows..." (order); UI in game | OFFLINE (rows) / NOT-VERIFIED (UI) | | open | |
| R7 | one companion, fresh on switch, run-away | test_azecaught "selecting starts fresh", "switching away with negative hearts" | OFFLINE | suite line | pass | 2026-11-20 |
| R8 | 3D model | needs the game (S1: display id capture) | NOT-VERIFIED | in-game checklist 4 | open | |
| R9 | four needs, schedule, thresholds | test_azecaught "needs reach needy exactly at their schedule", "sleep refills energy" | OFFLINE (logic) / NOT-VERIFIED (bars) | suite line | pass (logic) | 2026-11-20 |
| R10 | active time only, clamped ticks | test_azecaught "a huge tick is clamped" | OFFLINE | suite line | pass | 2026-11-20 |
| R11 | care buttons, prices, effects, emotes | test_azecaught "care: ..."; test_load clicks Feed/Pet/Sleep under stubs; effects and emotes need the game (S2) | OFFLINE (logic) / NOT-VERIFIED (effects) | | open | |
| R12 | hearts and streaks | test_azecaught "care: ...", "neglect costs a heart" | OFFLINE | suite line | pass | 2026-11-20 |
| R13 | death after 2 h starving | test_azecaught "starving for 2 h kills", "feeding in time stops the starve timer" | OFFLINE | suite line | pass | 2026-11-20 |
| R14 | minimap badge + schedule tooltip + toggle | test_load runs the tooltip and `notify on/off` under stubs | READ-ONLY | | open | |
| R15 | money pool | test_wallet "a new player starts with the 20g grant" | OFFLINE | suite line | pass | 2026-11-20 |
| R16 | Guild view leaderboard | test_azecaught "model rows..."; record round-trip test | OFFLINE (rows) / NOT-VERIFIED (two clients) | | open | |
| R17 | weekly payout | test_azecaught "the weekly payout pays last week's place once" | OFFLINE | suite line | pass | 2026-11-20 |
| R18 | stake limited by balance, all games | test_wallet "a stake above the balance is refused in every game", "a running survivor stake counts" | OFFLINE | suite line | pass | 2026-11-20 |
| R19 | automatic journal | test_azecaught "journal: own ring, filter, verbose echo, export line" + `journalHas` checks in every case | OFFLINE | suite line | pass | 2026-11-20 |
| R20 | manual commands | test_load runs every `/gg caught` sub-command (live and dev) without an error line | OFFLINE (no errors) / NOT-VERIFIED (output in game) | suite line | pass (no errors) | 2026-11-20 |
| RF1 | death without throw / twice | test_azecaught "a throw needs low health..." | OFFLINE | suite line | pass | 2026-11-20 |
| RF2 | huge dt | test_azecaught "a huge tick is clamped" | OFFLINE | suite line | pass | 2026-11-20 |
| RF3 | pool short for food | test_azecaught "a paid action is refused when the pool is short" | OFFLINE | suite line | pass | 2026-11-20 |
| RF4 | hostile peer section | test_azecaught "the record section round-trips..." (11 mutations) | OFFLINE | suite line | pass (found and fixed a nil-skip bug) | 2026-11-20 |
| RF5 | offline across weeks | test_azecaught "weekly payout..." | OFFLINE | suite line | pass | 2026-11-20 |
| RF6 | balance edges | test_wallet "a stake above the balance..." | OFFLINE | suite line | pass | 2026-11-20 |

## In-game checklist (things only the user can do)
Setup: `powershell tools/deploy.ps1` (regenerates GuildGames-Dev.toc; new files were added), **restart** the game,
`/console scriptErrors 1`. Then `/ggd caught verbose on` to see every journal line in chat.
- [ ] 1. `/ggd version` -> protocol 1.1, schema 2. `/ggd caught wallet` -> balance = 20g + your casino net.
- [ ] 2. Fight a hostile mob -> `/ggd caught collection` lists it (level, rarity). At <= 35% health a rope icon appears
  right of its nameplate (S3); `/ggd caught chance` shows the breakdown.
- [ ] 3. Click the icon (and once with the key binding from Options > Key Bindings > AddOns) -> "Rope thrown at ...";
  kill it within 3 s -> "caught" or "slipped out" with the chance. `/ggd caught force` makes the next roll catch.
- [ ] 4. Open `/ggd caught` -> Collection -> click the caught NPC -> Companion view shows its 3D model (S1). If it is
  white/empty: `/ggd caught log model`.
- [ ] 5. Feed / Water / Pet / Sleep: sparkles, an emote (S2: `/ggd caught probe` lists the animations the model has), bars
  refill, hearts change, balance drops by 50s / 25s.
- [ ] 6. `/ggd caught time 70` -> water bar needy, minimap badge "1", chat reminder; hover the minimap button -> schedule.
  `/ggd caught notify off` hides the badge.
- [ ] 7. Bet more than the balance in the coin flip -> "Not enough money in the pool".
- [ ] 8. Two guild members with companions -> both appear in Guild view, sorted by level (MULTI-CLIENT).
- [ ] 9. After the checks: `/ggd caught export` and `/ggd caught log 40`, screenshot or paste into evidence/.

## Accepted gaps
- (none yet)
