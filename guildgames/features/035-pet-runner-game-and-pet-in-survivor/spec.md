# 035 Pet runner game and pet in Survivor: spec

- Status: done
- Created: 2026-11-25
- Target version: GuildGames 0.9.0 (protocol 1.4 additive, schema 2 unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A fourth game, **Companion Dash** (working title): a side-view endless runner where your companion runs, jumps over and
ducks under monsters from your collection, in front of a parallax background. Survivor also shows your companion, seen
from above, in place of the tower icon.

## Requirements
- R1: A new game in the game switch, after Survivor. It is locked while you have no active companion: the button tells you
  to catch a companion first.
- R2: The runner is your companion's model, seen from the side. It uses the run animation while running and the jump
  animation in the air. The duck pose is the model squashed and lowered.
- R3: Mouse controls in the play area. Pressing the top half jumps, and holding longer jumps higher. Holding the bottom
  half ducks, and ducking in the air drops faster. Space / Up jumps and Down ducks while the game window has focus.
- R4: Obstacles are monsters from your collection, found or caught. Every obstacle has the same box size, and the model
  is scaled to fit the box. While fewer than 3 are known, a few built-in monsters fill the pool.
- R5: Duck obstacles are flying monsters at head height (creature type Dragonkin / Elemental-air, or a flying beast
  family such as bat, bird, wind serpent). When the type is unknown (old entries), a random monster may fly instead.
- R6: Speed rises steadily up to a cap and the gaps shrink. One collision ends the run. The hitbox is slightly smaller than
  the drawing, so near-misses feel fair.
- R7: The parallax background is built from client textures (sky, clouds, far mountains, near hills, ground) in 4-5
  layers, each with its own speed and tint. The addon ships no new art.
- R8: A run pays 1g per full 100 m, at most 50g per day (server day, UTC), through Wallet kind `"runner"`. Before 100 m
  the run pays nothing.
- R9: There is a guild leaderboard. A new optional record section `runner` holds the best distance, a weekly best and
  recent runs. It is protocol 1.4 additive: older peers drop the unknown key. Peer data is checked against an
  allow-list.
- R10: The local stats are the personal best distance, the run count and the gold earned today. The gold earned today
  survives /reload.
- R11: In Survivor the tower icon is replaced by your companion's model seen from above, or from the steepest angle the
  client allows. It plays an attack animation on every weapon fire and faces the targeted monster. Without a companion,
  or if the model fails to load, the tower icon stays.
- R12: A shared helper sets up the companion model and plays animations (load, scale, play the first animation the model
  has). It is used by the runner, Survivor and the existing views where that fits.
- R13: The simulation runs offline: one pure module holds physics, spawning, collision, distance, payout and section
  sanitizing.

## Non-goals
- No copy of an existing game's name, dinosaur, art, sounds or look. Only the genre mechanics are used.
- No stakes or betting in the runner. It is free play with a daily cap.
- No real model-size hitboxes (the user chose the same size for all).
- No companion stats in the runner (no hearts or jump bonus).
- No new texture files.

## Design
- `Core/Minigames/Runner.lua` (new, pure):
  - `Runner.New(seed, pool)`, `Runner.Step(run, dt, input)` with a fixed 1/60 s tick, and `Runner.Collides(a, b)` for
    AABB collision.
  - Spawn table: ground or flying, gap = f(speed). Speed starts at 260 px/s, grows by 6 px/s per second and is capped at
    620. Gravity and the jump hold window are constants.
  - Distance: 1 m = 10 px.
  - `Runner.Payout(meters, paidToday)` gives min(floor(m/100), 50 - paidToday).
  - Daily bookkeeping in `db.runner = { day, paid, best, runs }`.
  - `Runner.SanitizeSection` and `Runner.SanitizePersisted`.
  - Events (jump, land, duck, spawn, crash, milestone) go to the UI.
- `Core/Data/Games.lua` (changed): the `runner` section allow-list hook, like `caught` and `arena`. It is not in
  `Games.ORDER` (not a casino game; it is out of the casino net).
- Flying is read from what the collection already stores (`entry.st.type` 2 = dragonkin, `entry.st.family` by enUS/deDE
  name); no AzeCaught or Api change.
- `UI/CompanionModel.lua` (new): the shared model helper (R12). It takes the load, the display id fallback to the
  creature, a scale-to-box, `Play(model, candidates, loop)`, and facing/pitch with pcall.
- `UI/RunnerView.lua` (new):
  - The play frame with the parallax layers: shapes from the addon's Disc texture and colour textures (clouds, tall
    ellipse mountains, hills, ground, pebbles), each moved by its share of the distance and wrapped over a span.
  - A pool of obstacle model frames (max 4 on screen, reused).
  - The runner model, the mouse halves, the key bindings, and the HUD: distance, best, gold today.
  - The end screen.
- `UI/SurvivorArena.lua` (changed): the companion model in the tower spot; attack on the `fire` events, throttled to
  the animation length.
- `UI/GamesTab.lua` / `UI/Window.lua` (changed): the new switch button (icon) with the locked state.
- `Locales/deDE.lua`, `GuildGames.toc`, `tests/run.lua`, `tests/test_runner.lua` (new), `tests/test_load.lua`.
- Data shape change:
  - `db.runner` (new, local).
  - It is additive. `Store.SCHEMA` stays 2 and sanitize drops bad values.
- Message shape change:
  - Record section `runner = { b = {d, t}, weeks = {["YYYY-Www"] = d}, recent = {{d, g, t}} }`.
  - Limits: d 0..1e6 m, g 0..50, at most 4 week keys, at most 10 recent entries.
  - Protocol MINOR 3 -> 4.
- Pure logic lives in `Runner.lua`; WoW calls only in `Core/Game/Api.lua` and the UI files.

## Tasks
- [x] T1 (S): (built as `/gg caught model`; user confirmed the top view in game) Probe the model API in the client with `/ggd probe`: `SetPitch` / `SetCamera` / `SetModelScale`,
  `HasAnimation`, and the ids for the Run (5), Jump start / Jump / Jump end (37/38/39) and Walk (4) animations. This
  decides the Survivor top view. Verify: probe output from the user (BLOCKED until then; the side-view fallback is
  built anyway).
- [x] T2 (M): `Runner.lua` physics, spawning and collision. Verify: `test_runner` (the jump clears a ground obstacle,
  the duck clears a flyer, standing still crashes, the same seed gives the same run).
- [x] T3 (S): Payout, daily cap and day rollover, persisted state and sanitize. Verify: `test_runner` (cap at 50, the
  next day resets, a 99 m run pays 0, garbage in db is dropped).
- [x] T4 (M): The `runner` record section, protocol 1.4, and the allow-list sanitize. Verify: `test_runner` and
  `test_games` (bad section dropped alone, limits, unknown keys dropped).
- [x] T5 (S): (no new field: `entry.st.type` / `st.family` already stored) The creature type on found NPCs and the pool builder with the built-in fallback. Verify: `test_runner`
  (empty collection gives the fallback pool, a flyer is flagged).
- [x] T6 (M): The `CompanionModel` helper (PetView/ArenaView keep their own code: see log DEVIATION). Verify:
  `test_load` and the simulator.
- [x] T7 (L): `RunnerView`: parallax, models, input, HUD, end screen, locked state. Verify: `test_load` and simulator
  screenshots (running, jump, duck, crash).
- [x] T8 (M): The Survivor pet in place of the tower, attack on fire, icon fallback. Verify: `test_load` and a
  simulator screenshot.
- [x] T9 (S): Locale (deDE), TOC, README, CHANGELOG, protocol.md, doc.md. Verify: locale lint and the comment test.
- [x] T10 (S): In-game check by the user (verify.md checklist). Verify: IN-GAME evidence.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Frame-rate spikes (a dt of 0.5 s after a loading screen) let the runner tunnel through an obstacle -> a fixed
   tick with substeps and a capped dt. Pinned by: T2.
2. RF2: The daily cap gets bypassed by /reload mid-run or by a clock change -> payout is booked at the run end against
   the persisted `paid`, and the day key comes from server time. Pinned by: T3.
3. RF3: A peer sends a huge or garbage `runner` section (d = 1e300, 1000 recent entries, a string d) -> it is dropped or
   clamped without breaking the rest of the record. Pinned by: T4.
4. RF4: A model never loads (display 0, unknown creature) or has no run/jump animation -> a fallback model or a plain
   frame is used, the game stays playable, and the Survivor tower icon stays. Pinned by: T6, T8.
5. RF5: Many PlayerModel frames hurt the frame rate -> obstacle models are pooled (max 4) and reused; layers scroll
   through tex coords, not by moving frames. Pinned by: T7.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive, MINOR 3 -> 4. The new optional `runner` record section; 1.3 peers drop it (allow-list copy).
- [x] Stored data: `Store.SCHEMA` stays 2. `db.runner` is new and sanitized at load (`Runner.SanitizePersisted`), so no
  migration is needed.
- [x] Trust model: the peer `runner` section is allow-listed, numbers are clamped, and it holds no strings.
- [x] Localization: only numbers and tokens are stored and sent; the UI text goes through `Text[...]`; the creature type
  is stored as a token, never client text.
- [x] Load order: `Runner.lua` after `Survivor.lua`; `UI/CompanionModel.lua` before PetView, ArenaView, SurvivorArena
  and RunnerView; `UI/RunnerView.lua` before GamesTab.
- [x] Packaging: new files under Core/ and UI/ are picked up by package.ps1; `features/` and `tests/` stay excluded.
- [x] Tests: `tests/test_runner.lua`, with the adversarial cases from RF1-RF3 plus load tests.
- [x] Docs: README, CHANGELOG, docs/protocol.md, doc.md (guildgames has no docs/status.md).

## Decisions (user answers and design choices, newest last)
- 2026-11-25: Money is free play: gold per distance, no stake (user Q1).
- 2026-11-25: Results are shared in a guild leaderboard, protocol 1.4 additive (user Q2).
- 2026-11-25: Without a companion the game is locked (user Q3).
- 2026-11-25: Obstacles are all seen and caught monsters, with a built-in fallback (user Q4).
- 2026-11-25: All obstacles are the same size; the model is scaled into one box (user Q5).
- 2026-11-25: Duck obstacles are flying monsters at head height (user Q6).
- 2026-11-25: Controls: click the top half to jump (hold for higher), hold the bottom half to duck, keys as well (user
  Q7).
- 2026-11-25: One hit ends the run; the speed ramps up (user Q8).
- 2026-11-25: The parallax uses built-in WoW textures, no new art (user Q9).
- 2026-11-25: The payout is 1g per 100 m, at most 50g a day (user Q10).
- 2026-11-25: The Survivor pet from above with attack animations ships in this feature and shares the model helper
  (user, extra request).
- 2026-11-25: Only the mechanics are used: no name, art or look of the existing runner game (design).
- 2026-11-25: The parallax is drawn from the addon's Disc texture and colour textures instead of client art files:
  still no new art, and it does not depend on client texture paths (design, within the user's "no new art" choice).
- 2026-11-25: The name stays "Companion Dash" / "Begleiter-Sprint" (user: "yes to everything").
- 2026-11-25: 1 m = 40 px: about 6.5 m/s at the start, 15.5 m/s at the top speed, so a one-minute run is about
  600-800 m (6-8g) and the 50g cap takes several good runs (design).

## Open questions
- Game name: "Companion Dash" is a working title (needs: user).
- Whether this client's PlayerModel can pitch the camera for a true top view (needs: game, T1 probe). The fallback is
  a steep 3/4 view facing the target.
- The parallax look in the real client (the simulator washes colours out) (needs: game).
