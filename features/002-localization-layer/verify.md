# 002 Localization layer: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> <N passed, 0 failed>
Result after work:    `luajit tests/run.lua` -> <N passed, 0 failed>

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | | | NOT-VERIFIED | | | |
| RF1 | | | NOT-VERIFIED | | | |

## In-game checklist (things only the user can do)
- [ ] <exact steps, expected result>

## Accepted gaps
- <row id>: accepted by <user> on <date>, reason:
