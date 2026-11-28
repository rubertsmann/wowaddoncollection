# 031 Catch refused in dungeons: verification

SIM = wow-ui-sim: Blizzard's UI without the server; it backs a row as evidence, it is not IN-GAME.
Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Result after work: `luajit tests/run.lua` -> `147 passed, 0 failed`

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | refused in party/raid | test_load "no throw in party/raid" | OFFLINE | 147 passed, 0 failed | pass | 2026-11-24 |
| R2 | overlay text | test_load "overlay in party/raid" (stubbed UIErrorsFrame) | OFFLINE | same | pass | 2026-11-24 |
| R3 | chat line | test_load "chat line in party/raid" | OFFLINE | same | pass | 2026-11-24 |
| R4 | open world unchanged | test_load "no dungeon overlay in the open world" | OFFLINE | same | pass | 2026-11-24 |
| R5 | deDE string | locale key test in the suite | OFFLINE | same | pass | 2026-11-24 |
| RF1 | IsInInstance missing/secret | reuses guarded `Api.InInstance` | READ-ONLY | Core/Game/Api.lua | - | 2026-11-24 |
| RF2 | no UIErrorsFrame | guard + pcall in `Api.ShowOverlay` | READ-ONLY | Core/Game/Api.lua | - | 2026-11-24 |
| R6 | tagged by others refused | test_azecaught: tapDenied = true -> "tapped" | OFFLINE | 147 passed, 0 failed | pass | 2026-11-24 |
| R7 | out of range refused | test_azecaught: inRange = false -> "range" | OFFLINE | same | pass | 2026-11-24 |
| R8 | unknown range/tag allowed | test_azecaught: throws without the fields succeed | OFFLINE | same | pass | 2026-11-24 |
| RF3 | CheckInteractDistance in combat | catch dump `interactRange4` | NOT-VERIFIED | needs user | | |
| RF4 | health told before range | test_azecaught "health is told first" | OFFLINE | same | pass | 2026-11-24 |
| SIM | R2, R3, R6, R7 in Blizzard's UI | `tools/wow-sim.ps1 -Addon guildgames -Mode shot -NoOpen -Lua evidence/sim-catch-refusals.lua` (IsInInstance and unit functions stubbed) | SIM | evidence/sim-catch-refusals.png: red overlay "Catching does not work in dungeons and raids." + the three chat lines; "0 Lua error(s) in GuildGames" | pass | 2026-11-24 |
| R1 (client) | real client in a dungeon | user in a dungeon | IN-GAME | user: companions cannot be caught in a dungeon | pass (refused); overlay/chat text not reported | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] Enter a dungeon, `/gg catch`: red line "Catching does not work in dungeons and raids." at the top and the same line in chat; no rope.
- [ ] Outside: `/gg catch` on a weak enemy still throws.
- [ ] Weak enemy tagged by another player: `/gg catch` -> "Someone else tagged this one ...".
- [ ] Weak enemy 30+ yards away (in combat): `/gg catch` -> "Too far away ..." or a throw; then `/gg caught log 20 catch`
  and report the `interactRange4` value (true/false/secret/error/nil) of the last dump.

## Accepted gaps
- R2/R3 in the client (overlay + chat text), RF3 (`interactRange4`), R6/R7 in game: closed at the user's status review (2026-11-28); the user reported only that catching is refused in dungeons.
