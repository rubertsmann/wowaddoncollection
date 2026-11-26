# 040 Roster move survives early journal lines, restore codes for lost companions: spec

- Status: done
- Created: 2026-11-26
- Target version: 0.11.2 (protocol 1.6 unchanged, schema 3 unchanged); the command moved to the dev build in 0.11.3
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The schema 2 -> 3 load keeps every catch and the active companion, and a companion already lost to the 0.11.0/0.11.1
bug can be brought back from a backup with a restore code.

## Requirements
- R1: Loading schema 2 data moves the active companion (state, hearts, arena progress, training) and every catch into
  the roster even when a journal line is written earlier in the same load (an outdated arena or companion section in a
  guild record).
- R2: `/gg caught restore <code>` (0.11.2; `/ggd caught restore <code>` from 0.11.3) adds the companion of a restore code (needs, hearts, streaks, arena XP/W/L, training)
  to the roster, counts it in the collection (also when the collection entry is gone) and makes it active.
- R3: A restore works once per character; a bad code is refused without a change; the result survives a reload.
- R4: Support can build the code from a backup (`AzeCaught.RestoreCode`).

## Non-goals
- Recovering data from a save already written by 0.11.0/0.11.1 without a backup (the counts are gone from the file).
- Protecting against a player forging a code (the saved data is local and editable anyway; one use per character).

## Design
- `Core/Data/Store.lua` (changed): migration 2 -> 3 sets `db.caught.moveRoster = true`.
- `Core/Minigames/AzeCaught.lua` (changed): `SanitizePersisted` moves when the marker is set (or the roster is missing)
  and clears it; new `RestoreCode` / `Restore`; `restoredAt` validated on load.
- `Core/Game/Catcher.lua` (changed): `restore <code>`, a live command in 0.11.2, a dev command (`/ggd`) from 0.11.3.
- Data shape change: `db.caught.moveRoster` (transient, cleared in the same load), `db.caught.restoredAt` (time). Schema stays 3.
- Message shape change: none.
- Root cause: `Games.SanitizePersisted` runs before `AzeCaught.SanitizePersisted`; a dropped section journals through
  `AzeCaught.State()`, which creates an empty `caught.roster`, so the "roster missing" check said "already moved" and the
  recount set every `collection[*].caught` to 0 and dropped the active companion.

## Tasks
- [x] T1 (S): failing test with an outdated arena section in a guild record. Verify: `roster: the move still happens when a guild record writes a journal line before the companions are sanitized`
- [x] T2 (S): migration marker. Verify: T1 test passes; a real pre-update backup loads with the companion
- [x] T3 (M): restore code + command. Verify: `roster: a restore code brings a wiped companion back once, ...`, `roster: a restore code also works when the collection entry is gone`
- [x] T4 (S): in game: the affected player runs the code. Verify: chat line + Companion view
- [x] T5 (S): the command moves to the dev build once the affected player is restored. Verify: suite green

## Review Focus (failure modes a happy-path test would miss)
1. RF1: journal line before the companion sanitize -> the move still happens. Pinned by: T1
2. RF2: the separator inside the NPC name -> name kept. Pinned by: T3
3. RF3: second restore / garbage code -> refused, nothing changed. Pinned by: T3
4. RF4: an existing active companion -> it rests, the restored one is active. Pinned by: T3

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged (nothing new is sent; the restored companion is published like any selected one).
- [x] Stored data: schema stays 3; marker set by the 2 -> 3 migration; `restoredAt` sanitized on load.
- [x] Trust model: the code is parsed by allow-list and validated by the same sanitizer as saved companions.
- [x] Localization: n/a: support command, English chat lines like the other `/gg caught` diagnostics.
- [x] Load order: n/a: no new file.
- [x] Packaging: n/a: no new file.
- [x] Tests: tests/test_roster.lua (three new tests).
- [x] Docs: README, CHANGELOG, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-26: a generic restore code instead of a restore hard-coded for one character (no real names in the repo; usable for every affected player).
- 2026-11-26: the restored companion becomes active (it was the active one when it was lost; switching is free).
- 2026-11-26: needs are rounded to whole numbers in the code; `asleep` is not restored (it comes back awake).
- 2026-11-26: the user releases the version; the affected player's local data is expected to be lost already, so the restore code is the recovery path.
- 2026-11-26: after the restore worked, the user chose to remove the command from the live build (0.11.3) to prevent forged codes; it stays a dev command.

## Open questions
- none
