# 053 Sleeping interrupts a running training: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 233 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 234 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | sleep cancels a running training, no refund | test_arena "sleeping stops a running training ..." | OFFLINE | 234 passed, 0 failed | pass | 2026-11-28 |
| R2 | finished training kept | same test | OFFLINE | 234 passed, 0 failed | pass | 2026-11-28 |
| R3 | sleep without training unchanged | same test + test_azecaught sleep tests | OFFLINE | 234 passed, 0 failed | pass | 2026-11-28 |
| R4 | chat line + tooltip warning | in game: start a training, hover Sleep, click it | NOT-VERIFIED | needs the user | - | |
| RF2 | refused sleep cancels nothing | cancel runs after CareAvailability | READ-ONLY | AzeCaught.Care | - | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] Start a training, hover the energy bar: orange "Sleeping stops the running training (no refund)."; click it: the companion sleeps, chat says "The running training was cancelled.", the training timer is gone.

## Accepted gaps
- <row id>: accepted by <user> on <date>, reason:
