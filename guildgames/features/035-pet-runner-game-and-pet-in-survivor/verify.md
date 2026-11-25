# 035 Pet runner game and pet in Survivor: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 159 passed, 0 failed (0.8.0 release)
Result after work:    `luajit tests/run.lua` -> 170 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Fifth switch button, locked without companion | test_load runner block; sim "locked"; in game checklist 1 | IN-GAME | 170 passed; evidence/sim-locked.png; user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| R2 | Companion model runs / jumps | checklist 2 | IN-GAME | user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| R3 | Mouse halves, hold-to-jump-higher, fast fall, keys | test_runner "holding jump jumps higher; ducking in the air falls faster"; mouse/keys in game | OFFLINE (physics) / IN-GAME (input, checklist 3-4) | 170 passed; user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| R4 | Collection pool, one box size, fallback | test_runner "the pool uses the collection, flags flyers, falls back ..." | OFFLINE | 170 passed | pass | 2026-11-25 |
| R5 | Flyers at head height, duck passes | test_runner "a jump clears ...; a duck passes under a flyer; standing hits the flyer" | OFFLINE | 170 passed | pass | 2026-11-25 |
| R6 | Speed ramp, one hit ends, fair gaps | test_runner "standing still crashes", "a careful player survives 1500 m on several seeds" | OFFLINE | 170 passed | pass | 2026-11-25 |
| R7 | Parallax from built-in shapes | sim screenshot (layout only; the simulator washes colours out) | IN-GAME | evidence/sim-run.png; user: "looks and works fine" | pass | 2026-11-25 |
| R8 | 1g / 100 m, 50g/day, readonly books nothing | test_runner "payout 1g per 100 m ...", "read-only saved data books nothing"; checklist 4 | OFFLINE | 170 passed; user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| R9 | Guild section protocol 1.4, allow-list | test_runner "section sanitize drops garbage and keeps the rest of the record" | MULTI-CLIENT | 170 passed; user confirmed a second member sees the runner board | pass | 2026-11-25 |
| R10 | Local stats survive /reload | test_runner "saved data is repaired on load" (db.runner round trip) | OFFLINE | 170 passed | pass | 2026-11-25 |
| R11 | Survivor pet from above + attacks | checklist 5-6 | IN-GAME | user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| R12 | Shared model helper | UI/CompanionModel.lua used by RunnerView, SurvivorArena, /gg caught model | IN-GAME | runner and Survivor models confirmed by the user; PetView/ArenaView keep their own code (log DEVIATION, R12 narrowed) | pass | 2026-11-25 |
| R13 | Pure offline simulation | Core/Minigames/Runner.lua in PURE_FILES, test_runner | OFFLINE | 170 passed | pass | 2026-11-25 |
| RF1 | Hitch does not tunnel | test_runner "the same seed replays ...; a long frame is cut (no tunnelling)" | OFFLINE | 170 passed | pass | 2026-11-25 |
| RF2 | Daily cap vs reload/clock | payout booked at the end against persisted `paid`; server day | OFFLINE | test_runner payout test (day rollover) | pass | 2026-11-25 |
| RF3 | Garbage peer section | test_runner sanitize (1e300, string, bad week, gold 51, future time, 1000 recent) | OFFLINE | 170 passed | pass | 2026-11-25 |
| RF4 | Model fails to load | Load returns false -> icon fallback (runner obstacles), tower icon (Survivor) | IN-GAME | user in game: checklist 1-7 "yes to everything" | pass | 2026-11-25 |
| RF5 | Frame rate with models | 6 pooled obstacle models + 1 runner; shapes are moved, not recreated | IN-GAME | user in game: checklist 1-7 "yes to everything" (checklist 7) | pass | 2026-11-25 |

## In-game checklist (things only the user can do)
1. `/reload`, `/gg`, hover the switch: Companion Dash is the last button (running icon). Without a companion the play
   area says to catch one first and Start is grey.
2. With a companion: Start. Expected: the companion runs to the right (facing right), jumps with a jump animation,
   monsters from your collection come from the right facing left, flyers at head height. Screenshot mid-run.
3. Click top half quickly vs hold: the held jump is higher. Hold the bottom half: the companion squashes/ducks; a flyer
   passes over. Space / Up / Down work while a run is open; WASD movement is not blocked when no run is open.
4. Let it crash after > 100 m: the result shows meters and gold, the balance rises, the board shows the run.
5. `/gg caught model` with a companion: paste the chat line and screenshot the model shown for 15 s (is it seen from
   above?). If not from above, tell me which way it faces.
6. Survivor: Start a run. The companion replaces the tower icon and attacks when weapons fire; does it face the monsters?
7. Frame rate during a fast runner run (>300 m) compared with idle.

## Accepted gaps
- none: every row passed (user confirmation 2026-11-25)

## Survivor grass floor and clipping (user feedback)
- Confirmed in game by the user ("yes to everything", 2026-11-25); evidence/sim-survivor.png for the layout.
