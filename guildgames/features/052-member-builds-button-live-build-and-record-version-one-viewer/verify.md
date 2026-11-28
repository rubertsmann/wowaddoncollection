# 052 Member builds button (live build and record version, one viewer): verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 218 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 220 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | button only for the maintainer hash | test_member_builds "only the viewer's name ..." | OFFLINE | 220 passed, 0 failed | pass (logic); button visibility in game NOT-VERIFIED | 2026-11-27 |
| R2 | rows: live build, record version, record time | test_member_builds "record version next to the live build ..." | OFFLINE | 220 passed, 0 failed | pass | 2026-11-27 |
| R3 | mismatch marked and first | same test (Stale-Realm first, mismatch = true) | OFFLINE | 220 passed, 0 failed | pass | 2026-11-27 |
| R4 | escaped / sanitized, garbage skipped | same test (Pipe, BadVer, Garbage rows) | OFFLINE | 220 passed, 0 failed | pass | 2026-11-27 |
| R5 | simulated records not listed | UI reads `Store.db.games`, not `Games.AllRecords` | READ-ONLY | UI/Window.lua buildMemberBuildsButton | - | 2026-11-27 |
| RF1-RF4 | see spec | same test | OFFLINE | 220 passed, 0 failed | pass | 2026-11-27 |
| R6 | arena section rewritten when missing / older | test_member_builds "arena version: ..." | OFFLINE | 233 passed, 0 failed | pass (in game NOT-VERIFIED) | 2026-11-28 |
| UI | tooltip renders in the client | hover the (i) bottom left of the GuildGames window | IN-GAME | user: "52 works as expected" | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
- [x] On the maintainer character: open the GuildGames window, an (i) icon sits at the bottom left; hover it: "Member builds", my build, one row per member (orange = record version differs from the live build).
- [ ] On any other character: no (i) icon.

## Accepted gaps
- R5 (READ-ONLY), "no (i) on other characters": closed at the user's status review (2026-11-28).
