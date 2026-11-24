# 032 Arena watch to reveal and counter offers: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 23:47 | PLAN | Feature created
- Did: scaffolded `features/032-arena-watch-to-reveal-and-counter-offers/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 23:58 | BUILD | T1-T4 watch gate, counter offers, UI, docs
- Did: user chose (AskUserQuestion): result and money wait for the watch, auto after 24 h; bettors watch too; one counter, then the challenger decides; the counter stake leaves at once. Core/Minigames/Arena.lua (REVEAL_AFTER, watched, MarkWatched, Revealed, Counter, AnswerCounter, section `co`, `ca`/`cd`, states countered/rejected, refunds, busy, dummy accepts counters); UI/ArenaView.lua (counter box and button, counter rows, "watch!", replay end/close marks watched and settles); Core/Game/Catcher.lua (ready, betready, countered, counteranswered lines); Core/Base/Init.lua protocol 1.3; deDE; tests/test_arena.lua (old tests watch first; 5 new tests), tests/test_load.lua (protocol 3, counter buttons), tests/run.lua; README, CHANGELOG, docs/protocol.md, doc.md
- Result: offline green; the wow-ui-sim shows the four UI states with 0 Lua errors (screenshots are dim: the window's fade-in does not finish in the sim; evidence/sim-rows-contrast.png is contrast-boosted)
- Evidence: `luajit tests/run.lua` -> `152 passed, 0 failed`; evidence/sim-*.png (scenario script evidence/sim-arena.lua, run with `SIM_SCENARIO = '<name>'` prepended); tools/wow-sim.ps1 got `-Delay`
- Next: T5 in game (user): dev dummy flow in verify.md, then two guild members

## 2026-11-25 00:10 | BUILD | Accept / Decline moved into the dialog
- Did: user: "move the inline button down to the dialog where you can do the counter offer". UI/ArenaView.lua: the row icons are gone (rows show the state; Stop of a waiting challenge stays in its row); the dialog has Accept / Decline on line 1 (`ArenaView.Decide`: the challenge or the counter offer), the gold box + Counter offer (or Stop for a countered challenge) on line 2, the status below; a blocked accept is greyed out with the reason in the details. Two unused deDE keys removed. tests/test_load.lua now expects the dialog button and accepts through it.
- Result: offline green; sim shows both dialogs, 0 Lua errors
- Evidence: `luajit tests/run.lua` -> `152 passed, 0 failed`; evidence/sim-dialog-buttons.png
- Next: T5 in game (user), see verify.md

## 2026-11-25 00:20 | BUILD | Accept / Decline as icons
- Did: UI/ArenaView.lua: the dialog's Accept / Decline are `CreateIconButton` "accept" / "decline" (24 px) with tooltips (busy reason when blocked; "Accept the counter offer (12g)" / "Decline the counter offer" for a counter); the two deDE keys are back in use
- Result: offline green; sim shows the check and cross icons in both dialogs, 0 Lua errors
- Evidence: `luajit tests/run.lua` -> `152 passed, 0 failed`; evidence/sim-dialog-icons.png
- Next: T5 in game (user), see verify.md

## 2026-11-25 00:40 | VERIFY | dev dummy flow in game
- Did: user ran `/ggd arena request 5`, the counter offer / accept icons, `/ggd arena skip`, Watch
- Result: user: "looks good" (asked for icons, done), then "works"
- Evidence: user statement in chat, 2026-11-25
- Next: release 0.6.0; two-member test (counter offer between real players) still open
