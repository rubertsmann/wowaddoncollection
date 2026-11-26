# 037 Companion roster (every catch its own companion, one active, frozen needs): spec

- Status: done
- Created: 2026-11-25
- Target version: 0.11.0 (together with 038, or alone if 038 is not ready)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md) | needed by [038](../038-team-arena-fights-3-vs-3-defender-picks-in-a-dialog-same-version-required/spec.md)

## Goal
Every caught monster becomes its own companion in an unlimited roster. Exactly one is active at a time, and each keeps its needs, hearts and arena progress while it rests.

## Requirements
- R1: Every successful catch adds one roster companion with its own local id (`uid`). Two catches of the same NPC are two companions with separate needs, hearts, arena XP, wins/losses and training.
- R2: The roster has no game limit. A technical cap of `ROSTER_LIMIT = 1000` only bounds the sanitizer. Catching at the cap is refused with a clear message.
- R3: Exactly one companion is active, or none. Switching is free, has no cooldown and keeps the state of both companions. The old companion is no longer released when its hearts are negative.
- R4: Only the active companion's needs decay. Resting companions are frozen: no decay, no sleep, no starving and no death. On switching back they continue exactly where they stopped.
- R5: A training session that is running when you switch is cancelled. Gold and energy are not refunded, and the Switch button warns about this first.
- R6: Arena XP, wins/losses and training points belong to the individual companion, not to its NPC kind. `Arena.Fighter(companion)` reads them from that companion.
- R7: A companion that dies (needs) leaves the roster. The collection entry keeps `got`, the count of catches ever made.
- R8: The guild record is unchanged: it still carries only the active companion (`caught.c`).
- R9: The Collection/Companion UI lists the roster: a row per companion with its name, level, rank and whether it is active, plus Switch and Release buttons. Release asks for confirmation and deletes that one companion.
- R10: Migration without backward compatibility (schema 2 -> 3):
  - Each collection entry with `caught = n` becomes n roster companions with full needs.
  - The current active companion keeps its live state.
  - Arena progress per NPC kind (`arena.npcs[npc]`) moves to the active companion if it is of that kind, otherwise to the first companion of that kind.

## Non-goals
- Nicknames for companions.
- Sending the roster to the guild (the opponent's team is only shown inside a fight, see 038).
- Team fights (038).

## Design
- `db.caught.roster = { [uid] = CompanionState + { uid, ar = { xp, w, l, tr }, restAt? } }`, `db.caught.activeID`, `db.caught.nextID` (uids "u1", "u2", ...).
  - `caught.active` stays a reference to `roster[activeID]`, so the existing readers (Catcher, Survivor, Runner, PetView) keep working.
  - Per-companion arena fields: `ax` arena XP, `aw`/`al` wins/losses, `tr` training points.
- `Core/Minigames/AzeCaught.lua` (changed):
  - `AzeCaught.AddToRoster(npcID, now)` on a catch.
  - `AzeCaught.Select(uid, now)` switches and keeps state, refusals `unknown|same|readonly`.
  - `AzeCaught.Release(uid)`.
  - `AzeCaught.Roster()` returns a sorted list.
  - `die` removes the companion from the roster.
  - `releaseOne` and the run-away on switching are removed.
- `Core/Minigames/Arena.lua` (changed):
  - `Arena.Npc(npcID)` is replaced by `Arena.Progress(companion)`, which reads the companion's own fields.
  - `Arena.Train` and `FinishTraining` use the companion's uid. `state.training.uid` replaces `.npc`.
  - Switching cancels the training through `Arena.CancelTraining()`.
- `Core/Data/Store.lua`: `SCHEMA = 3` and a `migrate2to3` step (R10).
- `AzeCaught.SanitizePersisted` / `Arena.SanitizePersisted`:
  - every roster entry is validated
  - the cap applies
  - `activeID` must exist
  - `training.uid` must exist
- UI:
  - `UI/AzeCaughtPanel.lua`: the collection rows become roster rows with Switch and Release. An NPC kind with several companions shows one row per companion.
  - `UI/ArenaView.lua` and `UI/PetView.lua` read the progress through `Arena.Progress`.
- Message shape: none (R8).
- Pure logic in AzeCaught/Arena; no new WoW calls.

## Tasks
- [x] T1 (M): Roster data, `AddToRoster`, `Select` keeping state, `Release`, death removes. Verify: tests/test_roster.lua "two catches of one NPC are two companions", "switching keeps both states", "release and death remove one".
- [x] T2 (S): Frozen needs: the tick touches only `caught.active`. Verify: "a resting companion does not change over 10 h of ticks".
- [x] T3 (M): Arena progress per companion, training by uid, cancelled on switch. Verify: "training belongs to one companion; switching cancels it without refund".
- [x] T4 (M): Schema 3 migration and the sanitizer (cap, dangling activeID/training). Verify: "a schema 2 db becomes a roster"; "garbage roster entries are dropped".
- [x] T5 (M): Roster UI: rows, Switch with the training warning, Release with confirmation. Verify: simulator shot, then in-game.
- [x] T6 (S): Locale (deDE), README, CHANGELOG. Verify: test_store_and_locale, tests green.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: `activeID` points to a missing or released companion -> no active companion, no error (T4).
2. RF2: Switching during a training -> the session is cancelled, it never finishes on the new companion (T3).
3. RF3: Several companions of one NPC, one dies -> only that one is removed, the collection count still matches (T1).
4. RF4: The migration runs twice or on a half-written db -> idempotent, nothing duplicated (T4).
5. RF5: A huge roster (1000) -> the panel stays responsive (rows are reused, as in the collection list today) (T5).

## Cross-cutting checklist
- [x] Protocol: unchanged. The record still carries the active companion only.
- [x] Stored data: `Store.SCHEMA` 2 -> 3, with `migrate2to3` (R10). The user accepted no backward compatibility (beta), and an older addon refuses a newer schema (`"newer"`).
- [x] Trust model: no peer data involved. The local roster is sanitized at load.
- [x] Localization: only ids and numbers are stored. New UI texts go into deDE.
- [x] Load order: no new files.
- [x] Packaging: no change.
- [x] Tests: new `tests/test_roster.lua` (adversarial cases: dangling ids, garbage entries, the cap, double migration).
- [x] Docs: README (roster), CHANGELOG, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-25: Every caught monster is its own companion with its own id (user, Q1).
- 2026-11-25: Resting companions' needs freeze (user, Q2).
- 2026-11-25: Switching is free, and a running training is interrupted (user, Q3). Gold and energy are not refunded (design choice, warned before).
- 2026-11-25: The guild sees only the active companion (user, Q4).
- 2026-11-25: No backward compatibility. Every monster caught so far becomes available in the roster (user, Q5).
- 2026-11-25: The run-away on switching is removed, because switching no longer resets a companion (design choice).
- 2026-11-25: The schema goes to 3. The technical cap is 1000 companions (design choice, for bounded saved data).

- 2026-11-25: DEVIATION: the move from schema 2 runs in `AzeCaught.SanitizePersisted` (roster missing -> built), the Store migration 2 -> 3 is empty. `AzeCaught.Reconcile` keeps `collection[npc].caught` equal to the roster count (dev `add`, tests and old data only change the count). Arena progress lives in `companion.ar`.

## Open questions
- none
