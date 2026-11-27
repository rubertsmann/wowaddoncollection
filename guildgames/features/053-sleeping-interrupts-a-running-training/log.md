# 053 Sleeping interrupts a running training: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-28 00:24 | PLAN | Feature created
- Did: scaffolded `features/053-sleeping-interrupts-a-running-training/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-28 00:26 | BUILD | T1-T2 sleep cancels the running training
- Did: `Core/Minigames/AzeCaught.lua` (Care: cancel on sleep, result.trainingCancelled), `UI/AzeCaughtPanel.lua` (chat line, tooltip warning), `Locales/deDE.lua`, test in `tests/test_arena.lua` (written first, failed: expected true, got nil)
- Result: offline suite green; in game not seen
- Evidence: `luajit tests/run.lua` -> 234 passed, 0 failed
- Next: user checks R4 in game (verify.md checklist); ship with the next release

## 2026-11-28 00:45 | NOTE | released with 0.15.0
- Did: user checked it in game ("looks good"); shipped in 0.15.0 together with the removal of the Survivor / Companion Dash hitbox markers and tower glow
- Result: released
- Evidence: `luajit tests/run.lua` -> 234 passed, 0 failed
- Next: confirm R4 (chat line, tooltip warning) explicitly in verify.md, then set done
