# 038 Team arena fights: verification

Baseline before work: `luajit tests/run.lua` -> 180 passed, 0 failed (release 0.10.0)
Result after work:    `luajit tests/run.lua` -> 193 passed, 0 failed

Test names are from `tests/test_team_arena.lua` unless another file is named.

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Exactly 3 different own companions | "a team needs exactly 3 different companions of mine" | OFFLINE | 193 passed, 0 failed | pass | 2026-11-25 |
| R2 | Challenge with a team | "challenge and accept with teams; rewards ..." | OFFLINE | same | pass | 2026-11-25 |
| R3 | Defender sees the team in full, picks 3 in a dialog with the win chance | test_load (Decide -> TeamDialog, ClearSlot, Toggle, Confirm); simulator | IN-GAME | user report 2026-11-25 (dummy fights, carousel); evidence/sim-accept.png, sim-challenge.png (simulator only) | pass | 2026-11-25 |
| R4 | Sequential rounds, the winner carries its state, deterministic | "a 3 vs 3 fight runs in order; the round winner keeps its health ..." | OFFLINE | same | pass | 2026-11-25 |
| R5 | Replay shows both teams and swaps fighters | test_load (Watch, Step); simulator | IN-GAME | user report 2026-11-25; evidence/sim-replay.png (simulator only) | pass | 2026-11-25 |
| R6 | XP per entered companion plus knockouts; player record per fight; money adds up | "challenge and accept with teams; rewards go to every companion that entered ..." | OFFLINE | same | pass | 2026-11-25 |
| R7 | Buffs on all 3, one charge per fight | test_item_batch "a challenge spends the buffs once ..." | OFFLINE | same | pass | 2026-11-25 |
| R8 | Same-version gate, void and refunded when mixed | "different versions can neither challenge nor accept ..." | OFFLINE | same | pass | 2026-11-25 |
| R9 | Dummy team | "the dummy fields a valid team of three in my version" | OFFLINE | same | pass | 2026-11-25 |
| R10 | Old one-against-one leftovers refunded once | "peer teams with 2, 4 or bad fighters are dropped; one-against-one leftovers are refunded once" | OFFLINE | same | pass (accepted 1v1 stakes: not refunded, see doc) | 2026-11-25 |
| RF1 | Peer teams of 2/4/garbage | "peer teams with 2, 4 or bad fighters ..."; test_arena hostile sections | OFFLINE | same | pass | 2026-11-25 |
| RF2 | Both clients compute the same fight | "challenge and accept with teams ..." (A and B results equal) | OFFLINE | same | pass | 2026-11-25 |
| RF3 | A companion of an open team is released | settle skips missing uids (`AzeCaught.Companion` nil) | READ-ONLY | Arena.Settle | not run | 2026-11-25 |
| RF4 | Version changes after the accept | "different versions ..." (B updates before the fight) | OFFLINE | same | pass | 2026-11-25 |
| RF5 | Win chance speed in the dialog | cached per pick; 40 samples; not measured in game | READ-ONLY | - | not measured | 2026-11-25 |
| MC | Two real clients fight 3 vs 3 | two guild members on the same build | NOT-VERIFIED | needs a second player | open | 2026-11-25 |

## In-game checklist
- [ ] Guild > fight icon: the challenge modal shows "Your team" (3 names) and Change team; Send works.
- [ ] Fights > incoming challenge > Accept: the team dialog shows their 3 in full and your roster; the chance changes with the pick.
- [ ] Watch: the strip under the bars shows 3 squares per side; a new fighter enters with its name and model.
- [ ] A player on another version: the challenge is refused with both versions named.
- [ ] Two clients: both see the same winner.

## Accepted gaps
- 2026-11-25, user ("seems to be all working just fine", release request): the two-client fight (MC) and the READ-ONLY rows RF3, RF5 are accepted as open for the release; checked with the training dummy in game only.
