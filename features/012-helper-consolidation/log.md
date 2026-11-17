# 012 Helper consolidation: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-17 10:12 | PLAN | Feature created
- Did: scaffolded `features/012-helper-consolidation/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-17 10:13 | BUILD | T1-T4 shared helpers and call sites
- Did: added `U.Count/SortedKeys/Wipe/Refill/SanitizeMap/Me/ChatSafe` (Core/Util.lua), `Store.Knows/RecipeCount` (Core/Store.lua); replaced the copies in Api, Comm, Diag, Events, Init, Model, Notify, Offers, Scanner, Store, Trace, UI/Alerts, UI/Window, UI/DevProbe
- Result: no copy of the duplicated loops left (`grep "n = n + 1 end"` only finds U.Count)
- Evidence: `luajit tests/run.lua` -> `194 passed, 0 failed` (same as baseline)
- Next: T5 tests for the helpers

## 2026-11-17 10:14 | TEST | T5 tests/test_helpers.lua
- Did: 10 tests incl. malformed records (Knows/RecipeCount), Me before Store.Init, mixed-type SortedKeys, SanitizeMap with a throwing sanitizer; spec/verify/doc filled, INDEX + CHANGELOG updated
- Result: all pass
- Evidence: `luajit tests/run.lua` -> `204 passed, 0 failed`
- Next: user runs the in-game checklist in verify.md (UI/Events/Api changes are READ-ONLY until then), then set status done

## 2026-11-17 10:39 | DEVIATION | T6 Core/ split into layer folders (user request)
- Did: `git mv` of all 19 Core files into `Core/Base|Debug|Data|Net|Game|View/`; TOC (+ generated dev TOC) paths updated, load order unchanged; path references rewritten in code comments, tests, tools, docs/, eval/, review/, .claude/skills; tests/test_load.lua and tests/test_locale_files.lua now list files at any folder depth; README "Develop" has the layout table. History left as written: features/001-011 and the 0.x CHANGELOG entries
- Result: all tests pass; dev TOC file list identical to the live TOC
- Evidence: `luajit tests/run.lua` -> `204 passed, 0 failed`
- Next: user restarts the game after `tools/deploy.ps1` (TOC changed, /reload is not enough) and runs the in-game checklist in verify.md, then set status done
