# 040 Roster move survives early journal lines, restore codes for lost companions: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 193 passed, 0 failed (plus the new failing T1 test)
Result after work:    `luajit tests/run.lua` -> 196 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | move survives an early journal line | `roster: the move still happens when a guild record writes a journal line before the companions are sanitized`; a real pre-update backup (kept outside the repo) loaded offline | OFFLINE | `196 passed, 0 failed`; backup: roster 1, hearts 19, xp 40, atk 10, active (unfixed code: roster 0, caught 0) | pass | 2026-11-26 |
| R2 | restore adds and activates the companion | `roster: a restore code brings a wiped companion back once, with hearts and arena training, and survives a reload`, `roster: a restore code also works when the collection entry is gone` | OFFLINE | `196 passed, 0 failed` | pass | 2026-11-26 |
| R3 | once per character, bad code refused, survives a reload | first restore test | OFFLINE | `196 passed, 0 failed` | pass | 2026-11-26 |
| R4 | code built from a backup | `RestoreCode` pinned in the first restore test; built from the real backup offline | OFFLINE | `GGR1;6500;55;elite;19;5;0;89;83;89;100;40;1;0;10;1;0;0;<name>` | pass | 2026-11-26 |
| RF1-RF4 | see spec | the three new roster tests | OFFLINE | `196 passed, 0 failed` | pass | 2026-11-26 |
| T4 | the affected player restores in game | `/gg caught restore <code>` on 0.11.2 | IN-GAME | the user reported "the command worked" (2026-11-26) | pass | 2026-11-26 |

## In-game checklist (things only the user can do)
- [x] After 0.11.2: the affected player types `/gg caught restore <code>`; chat says the companion is back and active (confirmed by the user).

## Accepted gaps
- none
