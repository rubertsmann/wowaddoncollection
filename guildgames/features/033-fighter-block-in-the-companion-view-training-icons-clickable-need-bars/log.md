# 033 Fighter block in the Companion view (training icons, clickable need bars): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-25 00:22 | PLAN | Feature created
- Did: scaffolded `features/033-fighter-block-in-the-companion-view-training-icons-clickable-need-bars/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-25 00:25 | DECISION | user answers
- Did: asked 5 questions; answers in spec.md Decisions (Companion view only + drop Fighter page; 10/25; whole bar for all 4 needs; train at once; level line under the name). Then the user added R9 (compact view training button) and "implement fully, dev testing by me"
- Result: spec filled
- Evidence: chat
- Next: build T1, T2, T5

## 2026-11-25 00:29 | BUILD | T1 T2 T5 fighter block, clickable bars, compact training menu
- Did: UI/ArenaView.lua (fighter page -> FighterState, CreateStatIcon, FillStatIcon, BuildFighterBlock, RefreshFighter; pages Guild + Fights), UI/AzeCaughtPanel.lua (bars with careKey, care icons removed, AddCareTooltip, ShowStatus, block mounted), UI/PetView.lua (BuildTraining etc.), Core/View/Model.lua (layout.train), UI/Window.lua (comment), Locales/deDE.lua, tests/test_load.lua
- Result: all green
- Evidence: `luajit tests/run.lua` -> `152 passed, 0 failed`
- Next: T3 simulator

## 2026-11-25 00:29 | VERIFY | T3 simulator screenshots
- Did: tools/wow-sim.ps1 -Mode shot with evidence/sim-fighter.lua (SIM_SCENARIO companion / minimal prepended), cropped + contrast boosted
- Result: 0 Lua errors in GuildGames; the Companion view shows the level line, the bars (unusable ones dimmed), icons 10/25 3/25 Speed training 25/25 greyed; the minimal view shows the button at 6 o'clock and the open row with Speed lit
- Evidence: evidence/sim-companion.png, evidence/sim-minimal-training-menu.png
- Next: user tests in the dev build (verify.md checklist); then commit/release when asked

## 2026-11-25 00:45 | VERIFY | user in the simulator window
- Did: wow-ui-sim GUI with evidence/sim-fighter.lua (companion scenario); user clicked through
- Result: user: "looks like it works fine"
- Evidence: user statement in chat, 2026-11-25 (SIM level, not IN-GAME)
- Next: release 0.7.0; the live-client test (bar clicks, outside click closes the compact row, globalMouse in the journal) stays open

## 2026-11-25 00:46 | NOTE | cleanup for the release
- Did: removed the unused "train" icon-button style in UI/Window.lua
- Result: `luajit tests/run.lua` -> `152 passed, 0 failed`
- Evidence: test output
- Next: release 0.7.0

## 2026-11-28 09:53 | DONE | training and feeding confirmed in game
- Did: user: "033 training and feeding works"
- Result: status done; compact-menu outside click not reported (accepted gap)
- Evidence: user 2026-11-28
- Next: none
