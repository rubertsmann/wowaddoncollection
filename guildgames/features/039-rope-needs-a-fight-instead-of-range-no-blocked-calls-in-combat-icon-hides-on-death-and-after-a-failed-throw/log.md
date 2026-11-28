# 039 Rope needs a fight instead of range (no blocked calls in combat), icon hides on death and after a failed throw: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-26 15:43 | PLAN | Feature created
- Did: scaffolded `features/039-rope-needs-a-fight-instead-of-range-no-blocked-calls-in-combat-icon-hides-on-death-and-after-a-failed-throw/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-26 16:05 | BUILD | T1-T4 fight instead of range, icon hides on death and after a failed throw
- Did: `Core/Game/Api.lua` (InRopeRange and the dump's interactRange4 removed, snapshot `fighting`), `Core/Minigames/AzeCaught.lua` (`nofight`, `Tried`), `Core/Game/Catcher.lua` (refusal text, hide on health 0 / Tried, greyed icon + tooltip, threat event refreshes the icon), `UI/CatchItems.lua`, `Locales/deDE.lua`, tests in test_azecaught / test_items / test_item_batch / test_load; README, CHANGELOG (Unreleased), doc.md, verify.md
- Result: the four new assertions failed first (`expected nofight, got nil` ...), then pass
- Evidence: `luajit tests/run.lua` -> 193 passed, 0 failed
- Next: user checks in game (verify.md checklist); then release as 0.11.1

## 2026-11-26 16:06 | NOTE | health is hidden in every logged icon state
- Did: counted `health=` in the icon.state journal lines of GuildGames.lua, GuildGames-Dev.lua, GuildGames.lua.bak
- Result: 163, 267 and 173 entries `health=hidden`, none readable (the normal "above the threshold" case is not journaled). The "weak enough" rule then falls back to "it is the target", the throw rolls at the threshold and the ring has no colour.
- Evidence: SavedVariables journal lines `[caught.icon.state] ... health=hidden`
- Next: in-game probe in and out of combat (`/gg caught identity` on a hostile target) to see whether health or UnitHealthPercent is readable anywhere

## 2026-11-26 16:30 | VERIFY | emulator runs (wow-ui-sim)
- Did: ran `tools/wow-sim.ps1 -Addon guildgames` (load) and three scenarios with a faked hostile target (not fighting / fighting / dead), reading the icon state and the throw binding's chat; report returned through a Lua error because `print` fails in the emulator
- Result: 0 Lua errors; not fighting: icon alpha 0.5 + desaturated, throw refused "It is not fighting you"; fighting: icon in colour, throw armed; dead: icon hidden, "It is already dead."; CheckInteractDistance never called. The failed-throw case could not run (the emulator's timers did not fire)
- Evidence: verify.md "Emulator runs", evidence/sim-icon-nofight-vs-fight.png
- Next: user checks in the game (no blocked lines in a fight; icon stays gone after a snap); `/gg caught identity` on a hostile target in and out of combat for the health question

## 2026-11-26 16:40 | NOTE | released in 0.11.1
- Did: version 0.11.1 (TOC, Dev TOC, Init fallback), CHANGELOG section, RELEASE_NOTES player notes
- Result: status stays `verifying`: the in-game rows of verify.md are open
- Evidence: `luajit tests/run.lua` -> 193 passed, 0 failed
- Next: user checks in the game (verify.md checklist), then set `done`

## 2026-11-28 11:55 | DONE | closed at the status review
- Did: user reviewed the feature's state
- Result: status done
- Evidence: user: "yes it does" (2026-11-28)
- Next: none
