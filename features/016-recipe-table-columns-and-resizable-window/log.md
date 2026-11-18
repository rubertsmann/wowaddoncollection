# 016 Recipe table columns and resizable window: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-18 15:53 | PLAN | Feature created
- Did: scaffolded `features/016-recipe-table-columns-and-resizable-window/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-18 15:58 | DECISION | Options panel, item level desc, five optional columns
- Did: asked the user; answers recorded in spec.md "Decisions" (toggles in the options panel; default sort item level highest first; columns Item level, Req. level, Profession, Skill, Category; no Crafters column)
- Result: spec.md filled (R1-R8, RF1-RF5, T1-T7)
- Evidence: spec.md
- Next: T1 tests first

## 2026-11-18 16:00 | TEST | Baseline
- Did: ran the suite before any code
- Result: one pre-existing failure from feature 015's working tree (Core/Play/Slots.lua present on disk but staged as deleted); left untouched
- Evidence: `luajit tests/run.lua` -> `211 passed, 1 failed`
- Next: T1

## 2026-11-18 16:05 | BUILD | T1-T6 pure module, model fields, API, resizable list, window, options
- Did: new `Core/View/RecipeTable.lua`, `UI/Table.lua`, `tests/test_recipe_table.lua`; changed `Core/View/Model.lua` (item fields), `Core/Game/Api.lua` (ItemDetails, QualityHex), `UI/Window.lua` (table, header sort, quality colour, all lists anchored, resize grip + saved size, debounced ITEM_INFO redraw), `UI/Alerts.lua` ("Recipe list" options section, fallback panel 600 high), `Locales/deDE.lua` (new keys; removed "{n} crafter(s)"), `TalentShare.toc`, `tests/run.lua`, `tests/test_load.lua` (stub GetFrameLevel)
- Result: tests green apart from the pre-existing failure
- Evidence: `luajit tests/run.lua` -> `222 passed, 1 failed` (only `Core/Play/Slots.lua exists but is not in TalentShare.toc`); `powershell tools/deploy.ps1` -> `generated ...\TalentShare-Dev.toc`
- Next: docs

## 2026-11-18 16:01 | NOTE | Correction: the BUILD entry above was written at 16:01, its header time 16:05 is wrong
- Did: n/a
- Result: n/a
- Evidence: `date` -> 2026-11-18 16:01
- Next: n/a

## 2026-11-18 16:01 | DOC | doc.md, verify.md, README, CHANGELOG, status, INDEX
- Did: wrote doc.md and verify.md; README Recipes tab + resizable window; CHANGELOG 0.7.0 lines; docs/status.md line; INDEX status verifying
- Result: feature is `verifying`: logic OFFLINE, screen behaviour NOT-VERIFIED
- Evidence: verify.md
- Next: BLOCKED on the user: restart the game, `/console scriptErrors 1`, run the in-game checklist in verify.md with `/tsd`, report results or screenshots

## 2026-11-18 16:05 | VERIFY | User confirmed in game
- Did: user ran the in-game checklist with the dev build and reported "works as expected"; verify.md rows set to IN-GAME (on-screen behaviour) or kept OFFLINE (pure logic); the stray `Core/Play/Slots.lua` (feature 015 leftover, copy lives in GuildGames) was removed
- Result: every requirement is IN-GAME or OFFLINE: status done
- Evidence: user message 2026-11-18; `luajit tests/run.lua` -> `223 passed, 0 failed`
- Next: commit, release 0.7.0 (with feature 015)
