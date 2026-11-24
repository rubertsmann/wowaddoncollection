# 029 Grouped settings page: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 11:44 | PLAN | Feature created
- Did: scaffolded `features/029-grouped-settings-page/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 11:40 | BUILD | Page rebuilt with sections
- Did: `UI/Alerts.lua` buildOptionsPanel rebuilt (scroll frame, addSection/addCheck, refreshers; sections General, Order
  notifications, Recipe drops, Recipe list); `UI/Window.lua` UI.MinimapButtonShown / SetMinimapButtonShown; deDE labels;
  test_load builds and opens the page and toggles the minimap switch; README, CHANGELOG
- Result: built; scaffold gave id 029 (028 is "Craft cooldowns grid", planned by another session)
- Evidence: `luajit tests/run.lua` -> 310 passed, 0 failed; tools/deploy.ps1 ran
- Next: user: in-game checklist in verify.md

## 2026-11-24 11:52 | DONE | Accepted by the user
- Did: user: "check everything commit then finalize"; the BUILD entry time was corrected (it was written as 13:30 without reading the clock)
- Result: done; the page itself was not seen in game (accepted gap in verify.md)
- Evidence: saved data has no ui.drops values and no minimapIcon.hide
- Next: none
