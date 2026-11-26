# 040 Roster move survives early journal lines, restore codes for lost companions: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-26 21:04 | PLAN | Feature created
- Did: scaffolded `features/040-roster-move-survives-early-journal-lines-restore-codes-for-lost-companions/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-26 21:05 | TEST | T1 failing test reproduces the wipe
- Did: `tests/test_roster.lua`: schema 2 load with an outdated arena section in a guild record
- Result: failed as expected
- Evidence: `tests/test_roster.lua:177: the saur and two rats: expected 3, got 0` / `193 passed, 1 failed`
- Next: T2

## 2026-11-26 21:06 | BUILD | T2 migration marker
- Did: `Core/Data/Store.lua` migration [2] sets `caught.moveRoster`; `AzeCaught.SanitizePersisted` uses and clears it
- Result: suite green; a real pre-update backup (schema 2, kept outside the repo) loads into a roster of 1 with hearts 19, XP 40, training atk 10 def 1, active; the unfixed code loads the same file into 0 companions
- Evidence: `194 passed, 0 failed`
- Next: T3

## 2026-11-26 21:08 | BUILD | T3 restore code and command
- Did: `AzeCaught.RestoreCode` / `AzeCaught.Restore`, `restoredAt` sanitized on load, `/gg caught restore <code>` in `Core/Game/Catcher.lua`; spec, verify, doc, README, CHANGELOG
- Result: suite green
- Evidence: `196 passed, 0 failed`
- Next: T4 needs the release (user) and the affected player running the code in game

## 2026-11-26 21:34 | VERIFY | T4 restore worked in game
- Did: 0.11.2 released (`2c3631b`, CurseForge file 9833344); the affected player ran the code
- Result: the user reported "the command worked"
- Evidence: user statement in chat, 2026-11-26
- Next: T5

## 2026-11-26 21:35 | BUILD | T5 restore command moved to the dev build
- Did: `Core/Game/Catcher.lua` `commands.restore` -> `developmentCommands.restore`; README, CHANGELOG 0.11.3, RELEASE_NOTES 0.11.3, spec, doc, verify
- Result: suite green (see the release entry)
- Evidence: `luajit tests/run.lua` in the 0.11.3 release
- Next: none; feature done with 0.11.3
