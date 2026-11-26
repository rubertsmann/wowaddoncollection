# 037 Companion roster: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 180 passed, 0 failed (release 0.10.0)
Result after work:    `luajit tests/run.lua` -> 193 passed, 0 failed (037 and 038 together)

Test names are from `tests/test_roster.lua` unless another file is named.

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Every catch is its own companion with its own id and progress | "two catches of one NPC are two companions with their own ids; the first becomes active" | OFFLINE | 193 passed, 0 failed | pass | 2026-11-25 |
| R2 | Technical cap, a full roster refuses the throw | "garbage entries, a dangling active id and the cap are handled on load" | OFFLINE | same | pass | 2026-11-25 |
| R3 | Free switching keeps both states, no running away | "the resting companion is frozen ..."; test_azecaught "switching keeps both companions as they are ..." | OFFLINE | same | pass | 2026-11-25 |
| R4 | Resting companions are frozen (10 h of ticks) | "the resting companion is frozen for 10 h, the active one decays; switching back continues" | OFFLINE | same | pass | 2026-11-25 |
| R5 | Switching cancels a training, no refund | "switching cancels a running training without refund ..." | OFFLINE | same | pass | 2026-11-25 |
| R6 | Arena progress per companion | "switching cancels ..." (training per uid), test_team_arena "rewards go to every companion that entered" | OFFLINE | same | pass | 2026-11-25 |
| R7 | Death and release remove one companion, `got` stays | "release and death remove exactly one companion ..." | OFFLINE | same | pass | 2026-11-25 |
| R8 | The guild record is unchanged (active only) | `AzeCaught.BuildSection` untouched; test_games_sync and test_azecaught section tests | OFFLINE | same | pass | 2026-11-25 |
| R9 | Roster rows, Switch with the training warning, Release with confirmation | test_load (select row by uid, confirm switch); simulator shot | IN-GAME | user report 2026-11-25 ("seems to be all working just fine"); evidence/sim-roster.png | pass | 2026-11-25 |
| R10 | Moving schema 2 data (active keeps state, progress per NPC moved, training kept) | "one-companion data moves to the roster ..." | OFFLINE | same | pass | 2026-11-25 |
| RF1 | A dangling activeID | "garbage entries, a dangling active id ..." | OFFLINE | same | pass | 2026-11-25 |
| RF2 | Training never finishes on another companion | "switching cancels a running training ..." | OFFLINE | same | pass | 2026-11-25 |
| RF3 | One of several of a kind dies | "release and death remove exactly one companion ..." | OFFLINE | same | pass | 2026-11-25 |
| RF4 | Moving twice duplicates nothing | "one-companion data moves ..." (loads the moved data again) | OFFLINE | same | pass | 2026-11-25 |
| RF5 | A large roster stays responsive | rows are pooled (CreateScrollList); not measured | READ-ONLY | - | not measured | 2026-11-25 |

## In-game checklist
- [ ] Collection > Caught lists one row per companion (two of the same NPC show twice), arena level "A n" and NPC level.
- [ ] Make companion on a resting one: the dialog says the current one rests; confirm; its bars are where they were.
- [ ] With a training running, the dialog warns; after switching the training is gone.
- [ ] Release asks first; the row is gone afterwards.
- [ ] After /reload everything is still there (roster, active companion, progress).

## Accepted gaps
- 2026-11-25, user ("seems to be all working just fine", release request): the remaining READ-ONLY rows (not measured) are accepted for the release.
